package app

import (
	"encoding/json"
	"net/http"
	"sort"
	"strings"
	"time"
)

func (s *Server) staffOf(r *http.Request) (MerchantStaff, *MerchantRow, error) {
	u := s.st.Users[claimsOf(r).Sub]
	st, isStaff := s.st.Staff[u.Phone]
	if !isStaff {
		return st, nil, apiErr(403, "forbidden", "This number is not registered as a merchant")
	}
	row := s.st.Merchants[st.MerchantID]
	if row == nil {
		return st, nil, errForbidden
	}
	return st, row, nil
}

func (s *Server) merchantMe(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	st, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	ok(w, map[string]any{"merchant": s.publicMerchant(row, nil, false), "role": st.Role, "staff_name": st.StaffName})
	return nil
}

func (s *Server) patchStore(w http.ResponseWriter, r *http.Request) error {
	var raw map[string]json.RawMessage
	if err := decode(r, &raw); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
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
			var t UTC
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
	var hours []OpeningHours
	if get("hours", &hours) {
		m.Hours = hours
	}
	if get("logo_key", &str) {
		m.LogoURL = s.fileURL(str)
	}
	if get("cover_key", &str) {
		m.CoverURL = s.fileURL(str)
	}
	if get("name", &str) && strings.TrimSpace(str) != "" {
		m.Name = strings.TrimSpace(str)
	}
	s.touch()
	pub := s.publicMerchant(row, nil, false)
	for _, uid := range s.merchantUserIDs(m.ID) {
		s.emit(uid, "merchant", "merchant.updated", map[string]any{"merchant": pub})
	}
	ok(w, pub)
	return nil
}

// ---------- orders ----------

func (s *Server) ordersOf(merchantID string) []*JobState {
	var out []*JobState
	for i := len(s.st.JobIDs) - 1; i >= 0; i-- {
		js := s.st.Jobs[s.st.JobIDs[i]]
		if js != nil && js.MerchantID == merchantID && js.Order != nil && js.Job.Status != "pending_payment" {
			out = append(out, js)
		}
	}
	return out
}

func (s *Server) merchantOrders(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	status, from, to := q.Get("status"), q.Get("from"), q.Get("to")
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	var out []MerchantOrder
	for _, js := range s.ordersOf(row.Merchant.ID) {
		ms := merchantOrderStatus(js)
		match := ms == status
		if status == "done" {
			match = ms == "picked_up" || ms == "completed" || ms == "rejected" || ms == "cancelled"
		}
		if status == "" {
			match = true
		}
		d := manilaDate(js.Job.CreatedAt.Time)
		if !match || (from != "" && d < from) || (to != "" && d > to) {
			continue
		}
		out = append(out, s.orderView(js))
	}
	page, next := paginate(out, r, 50)
	okPage(w, page, next)
	return nil
}

func (s *Server) orderByID(r *http.Request) (*JobState, error) {
	_, row, err := s.staffOf(r)
	if err != nil {
		return nil, err
	}
	id := r.PathValue("id")
	for _, js := range s.ordersOf(row.Merchant.ID) {
		if js.Order.ID == id {
			return js, nil
		}
	}
	return nil, errNotFound
}

func (s *Server) merchantOrder(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	js, err := s.orderByID(r)
	if err != nil {
		return err
	}
	ok(w, s.orderView(js))
	return nil
}

func (s *Server) merchantAccept(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		PrepTimeMinutes int `json:"prep_time_minutes"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.PrepTimeMinutes < 5 || b.PrepTimeMinutes > 60 {
		return fieldErr("prep_time_minutes", "out_of_range", "5–60 minutes")
	}
	s.lock()
	defer s.unlock()
	js, err := s.orderByID(r)
	if err != nil {
		return err
	}
	if js.Job.Status != "merchant_pending" {
		return apiErr(409, "order_already_handled", "This order was already handled")
	}
	js.Job.Food.PrepTimeMinutes = intp(b.PrepTimeMinutes)
	js.MerchantDeadline = time.Time{}
	s.setStatus(js, "merchant_preparing")
	// Dispatch starts right away so the rider arrives around ready time.
	s.setStatus(js, "searching")
	s.dispatch(js)
	ok(w, s.orderView(js))
	return nil
}

var rejectReasons = map[string]string{
	"out_of_stock": "Sorry, an item is out of stock.", "too_busy": "Sorry, the store is too busy right now.",
	"closing_soon": "Sorry, the store is closing soon.", "other": "The store could not accept your order.",
}

func (s *Server) merchantReject(w http.ResponseWriter, r *http.Request) error {
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
	s.lock()
	defer s.unlock()
	js, err := s.orderByID(r)
	if err != nil {
		return err
	}
	if js.Job.Status != "merchant_pending" {
		return apiErr(409, "order_already_handled", "This order was already handled")
	}
	if b.Note != nil && strings.TrimSpace(*b.Note) != "" {
		msg += " " + strings.TrimSpace(*b.Note)
	}
	js.Order.RejectReason = strp(b.Reason)
	s.cancel(js, "merchant", msg)
	ok(w, s.orderView(js))
	return nil
}

func (s *Server) merchantReady(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	js, err := s.orderByID(r)
	if err != nil {
		return err
	}
	if merchantOrderStatus(js) != "preparing" {
		return apiErr(409, "invalid_status_transition", "Order is not being prepared")
	}
	js.Job.Food.IsReady = true
	js.Job.Food.ReadyAt = at(time.Now())
	js.Order.Status = "ready"
	s.publishJob(js)
	ok(w, s.orderView(js))
	return nil
}

// ---------- menu ----------

func (s *Server) merchantMenu(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	ok(w, s.publicMerchant(row, nil, true).Menu)
	return nil
}

func (row *MerchantRow) category(id string) *MenuCategory {
	for i := range row.Merchant.Menu {
		if row.Merchant.Menu[i].ID == id {
			return &row.Merchant.Menu[i]
		}
	}
	return nil
}

func (s *Server) addCategory(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Name string `json:"name"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if strings.TrimSpace(b.Name) == "" {
		return fieldErr("name", "required", "Name required")
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	c := MenuCategory{ID: newID(), Name: strings.TrimSpace(b.Name), SortOrder: len(row.Merchant.Menu), Items: []MenuItem{}}
	row.Merchant.Menu = append(row.Merchant.Menu, c)
	s.touch()
	ok(w, c)
	return nil
}

func (s *Server) renameCategory(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Name *string `json:"name"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	c := row.category(r.PathValue("id"))
	if c == nil {
		return errNotFound
	}
	if b.Name != nil && strings.TrimSpace(*b.Name) != "" {
		c.Name = strings.TrimSpace(*b.Name)
	}
	s.touch()
	ok(w, c)
	return nil
}

func (s *Server) deleteCategory(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
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
			s.touch()
			okEmpty(w)
			return nil
		}
	}
	return errNotFound
}

func (s *Server) reorderCategories(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		CategoryIDs []string `json:"category_ids"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
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
	s.touch()
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

func (s *Server) applyItemInput(in itemInput, id string, existing *MenuItem) (MenuItem, error) {
	if strings.TrimSpace(in.Name) == "" {
		return MenuItem{}, fieldErr("name", "required", "Name required")
	}
	if in.PriceCentavos < 0 {
		return MenuItem{}, fieldErr("price_centavos", "invalid", "Invalid price")
	}
	it := MenuItem{ID: id, CategoryID: in.CategoryID, Name: strings.TrimSpace(in.Name), Description: in.Description, PriceCentavos: in.PriceCentavos, IsAvailable: in.IsAvailable, AddonGroups: []AddonGroup{}}
	if in.PhotoKey != nil {
		it.PhotoURL = s.fileURL(*in.PhotoKey)
	} else if existing != nil {
		it.PhotoURL = existing.PhotoURL
	}
	for _, g := range in.AddonGroups {
		if g.MinSelect < 0 || g.MaxSelect < 1 || g.MinSelect > g.MaxSelect {
			return MenuItem{}, fieldErr("addon_groups", "invalid_min_max", "Check add-on min/max")
		}
		ng := AddonGroup{ID: newID(), Name: g.Name, MinSelect: g.MinSelect, MaxSelect: g.MaxSelect, Options: []AddonOption{}}
		if g.ID != nil {
			ng.ID = *g.ID
		}
		for _, o := range g.Options {
			no := AddonOption{ID: newID(), Name: o.Name, PriceCentavos: o.PriceCentavos, IsAvailable: o.IsAvailable}
			if o.ID != nil {
				no.ID = *o.ID
			}
			ng.Options = append(ng.Options, no)
		}
		it.AddonGroups = append(it.AddonGroups, ng)
	}
	return it, nil
}

func (s *Server) createItem(w http.ResponseWriter, r *http.Request) error {
	var in itemInput
	if err := decode(r, &in); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	c := row.category(in.CategoryID)
	if c == nil {
		return fieldErr("category_id", "not_found", "Category not found")
	}
	it, err := s.applyItemInput(in, newID(), nil)
	if err != nil {
		return err
	}
	c.Items = append(c.Items, it)
	s.touch()
	ok(w, it)
	return nil
}

func (row *MerchantRow) itemLoc(id string) (*MenuCategory, int) {
	for ci := range row.Merchant.Menu {
		for ii := range row.Merchant.Menu[ci].Items {
			if row.Merchant.Menu[ci].Items[ii].ID == id {
				return &row.Merchant.Menu[ci], ii
			}
		}
	}
	return nil, -1
}

func (s *Server) updateItem(w http.ResponseWriter, r *http.Request) error {
	var in itemInput
	if err := decode(r, &in); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	cat, idx := row.itemLoc(r.PathValue("id"))
	if cat == nil {
		return errNotFound
	}
	existing := cat.Items[idx]
	it, err := s.applyItemInput(in, existing.ID, &existing)
	if err != nil {
		return err
	}
	if in.CategoryID == cat.ID {
		cat.Items[idx] = it
	} else {
		dst := row.category(in.CategoryID)
		if dst == nil {
			return fieldErr("category_id", "not_found", "Category not found")
		}
		cat.Items = append(cat.Items[:idx], cat.Items[idx+1:]...)
		dst.Items = append(dst.Items, it)
	}
	s.touch()
	ok(w, it)
	return nil
}

func (s *Server) deleteItem(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	cat, idx := row.itemLoc(r.PathValue("id"))
	if cat == nil {
		return errNotFound
	}
	cat.Items = append(cat.Items[:idx], cat.Items[idx+1:]...)
	s.touch()
	okEmpty(w)
	return nil
}

func (s *Server) itemAvailability(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		IsAvailable bool `json:"is_available"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	cat, idx := row.itemLoc(r.PathValue("id"))
	if cat == nil {
		return errNotFound
	}
	cat.Items[idx].IsAvailable = b.IsAvailable
	s.touch()
	ok(w, cat.Items[idx])
	return nil
}

func (s *Server) optionAvailability(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		IsAvailable bool `json:"is_available"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	id := r.PathValue("id")
	for ci := range row.Merchant.Menu {
		for ii := range row.Merchant.Menu[ci].Items {
			if o := findOption(&row.Merchant.Menu[ci].Items[ii], id); o != nil {
				o.IsAvailable = b.IsAvailable
				s.touch()
				okEmpty(w)
				return nil
			}
		}
	}
	return errNotFound
}

// ---------- reports ----------

func (s *Server) salesReport(w http.ResponseWriter, r *http.Request) error {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	if from == "" || to == "" || from > to {
		return fieldErr("from", "invalid", "from/to required")
	}
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	type agg struct{ n, gross, net, comm int }
	byDay := map[string]*agg{}
	for _, js := range s.ordersOf(row.Merchant.ID) {
		st := merchantOrderStatus(js)
		if st != "completed" && st != "picked_up" {
			continue
		}
		d := manilaDate(js.Job.CreatedAt.Time)
		a := byDay[d]
		if a == nil {
			a = &agg{}
			byDay[d] = a
		}
		a.n++
		a.gross += js.Job.Food.SubtotalCentavos
		a.comm += js.Order.Commission
		a.net += js.Job.Food.SubtotalCentavos - js.Order.Commission
	}
	days := []map[string]any{}
	var tot agg
	for _, d := range dateRange(from, to) {
		a := byDay[d]
		if a == nil {
			a = &agg{}
		}
		tot.n += a.n
		tot.gross += a.gross
		tot.net += a.net
		tot.comm += a.comm
		days = append(days, map[string]any{"date": d, "orders_count": a.n, "gross_centavos": a.gross, "net_centavos": a.net})
	}
	ok(w, map[string]any{"from": from, "to": to, "orders_count": tot.n, "gross_centavos": tot.gross, "commission_centavos": tot.comm, "net_centavos": tot.net, "days": days})
	return nil
}

// listPayouts: seeded history + this week's pending payout for online-paid orders.
func (s *Server) listPayouts(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	_, row, err := s.staffOf(r)
	if err != nil {
		return err
	}
	now := time.Now().In(manila)
	weekStart := now.AddDate(0, 0, -((int(now.Weekday()) + 6) % 7))
	from, to := weekStart.Format("2006-01-02"), weekStart.AddDate(0, 0, 6).Format("2006-01-02")
	online, cashCommission := 0, 0
	for _, js := range s.ordersOf(row.Merchant.ID) {
		d := manilaDate(js.Job.CreatedAt.Time)
		if merchantOrderStatus(js) != "completed" || d < from || d > to {
			continue
		}
		if js.Job.Payment.Method == "cash" {
			cashCommission += js.Order.Commission
		} else {
			online += js.Job.Food.SubtotalCentavos - js.Order.Commission
		}
	}
	out := []*Payout{{ID: "current-" + from, PeriodFrom: from, PeriodTo: to, AmountCentavos: online, Type: "payout", Status: "pending"}}
	_ = cashCommission // collected from riders at settlement; nothing invoiced to the store
	for _, p := range s.st.Payouts {
		if p.MerchantID == row.Merchant.ID {
			out = append(out, p)
		}
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}
