package api

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"goapp/backend/internal/domain"
	"goapp/backend/internal/integrations"
	"goapp/backend/internal/service"
)

func (a *API) publicMerchant(row *domain.MerchantRow, near *domain.LatLng, withMenu bool) domain.Merchant {
	m := domain.DeepCopy(row.Merchant)
	if !withMenu {
		m.Menu = nil
	} else {
		sort.Slice(m.Menu, func(i, j int) bool { return m.Menu[i].SortOrder < m.Menu[j].SortOrder })
		if m.Menu == nil {
			m.Menu = []domain.MenuCategory{}
		}
	}
	if near != nil {
		d := domain.DistanceM(*near, m.Location)
		m.DistanceM = &d
	}
	if row.RatingCount > 0 {
		v := math.Round(float64(row.RatingSum)/float64(row.RatingCount)*10) / 10
		m.Rating = &v
	}
	return m
}

func (a *API) listMerchants(w http.ResponseWriter, r *http.Request) error {
	near, err := parseLatLng(r)
	if err != nil {
		return err
	}
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	a.svc.Lock()
	defer a.svc.Unlock()
	var out []domain.Merchant
	for _, id := range a.svc.St.MerchantIDs {
		row := a.svc.St.Merchants[id]
		if q != "" {
			hit := strings.Contains(strings.ToLower(row.Merchant.Name), q)
			for _, c := range row.Merchant.Menu {
				for _, it := range c.Items {
					hit = hit || strings.Contains(strings.ToLower(it.Name), q)
				}
			}
			if !hit {
				continue
			}
		}
		out = append(out, a.publicMerchant(row, &near, false))
	}
	sort.SliceStable(out, func(i, j int) bool {
		ai, aj := a.svc.St.Merchants[out[i].ID].Merchant.AcceptsOrders(), a.svc.St.Merchants[out[j].ID].Merchant.AcceptsOrders()
		if ai != aj {
			return ai
		}
		return *out[i].DistanceM < *out[j].DistanceM
	})
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (a *API) getMerchant(w http.ResponseWriter, r *http.Request) error {
	id := r.PathValue("id")
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		cached, hit, err := a.svc.Redis.GetCachedMerchant(ctx, id)
		cancel()
		if err == nil && hit && cached != nil {
			ok(w, *cached)
			return nil
		}
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	row := a.svc.St.Merchants[id]
	if row == nil {
		return errNotFound
	}
	pub := a.publicMerchant(row, nil, true)
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.CacheMerchant(ctx, pub, 5*time.Minute)
		cancel()
	}
	ok(w, pub)
	return nil
}

// ---------- quotes ----------

func findItem(m *domain.Merchant, id string) *domain.MenuItem {
	for ci := range m.Menu {
		for ii := range m.Menu[ci].Items {
			if m.Menu[ci].Items[ii].ID == id {
				return &m.Menu[ci].Items[ii]
			}
		}
	}
	return nil
}

func findOption(it *domain.MenuItem, id string) *domain.AddonOption {
	for gi := range it.AddonGroups {
		for oi := range it.AddonGroups[gi].Options {
			if it.AddonGroups[gi].Options[oi].ID == id {
				return &it.AddonGroups[gi].Options[oi]
			}
		}
	}
	return nil
}

const maxPabiliBudget = 300000

func (a *API) createQuote(w http.ResponseWriter, r *http.Request) error {
	var req domain.QuoteRequest
	if err := decode(r, &req); err != nil {
		return err
	}
	// Food pickup is always the merchant's location.
	a.svc.Lock()
	if req.Service == "food" && req.Food != nil {
		if m := a.svc.St.Merchants[req.Food.MerchantID]; m != nil {
			req.Pickup = domain.Stop{Address: m.Merchant.Address, Location: m.Merchant.Location, ContactName: domain.StrPtr(m.Merchant.Name)}
		}
	}
	a.svc.Unlock()

	var rt *integrations.Route
	if a.svc.Maps != nil && a.svc.Maps.Enabled() {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		route, err := a.svc.Maps.Route(ctx, req.Pickup.Location, req.Dropoff.Location)
		cancel()
		if err == nil {
			rt = &route
		} else {
			integrations.LogIntegration("google routes", err) // fall back to straight-line pricing
		}
	}

	a.svc.Lock()
	defer a.svc.Unlock()
	q, err := a.priceQuote(&req, rt)
	if err != nil {
		return err
	}
	q.UserID = claimsOf(r).Sub
	q.Request = &req
	a.svc.St.Quotes[q.ID] = q
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.SaveQuote(ctx, q)
		cancel()
	}
	ok(w, q)
	return nil
}

func (a *API) priceQuote(req *domain.QuoteRequest, rt *integrations.Route) (*domain.Quote, error) {
	if req.Service == "food" && req.Food != nil {
		if m := a.svc.St.Merchants[req.Food.MerchantID]; m != nil {
			req.Pickup = domain.Stop{Address: m.Merchant.Address, Location: m.Merchant.Location, ContactName: domain.StrPtr(m.Merchant.Name)}
		}
	}
	if !a.svc.InServiceArea(req.Pickup.Location) || !a.svc.InServiceArea(req.Dropoff.Location) {
		return nil, apiErr(422, "out_of_service_area", "Outside the Bongao service area")
	}
	dist := int(float64(domain.DistanceM(req.Pickup.Location, req.Dropoff.Location)) * 1.3)
	dur := max(180, int(float64(dist)/1000/22*3600))
	var poly *string
	if rt != nil && rt.DistanceM > 0 {
		dist, dur = rt.DistanceM, max(60, rt.DurationS)
		if rt.Polyline != "" {
			poly = domain.StrPtr(rt.Polyline)
		}
	}
	km := int(math.Ceil(float64(dist) / 1000))
	kmLabel := fmt.Sprintf("Distance %.1f km", float64(dist)/1000)
	var lines []domain.FareLine
	addLine := func(l string, amt int) { lines = append(lines, domain.FareLine{Label: l, AmountCentavos: amt}) }
	fees := 0
	var maxBudget *int
	switch req.Service {
	case "ride":
		addLine("Base fare", 4000)
		addLine(kmLabel, max(0, km-1)*1500)
	case "food":
		if req.Food == nil || len(req.Food.Items) == 0 {
			return nil, fieldErr("food", "required", "No items")
		}
		row := a.svc.St.Merchants[req.Food.MerchantID]
		if row == nil {
			return nil, errNotFound
		}
		m := &row.Merchant
		if !m.AcceptsOrders() {
			return nil, apiErr(409, "merchant_closed", m.Name+" is closed")
		}
		sub := 0
		for _, it := range req.Food.Items {
			item := findItem(m, it.ItemID)
			if item == nil || !item.IsAvailable {
				return nil, apiErr(409, "item_unavailable", "An item is sold out")
			}
			unit := item.PriceCentavos
			for _, oid := range it.AddonOptionIDs {
				o := findOption(item, oid)
				if o == nil || !o.IsAvailable {
					return nil, apiErr(409, "item_unavailable", "An add-on is sold out")
				}
				unit += o.PriceCentavos
			}
			if it.Quantity < 1 || it.Quantity > 50 {
				return nil, fieldErr("quantity", "invalid", "Invalid quantity")
			}
			sub += unit * it.Quantity
		}
		if sub < m.MinOrderCentavos {
			return nil, fieldErr("food", "below_min_order", "Below minimum order")
		}
		addLine("Food subtotal", sub)
		addLine("Delivery fee", 3900+max(0, km-1)*1000)
		addLine("Service fee", 1000)
	case "pabili":
		if req.Pabili == nil || len(req.Pabili.Items) == 0 || strings.TrimSpace(req.Pabili.StoreName) == "" {
			return nil, fieldErr("pabili", "required", "Store and items required")
		}
		mb := maxPabiliBudget
		maxBudget = &mb
		if req.Pabili.EstimatedItemTotalCentavos > mb {
			return nil, fieldErr("estimated_item_total_centavos", fmt.Sprintf("max_%d", mb), "Budget too high")
		}
		addLine("Pabili fee", 6000)
		addLine(kmLabel, max(0, km-1)*1000)
	case "padala":
		if req.Padala == nil || strings.TrimSpace(req.Padala.Description) == "" || !phoneRe.MatchString(req.Padala.RecipientPhone) {
			return nil, fieldErr("padala", "invalid", "Recipient and description required")
		}
		base := map[string]int{"small": 5000, "medium": 6500, "large": 8500}[req.Padala.Size]
		if base == 0 {
			return nil, fieldErr("size", "invalid", "Invalid size")
		}
		addLine("Base fare ("+req.Padala.Size+")", base)
		addLine(kmLabel, max(0, km-1)*1500)
	default:
		return nil, fieldErr("service", "invalid", "Unknown service")
	}
	total := 0
	for _, l := range lines {
		total += l.AmountCentavos
		if l.Label != "Food subtotal" {
			fees += l.AmountCentavos
		}
	}
	return &domain.Quote{
		ID:                    domain.NewID(),
		Service:               req.Service,
		DistanceM:             dist,
		DurationS:             dur,
		ExpiresAt:             *domain.At(time.Now().Add(5 * time.Minute)),
		Breakdown:             lines,
		TotalCentavos:         total,
		MaxItemBudgetCentavos: maxBudget,
		FeesCentavos:          fees,
		RoutePolyline:         poly,
	}, nil
}

// ---------- jobs ----------

func (a *API) createJob(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		QuoteID       string  `json:"quote_id"`
		PaymentMethod string  `json:"payment_method"`
		Notes         *string `json:"notes"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.PaymentMethod != "cash" && b.PaymentMethod != "gcash" && b.PaymentMethod != "maya" {
		return fieldErr("payment_method", "invalid", "Invalid payment method")
	}
	uid := claimsOf(r).Sub
	a.svc.Lock()
	defer a.svc.Unlock()
	idem := r.Header.Get("Idempotency-Key")
	if idem != "" {
		idemKey := uid + ":" + idem
		jid, done := a.svc.St.Idempotency[idemKey]
		if !done && a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			if rJid, found, err := a.svc.Redis.GetIdempotency(ctx, idemKey); err == nil && found {
				jid, done = rJid, true
				a.svc.St.Idempotency[idemKey] = rJid
			}
			cancel()
		}
		if done && a.svc.St.Jobs[jid] != nil {
			ok(w, a.svc.JobView(a.svc.St.Jobs[jid], "customer"))
			return nil
		}
	}
	q := a.svc.St.Quotes[b.QuoteID]
	if q == nil && a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		if rq, found, err := a.svc.Redis.GetQuote(ctx, b.QuoteID); err == nil && found {
			q = rq
		}
		cancel()
	}
	if q == nil || q.UserID != uid || time.Now().After(q.ExpiresAt.Time) {
		return apiErr(409, "quote_expired", "Quote expired")
	}
	// Re-validate (menu or store state may have changed since the quote).
	if _, err := a.priceQuote(q.Request, nil); err != nil {
		return err
	}
	js := a.buildJob(uid, q, b.PaymentMethod, b.Notes)
	if (b.PaymentMethod == "gcash" || b.PaymentMethod == "maya") && a.svc.PM != nil && a.svc.PM.Enabled() {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		meta := map[string]string{"type": "job", "job_id": js.Job.ID, "user_id": uid}
		co, err := a.svc.PM.CreateCheckout(ctx, js.Job.Code, "Ngaon "+js.Job.Code, q.TotalCentavos, b.PaymentMethod, strings.TrimRight(a.svc.Cfg.PublicURL, "/")+"/pay/return", strings.TrimRight(a.svc.Cfg.PublicURL, "/")+"/pay/return", meta)
		cancel()
		if err == nil {
			js.PMCheckoutID = co.ID
			js.Job.Payment.CheckoutURL = domain.StrPtr(co.URL)
		} else {
			integrations.LogIntegration("paymongo checkout "+js.Job.Code, err)
		}
	}
	a.svc.St.Jobs[js.Job.ID] = js
	a.svc.St.JobIDs = append(a.svc.St.JobIDs, js.Job.ID)
	delete(a.svc.St.Quotes, q.ID)
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.DeleteQuote(ctx, q.ID)
		cancel()
	}
	if idem != "" {
		idemKey := uid + ":" + idem
		a.svc.St.Idempotency[idemKey] = js.Job.ID
		if a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			_ = a.svc.Redis.SetIdempotency(ctx, idemKey, js.Job.ID, 24*time.Hour)
			cancel()
		}
	}
	if b.PaymentMethod == "cash" {
		a.svc.AfterPayment(js)
	} else {
		a.svc.SetStatus(js, "pending_payment")
	}
	ok(w, a.svc.JobView(js, "customer"))
	return nil
}

func (a *API) buildJob(uid string, q *domain.Quote, method string, notes *string) *domain.JobState {
	req := q.Request
	id := domain.NewID()
	dropoff := req.Dropoff
	if notes != nil && strings.TrimSpace(*notes) != "" {
		dropoff.Notes = notes
	}
	j := domain.Job{
		ID:             id,
		Code:           a.svc.NextCode(),
		Service:        req.Service,
		CreatedAt:      domain.Now(),
		UpdatedAt:      domain.Now(),
		Pickup:         req.Pickup,
		Dropoff:        dropoff,
		Fare:           domain.Fare{Breakdown: q.Breakdown, TotalCentavos: q.TotalCentavos},
		Payment:        domain.JobPayment{Method: method, Status: "pending"},
		Timeline:       []domain.TimelineEntry{},
		AllowedActions: []string{},
		RoutePolyline:  q.RoutePolyline,
	}
	if method != "cash" {
		j.Payment.CheckoutURL = domain.StrPtr(strings.TrimRight(a.svc.Cfg.PublicURL, "/") + "/pay/job/" + id)
	}
	earnings := q.FeesCentavos * 80 / 100
	js := &domain.JobState{
		CustomerID:         uid,
		FeesCentavos:       q.FeesCentavos,
		EarningsCentavos:   earnings,
		CommissionCentavos: q.FeesCentavos - earnings,
	}
	switch req.Service {
	case "food":
		row := a.svc.St.Merchants[req.Food.MerchantID]
		m := &row.Merchant
		js.MerchantID = m.ID
		j.Merchant = &domain.JobMerchant{ID: m.ID, Name: m.Name, PhoneMasked: domain.MaskPhone(row.Phone)}
		sub := 0
		var lines []domain.OrderLine
		for _, it := range req.Food.Items {
			item := findItem(m, it.ItemID)
			unit := item.PriceCentavos
			addons := []string{}
			for _, oid := range it.AddonOptionIDs {
				o := findOption(item, oid)
				unit += o.PriceCentavos
				addons = append(addons, o.Name)
			}
			lines = append(lines, domain.OrderLine{
				Name:              item.Name,
				Quantity:          it.Quantity,
				Addons:            addons,
				Note:              it.Note,
				LineTotalCentavos: unit * it.Quantity,
			})
			sub += unit * it.Quantity
		}
		commission := sub / 10
		j.Food = &domain.JobFood{Items: lines, SubtotalCentavos: sub}
		if method == "cash" {
			j.Food.RiderPaysMerchantCentavos = domain.IntPtr(sub - commission)
		}
		js.Order = &domain.MerchantOrderState{ID: domain.NewID(), Status: "new", Commission: commission}
	case "pabili":
		j.Pabili = &domain.JobPabili{StoreName: req.Pabili.StoreName, Items: req.Pabili.Items}
	case "padala":
		p := req.Padala
		j.Padala = &domain.JobPadala{
			Size:           p.Size,
			Description:    p.Description,
			RecipientName:  p.RecipientName,
			RecipientPhone: p.RecipientPhone,
		}
		if p.PhotoKey != nil {
			j.Padala.PhotoURL = a.svc.FileURL(*p.PhotoKey)
		}
		if j.Dropoff.ContactName == nil {
			j.Dropoff.ContactName = domain.StrPtr(p.RecipientName)
		}
		if j.Dropoff.ContactPhone == nil {
			j.Dropoff.ContactPhone = domain.StrPtr(p.RecipientPhone)
		}
	}
	js.Job = j
	return js
}

func (a *API) jobFor(r *http.Request) (*domain.JobState, error) {
	js := a.svc.St.Jobs[r.PathValue("id")]
	if js == nil {
		return nil, errNotFound
	}
	uid := claimsOf(r).Sub
	if js.CustomerID == uid || (js.RiderUserID != "" && js.RiderUserID == uid) {
		return js, nil
	}
	return nil, errNotFound
}

func (a *API) listJobs(w http.ResponseWriter, r *http.Request) error {
	active := r.URL.Query().Get("status") != "past"
	uid := claimsOf(r).Sub
	a.svc.Lock()
	defer a.svc.Unlock()
	var out []domain.Job
	for i := len(a.svc.St.JobIDs) - 1; i >= 0; i-- {
		js := a.svc.St.Jobs[a.svc.St.JobIDs[i]]
		if js == nil || js.CustomerID != uid || service.IsLive(js.Job.Status) != active {
			continue
		}
		out = append(out, a.svc.JobView(js, "customer"))
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (a *API) getJob(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	js, err := a.jobFor(r)
	if err != nil {
		a.svc.Unlock()
		return err
	}
	needSync := js.Job.Status == "pending_payment" && js.PMCheckoutID != "" && a.svc.PM != nil && a.svc.PM.Enabled() && time.Since(js.PayCheckedAt) > 4*time.Second
	jid := js.Job.ID
	if needSync {
		js.PayCheckedAt = time.Now()
	}
	a.svc.Unlock()

	if needSync {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		a.syncJobPayment(ctx, jid)
		cancel()
	}

	a.svc.Lock()
	defer a.svc.Unlock()
	js = a.svc.St.Jobs[jid]
	if js == nil {
		return errNotFound
	}
	ok(w, a.svc.JobView(js, claimsOf(r).App))
	return nil
}

func (a *API) syncJobPayment(ctx context.Context, jobID string) {
	a.svc.Lock()
	js := a.svc.St.Jobs[jobID]
	if js == nil || js.Job.Status != "pending_payment" || js.PMCheckoutID == "" || a.svc.PM == nil || !a.svc.PM.Enabled() {
		a.svc.Unlock()
		return
	}
	csID := js.PMCheckoutID
	a.svc.Unlock()

	st, err := a.svc.PM.RetrieveCheckout(ctx, csID)
	if err != nil {
		integrations.LogIntegration("paymongo retrieve checkout", err)
		return
	}
	if st.Paid {
		a.svc.Lock()
		if js := a.svc.St.Jobs[jobID]; js != nil && js.Job.Status == "pending_payment" {
			a.markJobPaid(js, st.PaymentID)
		}
		a.svc.Unlock()
	}
}

func (a *API) markJobPaid(js *domain.JobState, paymentID string) {
	js.Job.Payment.Status = "paid"
	if paymentID != "" {
		js.PMPaymentID = paymentID
	}
	a.svc.AfterPayment(js)
	a.svc.Touch()
}

func (a *API) cancelJob(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Reason string `json:"reason"`
	}
	_ = decode(r, &b)
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	if js.CustomerID != claimsOf(r).Sub || !contains(service.CustomerActions(js), "cancel") {
		return apiErr(409, "job_not_cancellable", "This booking can no longer be cancelled")
	}
	reason := strings.TrimSpace(b.Reason)
	if reason == "" {
		reason = "Cancelled by customer"
	}
	a.svc.Cancel(js, "customer", reason)
	ok(w, a.svc.JobView(js, "customer"))
	return nil
}

func (a *API) confirmItems(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Approved bool `json:"approved"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	if js.CustomerID != claimsOf(r).Sub || js.Job.Status != "items_purchased" {
		return apiErr(409, "invalid_status_transition", "Nothing to confirm")
	}
	if b.Approved {
		a.svc.SetStatus(js, "picked_up")
	} else {
		// Dispute = cancel + support follow-up.
		a.svc.Cancel(js, "customer", "Item total disputed by customer. Ngaon support will contact you.")
	}
	ok(w, a.svc.JobView(js, "customer"))
	return nil
}

func (a *API) rateJob(w http.ResponseWriter, r *http.Request) error {
	var b domain.Rating
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.RiderRating < 1 || b.RiderRating > 5 || (b.MerchantRating != nil && (*b.MerchantRating < 1 || *b.MerchantRating > 5)) {
		return fieldErr("rider_rating", "invalid", "Ratings are 1–5")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	if js.CustomerID != claimsOf(r).Sub || !contains(service.CustomerActions(js), "rate") {
		return apiErr(409, "invalid_status_transition", "Cannot rate this job")
	}
	js.Rated = true
	b.JobID = js.Job.ID
	a.svc.St.Ratings = append(a.svc.St.Ratings, b)
	if rd := a.svc.St.Riders[js.RiderUserID]; rd != nil {
		rd.RatingSum += b.RiderRating
		rd.RatingCount++
		v := math.Round(float64(rd.RatingSum)/float64(rd.RatingCount)*10) / 10
		rd.Profile.Rating = &v
	}
	if m := a.svc.St.Merchants[js.MerchantID]; m != nil && b.MerchantRating != nil {
		m.RatingSum += *b.MerchantRating
		m.RatingCount++
		if a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			_ = a.svc.Redis.InvalidateMerchantCache(ctx, js.MerchantID)
			cancel()
		}
	}
	a.svc.Touch()
	okEmpty(w)
	return nil
}

func (a *API) shareJob(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	if js.ShareToken == "" {
		js.ShareToken = domain.RandToken(12)
		a.svc.St.Shares[js.ShareToken] = js.Job.ID
		a.svc.Touch()
	}
	ok(w, map[string]any{"url": strings.TrimRight(a.svc.Cfg.PublicURL, "/") + "/t/" + js.ShareToken, "expires_at": domain.At(time.Now().Add(6 * time.Hour))})
	return nil
}

func (a *API) sosJob(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Location domain.LatLng `json:"location"`
	}
	_ = decode(r, &b)
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	a.svc.St.SOS = append(a.svc.St.SOS, domain.SOSAlert{JobID: js.Job.ID, UserID: claimsOf(r).Sub, Location: b.Location, At: domain.Now()})
	a.svc.Touch()
	log.Printf("🚨 SOS on %s by %s at %.5f,%.5f", js.Job.Code, claimsOf(r).Sub, b.Location.Lat, b.Location.Lng)
	okEmpty(w)
	return nil
}

func (a *API) callJob(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	other := js.RiderUserID
	if claimsOf(r).Sub == js.RiderUserID {
		other = js.CustomerID
	}
	u := a.svc.St.Users[other]
	if u == nil {
		return apiErr(409, "invalid_status_transition", "No one to call yet")
	}
	ok(w, map[string]string{"masked_number": u.Phone})
	return nil
}

// ---------- chat ----------

func (a *API) listMessages(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	page, next := paginate(a.svc.St.Chats[js.Job.ID], r, 50)
	okPage(w, page, next)
	return nil
}

func (a *API) sendMessage(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Text     *string `json:"text"`
		ImageKey *string `json:"image_key"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if (b.Text == nil || strings.TrimSpace(*b.Text) == "") && b.ImageKey == nil {
		return fieldErr("text", "required", "Message is empty")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	js, err := a.jobFor(r)
	if err != nil {
		return err
	}
	if !service.IsLive(js.Job.Status) {
		return apiErr(409, "invalid_status_transition", "This chat has ended")
	}
	uid := claimsOf(r).Sub
	sender, to, toApp := "customer", js.RiderUserID, "rider"
	if uid == js.RiderUserID {
		sender, to, toApp = "rider", js.CustomerID, "customer"
	}
	m := &domain.ChatMessage{ID: domain.NewID(), JobID: js.Job.ID, Sender: sender, Text: b.Text, CreatedAt: domain.Now()}
	if b.ImageKey != nil {
		m.ImageURL = a.svc.FileURL(*b.ImageKey)
	}
	a.svc.St.Chats[js.Job.ID] = append(a.svc.St.Chats[js.Job.ID], m)
	a.svc.Emit(to, toApp, "chat.message", map[string]any{"message": m})
	a.svc.Touch()
	ok(w, m)
	return nil
}

// ---------- uploads ----------

var purposes = map[string]bool{
	"rider_license": true, "rider_orcr": true, "rider_selfie": true, "rider_clearance": true, "receipt": true,
	"proof_of_delivery": true, "parcel_photo": true, "chat_image": true, "menu_item_photo": true,
	"merchant_logo": true, "merchant_cover": true,
}
var keyRe = regexp.MustCompile(`^u/[a-z_]+/[0-9a-f-]{36}\.jpg$`)

func (a *API) uploadSig(key string, exp int64) string {
	mac := hmac.New(sha256.New, a.svc.Cfg.JWTSecret)
	fmt.Fprintf(mac, "%s|%d", key, exp)
	return hex.EncodeToString(mac.Sum(nil))
}

func (a *API) createUpload(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Purpose     string `json:"purpose"`
		ContentType string `json:"content_type"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if !purposes[b.Purpose] {
		return fieldErr("purpose", "invalid", "Unknown purpose")
	}
	if b.ContentType != "image/jpeg" {
		return fieldErr("content_type", "invalid", "Only image/jpeg")
	}
	key := "u/" + b.Purpose + "/" + domain.NewID() + ".jpg"
	exp := time.Now().Add(15 * time.Minute)
	url := fmt.Sprintf("%s/upload/%s?exp=%d&sig=%s", strings.TrimRight(a.svc.Cfg.PublicURL, "/"), key, exp.Unix(), a.uploadSig(key, exp.Unix()))
	a.svc.Lock()
	a.svc.St.Uploads[key] = b.Purpose
	a.svc.Touch()
	a.svc.Unlock()
	ok(w, map[string]any{"upload_url": url, "key": key, "expires_at": domain.At(exp)})
	return nil
}

func (a *API) safeUploadPath(key string) (string, bool) {
	if !keyRe.MatchString(key) {
		return "", false
	}
	baseDir := filepath.Clean(filepath.Join(a.svc.Cfg.DataDir, "uploads"))
	fullPath := filepath.Clean(filepath.Join(baseDir, filepath.FromSlash(key)))
	if !strings.HasPrefix(fullPath, baseDir+string(filepath.Separator)) {
		return "", false
	}
	return fullPath, true
}

func (a *API) putUpload(w http.ResponseWriter, r *http.Request) {
	key := r.PathValue("key")
	exp, _ := strconv.ParseInt(r.URL.Query().Get("exp"), 10, 64)
	path, validPath := a.safeUploadPath(key)
	if !validPath || time.Now().Unix() > exp || !hmac.Equal([]byte(r.URL.Query().Get("sig")), []byte(a.uploadSig(key, exp))) {
		http.Error(w, "invalid or expired upload URL", http.StatusForbidden)
		return
	}

	reader := http.MaxBytesReader(w, r.Body, 10<<20)
	var header [2]byte
	if _, err := io.ReadFull(reader, header[:]); err != nil || header[0] != 0xff || header[1] != 0xd8 {
		http.Error(w, "invalid image/jpeg payload", http.StatusUnsupportedMediaType)
		return
	}

	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	f, err := os.Create(path)
	if err != nil {
		http.Error(w, "storage error", http.StatusInternalServerError)
		return
	}
	defer f.Close()
	if _, err := io.Copy(f, io.MultiReader(bytes.NewReader(header[:]), reader)); err != nil {
		_ = f.Close()
		_ = os.Remove(path)
		http.Error(w, "upload too large", http.StatusRequestEntityTooLarge)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func (a *API) getFile(w http.ResponseWriter, r *http.Request) {
	path, validPath := a.safeUploadPath(r.PathValue("key"))
	if !validPath {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Security-Policy", "default-src 'none'")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFile(w, r, path)
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
