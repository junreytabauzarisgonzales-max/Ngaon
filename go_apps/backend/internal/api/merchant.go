package api

import (
	"context"
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"time"

	"goapp/backend/internal/domain"
	"goapp/backend/internal/service"
)

func (a *API) invalidateMerchantCache(ctx context.Context, merchantID string) {
	if a.svc.Redis != nil && merchantID != "" {
		cctx, cancel := context.WithTimeout(ctx, 2*time.Second)
		_ = a.svc.Redis.InvalidateMerchantCache(cctx, merchantID)
		cancel()
	}
}

func (a *API) staffOf(r *http.Request) (domain.MerchantStaff, *domain.MerchantRow, error) {
	u := a.svc.St.Users[claimsOf(r).Sub]
	if u == nil {
		return domain.MerchantStaff{}, nil, errUnauthorized
	}
	st, isStaff := a.svc.St.Staff[u.Phone]
	if !isStaff {
		return st, nil, apiErr(403, "forbidden", "This number is not registered as a merchant")
	}
	row := a.svc.St.Merchants[st.MerchantID]
	if row == nil {
		return st, nil, errForbidden
	}
	return st, row, nil
}

func (a *API) merchantMe(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	st, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	ok(w, map[string]any{
		"merchant":   a.publicMerchant(row, nil, false),
		"role":       st.Role,
		"staff_name": st.StaffName,
	})
	return nil
}

func (a *API) patchStore(w http.ResponseWriter, r *http.Request) error {
	var raw map[string]json.RawMessage
	if err := decode(r, &raw); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	m := &row.Merchant
	get := func(k string, v any) bool {
		b, present := raw[k]
		if !present {
			return false
		}
		return json.Unmarshal(b, v) == nil
	}
	var b bool
	var n int
	var str string
	if get("is_open", &b) {
		m.IsOpen = b
	}
	if pu, present := raw["paused_until"]; present {
		if string(pu) == "null" {
			m.PausedUntil = nil
		} else {
			var t domain.UTC
			if json.Unmarshal(pu, &t) == nil {
				m.PausedUntil = &t
			}
		}
	}
	if get("prep_time_minutes", &n) {
		if n < 5 || n > 60 {
			return fieldErr("prep_time_minutes", "out_of_range", "5–60 minutes")
		}
		m.PrepTimeMinutes = n
	}
	if get("min_order_centavos", &n) {
		if n < 0 {
			return fieldErr("min_order_centavos", "invalid", "Invalid minimum")
		}
		m.MinOrderCentavos = n
	}
	var hours []domain.OpeningHours
	if get("hours", &hours) {
		m.Hours = hours
	}
	if get("logo_key", &str) {
		m.LogoURL = a.svc.FileURL(str)
	}
	if get("cover_key", &str) {
		m.CoverURL = a.svc.FileURL(str)
	}
	if get("name", &str) && strings.TrimSpace(str) != "" {
		m.Name = strings.TrimSpace(str)
	}
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), m.ID)
	pub := a.publicMerchant(row, nil, false)
	for _, uid := range a.svc.MerchantUserIDs(m.ID) {
		a.svc.Emit(uid, "merchant", "merchant.updated", map[string]any{"merchant": pub})
	}
	ok(w, pub)
	return nil
}

// ---------- orders ----------

func (a *API) ordersOf(merchantID string) []*domain.JobState {
	var out []*domain.JobState
	for i := len(a.svc.St.JobIDs) - 1; i >= 0; i-- {
		js := a.svc.St.Jobs[a.svc.St.JobIDs[i]]
		if js != nil && js.MerchantID == merchantID && js.Order != nil && js.Job.Status != "pending_payment" {
			out = append(out, js)
		}
	}
	return out
}

func (a *API) merchantOrders(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	status, from, to := q.Get("status"), q.Get("from"), q.Get("to")
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	var out []domain.MerchantOrder
	for _, js := range a.ordersOf(row.Merchant.ID) {
		ms := service.MerchantOrderStatus(js)
		match := ms == status
		if status == "done" {
			match = ms == "picked_up" || ms == "completed" || ms == "rejected" || ms == "cancelled"
		}
		if status == "" {
			match = true
		}
		d := domain.ManilaDate(js.Job.CreatedAt.Time)
		if !match || (from != "" && d < from) || (to != "" && d > to) {
			continue
		}
		out = append(out, a.svc.OrderView(js))
	}
	page, next := paginate(out, r, 50)
	okPage(w, page, next)
	return nil
}

func (a *API) orderByID(r *http.Request) (*domain.JobState, error) {
	_, row, err := a.staffOf(r)
	if err != nil {
		return nil, err
	}
	id := r.PathValue("id")
	for _, js := range a.ordersOf(row.Merchant.ID) {
		if js.Order.ID == id {
			return js, nil
		}
	}
	return nil, errNotFound
}

func (a *API) merchantOrder(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.orderByID(r)
	if err != nil {
		return err
	}
	ok(w, a.svc.OrderView(js))
	return nil
}

func (a *API) merchantAccept(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		PrepTimeMinutes int `json:"prep_time_minutes"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.PrepTimeMinutes < 5 || b.PrepTimeMinutes > 60 {
		return fieldErr("prep_time_minutes", "out_of_range", "5–60 minutes")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.orderByID(r)
	if err != nil {
		return err
	}
	if js.Job.Status != "merchant_pending" {
		return apiErr(409, "order_already_handled", "This order was already handled")
	}
	js.Job.Food.PrepTimeMinutes = domain.IntPtr(b.PrepTimeMinutes)
	js.MerchantDeadline = time.Time{}
	a.svc.SetStatus(js, "merchant_preparing")
	// Dispatch starts right away so the rider arrives around ready time.
	a.svc.SetStatus(js, "searching")
	a.svc.Dispatch(js)
	ok(w, a.svc.OrderView(js))
	return nil
}

var rejectReasons = map[string]string{
	"out_of_stock": "Sorry, an item is out of stock.",
	"too_busy":     "Sorry, the store is too busy right now.",
	"closing_soon": "Sorry, the store is closing soon.",
	"other":        "The store could not accept your order.",
}

func (a *API) merchantReject(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Reason string  `json:"reason"`
		Note   *string `json:"note"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	msg, valid := rejectReasons[b.Reason]
	if !valid {
		return fieldErr("reason", "invalid", "Invalid reason")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.orderByID(r)
	if err != nil {
		return err
	}
	if js.Job.Status != "merchant_pending" {
		return apiErr(409, "order_already_handled", "This order was already handled")
	}
	if b.Note != nil && strings.TrimSpace(*b.Note) != "" {
		msg += " " + strings.TrimSpace(*b.Note)
	}
	js.Order.RejectReason = domain.StrPtr(b.Reason)
	a.svc.Cancel(js, "merchant", msg)
	ok(w, a.svc.OrderView(js))
	return nil
}

func (a *API) merchantReady(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.orderByID(r)
	if err != nil {
		return err
	}
	if service.MerchantOrderStatus(js) != "preparing" {
		return apiErr(409, "invalid_status_transition", "Order is not being prepared")
	}
	js.Job.Food.IsReady = true
	js.Job.Food.ReadyAt = domain.At(time.Now())
	js.Order.Status = "ready"
	a.svc.PublishJob(js)
	ok(w, a.svc.OrderView(js))
	return nil
}

// ---------- menu ----------

func (a *API) merchantMenu(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	ok(w, a.publicMerchant(row, nil, true).Menu)
	return nil
}

func categoryOf(row *domain.MerchantRow, id string) *domain.MenuCategory {
	for i := range row.Merchant.Menu {
		if row.Merchant.Menu[i].ID == id {
			return &row.Merchant.Menu[i]
		}
	}
	return nil
}

func (a *API) addCategory(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Name string `json:"name"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if strings.TrimSpace(b.Name) == "" {
		return fieldErr("name", "required", "Name required")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	c := domain.MenuCategory{
		ID:        domain.NewID(),
		Name:      strings.TrimSpace(b.Name),
		SortOrder: len(row.Merchant.Menu),
		Items:     []domain.MenuItem{},
	}
	row.Merchant.Menu = append(row.Merchant.Menu, c)
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	ok(w, c)
	return nil
}

func (a *API) renameCategory(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Name *string `json:"name"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	c := categoryOf(row, r.PathValue("id"))
	if c == nil {
		return errNotFound
	}
	if b.Name != nil && strings.TrimSpace(*b.Name) != "" {
		c.Name = strings.TrimSpace(*b.Name)
	}
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	ok(w, c)
	return nil
}

func (a *API) deleteCategory(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	id := r.PathValue("id")
	for i, c := range row.Merchant.Menu {
		if c.ID == id {
			if len(c.Items) > 0 {
				return fieldErr("category", "not_empty", "Category is not empty")
			}
			row.Merchant.Menu = append(row.Merchant.Menu[:i], row.Merchant.Menu[i+1:]...)
			a.svc.Touch()
			a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
			okEmpty(w)
			return nil
		}
	}
	return errNotFound
}

func (a *API) reorderCategories(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		CategoryIDs []string `json:"category_ids"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	pos := map[string]int{}
	for i, id := range b.CategoryIDs {
		pos[id] = i
	}
	menu := row.Merchant.Menu
	sort.SliceStable(menu, func(i, j int) bool {
		pi, iok := pos[menu[i].ID]
		pj, jok := pos[menu[j].ID]
		if !iok {
			pi = len(pos) + i
		}
		if !jok {
			pj = len(pos) + j
		}
		return pi < pj
	})
	for i := range menu {
		menu[i].SortOrder = i
	}
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	okEmpty(w)
	return nil
}

type itemInput struct {
	CategoryID    string  `json:"category_id"`
	Name          string  `json:"name"`
	Description   *string `json:"description"`
	PhotoKey      *string `json:"photo_key"`
	PriceCentavos int     `json:"price_centavos"`
	IsAvailable   bool    `json:"is_available"`
	AddonGroups   []struct {
		ID        *string `json:"id"`
		Name      string  `json:"name"`
		MinSelect int     `json:"min_select"`
		MaxSelect int     `json:"max_select"`
		Options   []struct {
			ID            *string `json:"id"`
			Name          string  `json:"name"`
			PriceCentavos int     `json:"price_centavos"`
			IsAvailable   bool    `json:"is_available"`
		} `json:"options"`
	} `json:"addon_groups"`
}

func (a *API) applyItemInput(in itemInput, id string, existing *domain.MenuItem) (domain.MenuItem, error) {
	if strings.TrimSpace(in.Name) == "" {
		return domain.MenuItem{}, fieldErr("name", "required", "Name required")
	}
	if in.PriceCentavos < 0 {
		return domain.MenuItem{}, fieldErr("price_centavos", "invalid", "Invalid price")
	}
	it := domain.MenuItem{
		ID:            id,
		CategoryID:    in.CategoryID,
		Name:          strings.TrimSpace(in.Name),
		Description:   in.Description,
		PriceCentavos: in.PriceCentavos,
		IsAvailable:   in.IsAvailable,
		AddonGroups:   []domain.AddonGroup{},
	}
	if in.PhotoKey != nil {
		it.PhotoURL = a.svc.FileURL(*in.PhotoKey)
	} else if existing != nil {
		it.PhotoURL = existing.PhotoURL
	}
	for _, g := range in.AddonGroups {
		if g.MinSelect < 0 || g.MaxSelect < 1 || g.MinSelect > g.MaxSelect {
			return domain.MenuItem{}, fieldErr("addon_groups", "invalid_min_max", "Check add-on min/max")
		}
		ng := domain.AddonGroup{
			ID:        domain.NewID(),
			Name:      g.Name,
			MinSelect: g.MinSelect,
			MaxSelect: g.MaxSelect,
			Options:   []domain.AddonOption{},
		}
		if g.ID != nil {
			ng.ID = *g.ID
		}
		for _, o := range g.Options {
			no := domain.AddonOption{
				ID:            domain.NewID(),
				Name:          o.Name,
				PriceCentavos: o.PriceCentavos,
				IsAvailable:   o.IsAvailable,
			}
			if o.ID != nil {
				no.ID = *o.ID
			}
			ng.Options = append(ng.Options, no)
		}
		it.AddonGroups = append(it.AddonGroups, ng)
	}
	return it, nil
}

func (a *API) createItem(w http.ResponseWriter, r *http.Request) error {
	var in itemInput
	if err := decode(r, &in); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	c := categoryOf(row, in.CategoryID)
	if c == nil {
		return fieldErr("category_id", "not_found", "Category not found")
	}
	it, err := a.applyItemInput(in, domain.NewID(), nil)
	if err != nil {
		return err
	}
	c.Items = append(c.Items, it)
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	ok(w, it)
	return nil
}

func itemLoc(row *domain.MerchantRow, id string) (*domain.MenuCategory, int) {
	for ci := range row.Merchant.Menu {
		for ii := range row.Merchant.Menu[ci].Items {
			if row.Merchant.Menu[ci].Items[ii].ID == id {
				return &row.Merchant.Menu[ci], ii
			}
		}
	}
	return nil, -1
}

func (a *API) updateItem(w http.ResponseWriter, r *http.Request) error {
	var in itemInput
	if err := decode(r, &in); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	cat, idx := itemLoc(row, r.PathValue("id"))
	if cat == nil {
		return errNotFound
	}
	existing := cat.Items[idx]
	it, err := a.applyItemInput(in, existing.ID, &existing)
	if err != nil {
		return err
	}
	if in.CategoryID == cat.ID {
		cat.Items[idx] = it
	} else {
		dst := categoryOf(row, in.CategoryID)
		if dst == nil {
			return fieldErr("category_id", "not_found", "Category not found")
		}
		cat.Items = append(cat.Items[:idx], cat.Items[idx+1:]...)
		dst.Items = append(dst.Items, it)
	}
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	ok(w, it)
	return nil
}

func (a *API) deleteItem(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	cat, idx := itemLoc(row, r.PathValue("id"))
	if cat == nil {
		return errNotFound
	}
	cat.Items = append(cat.Items[:idx], cat.Items[idx+1:]...)
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	okEmpty(w)
	return nil
}

func (a *API) itemAvailability(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		IsAvailable bool `json:"is_available"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	cat, idx := itemLoc(row, r.PathValue("id"))
	if cat == nil {
		return errNotFound
	}
	cat.Items[idx].IsAvailable = b.IsAvailable
	a.svc.Touch()
	a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
	ok(w, cat.Items[idx])
	return nil
}

func (a *API) optionAvailability(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		IsAvailable bool `json:"is_available"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	id := r.PathValue("id")
	for ci := range row.Merchant.Menu {
		for ii := range row.Merchant.Menu[ci].Items {
			if o := findOption(&row.Merchant.Menu[ci].Items[ii], id); o != nil {
				o.IsAvailable = b.IsAvailable
				a.svc.Touch()
				a.invalidateMerchantCache(r.Context(), row.Merchant.ID)
				okEmpty(w)
				return nil
			}
		}
	}
	return errNotFound
}

// ---------- reports ----------

func (a *API) salesReport(w http.ResponseWriter, r *http.Request) error {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	if from == "" || to == "" || from > to {
		return fieldErr("from", "invalid", "from/to required")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	type agg struct{ n, gross, net, comm int }
	byDay := map[string]*agg{}
	for _, js := range a.ordersOf(row.Merchant.ID) {
		st := service.MerchantOrderStatus(js)
		if st != "completed" && st != "picked_up" {
			continue
		}
		d := domain.ManilaDate(js.Job.CreatedAt.Time)
		ag := byDay[d]
		if ag == nil {
			ag = &agg{}
			byDay[d] = ag
		}
		ag.n++
		ag.gross += js.Job.Food.SubtotalCentavos
		ag.comm += js.Order.Commission
		ag.net += js.Job.Food.SubtotalCentavos - js.Order.Commission
	}
	days := []map[string]any{}
	var tot agg
	for _, d := range dateRange(from, to) {
		ag := byDay[d]
		if ag == nil {
			ag = &agg{}
		}
		tot.n += ag.n
		tot.gross += ag.gross
		tot.net += ag.net
		tot.comm += ag.comm
		days = append(days, map[string]any{"date": d, "orders_count": ag.n, "gross_centavos": ag.gross, "net_centavos": ag.net})
	}
	ok(w, map[string]any{
		"from":                from,
		"to":                  to,
		"orders_count":        tot.n,
		"gross_centavos":      tot.gross,
		"commission_centavos": tot.comm,
		"net_centavos":        tot.net,
		"days":                days,
	})
	return nil
}

// listPayouts: seeded history + this week's pending payout for online-paid orders.
func (a *API) listPayouts(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	_, row, err := a.staffOf(r)
	if err != nil {
		return err
	}
	now := time.Now().In(domain.Manila)
	weekStart := now.AddDate(0, 0, -((int(now.Weekday()) + 6) % 7))
	from, to := weekStart.Format("2006-01-02"), weekStart.AddDate(0, 0, 6).Format("2006-01-02")
	online, cashCommission := 0, 0
	for _, js := range a.ordersOf(row.Merchant.ID) {
		d := domain.ManilaDate(js.Job.CreatedAt.Time)
		if service.MerchantOrderStatus(js) != "completed" || d < from || d > to {
			continue
		}
		if js.Job.Payment.Method == "cash" {
			cashCommission += js.Order.Commission
		} else {
			online += js.Job.Food.SubtotalCentavos - js.Order.Commission
		}
	}
	out := []*domain.Payout{{
		ID:             "current-" + from,
		PeriodFrom:     from,
		PeriodTo:       to,
		AmountCentavos: online,
		Type:           "payout",
		Status:         "pending",
	}}
	_ = cashCommission // collected from riders at settlement; nothing invoiced to the store
	for _, p := range a.svc.St.Payouts {
		if p.MerchantID == row.Merchant.ID {
			out = append(out, p)
		}
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}
