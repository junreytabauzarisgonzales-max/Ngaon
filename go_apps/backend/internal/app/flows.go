package app

// Handlers that call third-party APIs. Pattern: read what we need under the
// lock, release it, make the network call, then re-lock and apply.

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"sort"
	"strings"
	"time"
)

func (s *Server) publicBase() string { return strings.TrimRight(s.cfg.PublicURL, "/") }

func reqCtx(r *http.Request) (context.Context, context.CancelFunc) {
	return context.WithTimeout(r.Context(), 12*time.Second)
}

// ---------- quotes (Google Routes) ----------

func (s *Server) createQuote(w http.ResponseWriter, r *http.Request) error {
	var req QuoteRequest
	if err := decode(r, &req); err != nil {
		return err
	}
	// Food pickup is always the merchant's location.
	s.lock()
	if req.Service == "food" && req.Food != nil {
		if m := s.st.Merchants[req.Food.MerchantID]; m != nil {
			req.Pickup = Stop{Address: m.Merchant.Address, Location: m.Merchant.Location, ContactName: strp(m.Merchant.Name)}
		}
	}
	s.unlock()

	var rt *Route
	if s.maps.Enabled() {
		ctx, cancel := reqCtx(r)
		route, err := s.maps.Route(ctx, req.Pickup.Location, req.Dropoff.Location)
		cancel()
		if err == nil {
			rt = &route
		} else {
			logIntegration("google routes", err) // fall back to straight-line pricing
		}
	}

	s.lock()
	defer s.unlock()
	q, err := s.priceQuote(&req, rt)
	if err != nil {
		return err
	}
	q.UserID = claimsOf(r).Sub
	q.Request = &req
	s.st.Quotes[q.ID] = q
	ok(w, q)
	return nil
}

// ---------- jobs + PayMongo checkout ----------

func (s *Server) createJob(w http.ResponseWriter, r *http.Request) error {
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
	idem := r.Header.Get("Idempotency-Key")

	s.lock()
	if jid, done := s.st.Idempotency[uid+":"+idem]; idem != "" && done {
		v := s.jobView(s.st.Jobs[jid], "customer")
		s.unlock()
		ok(w, v)
		return nil
	}
	q := s.st.Quotes[b.QuoteID]
	if q == nil || q.UserID != uid || time.Now().After(q.ExpiresAt.Time) {
		s.unlock()
		return apiErr(409, "quote_expired", "Quote expired")
	}
	if _, err := s.priceQuote(q.Request, nil); err != nil { // menu/store may have changed
		s.unlock()
		return err
	}
	jobID, code, amount, service := newID(), s.nextCode(), q.TotalCentavos, q.Service
	s.unlock()

	online := b.PaymentMethod != "cash"
	var co Checkout
	if online && s.pm.Enabled() {
		ctx, cancel := reqCtx(r)
		var err error
		co, err = s.pm.CreateCheckout(ctx, code, "Ngain "+service+" "+code, amount, b.PaymentMethod,
			s.publicBase()+"/pay/return?status=success&ref="+code, s.publicBase()+"/pay/return?status=cancelled&ref="+code,
			map[string]string{"job_id": jobID, "kind": "job"})
		cancel()
		if err != nil {
			logIntegration("paymongo checkout", err)
			return apiErr(402, "payment_failed", "Could not start the payment. Please try again or pay with cash.")
		}
	}

	s.lock()
	defer s.unlock()
	if jid, done := s.st.Idempotency[uid+":"+idem]; idem != "" && done { // lost a race with a retry
		ok(w, s.jobView(s.st.Jobs[jid], "customer"))
		return nil
	}
	if s.st.Quotes[b.QuoteID] == nil {
		return apiErr(409, "quote_expired", "Quote expired")
	}
	js := s.buildJob(uid, q, b.PaymentMethod, b.Notes, jobID, code)
	if co.ID != "" {
		js.PMCheckoutID = co.ID
		js.Job.Payment.CheckoutURL = strp(co.URL)
	}
	s.st.Jobs[js.Job.ID] = js
	s.st.JobIDs = append(s.st.JobIDs, js.Job.ID)
	delete(s.st.Quotes, q.ID)
	if idem != "" {
		s.st.Idempotency[uid+":"+idem] = js.Job.ID
	}
	if online {
		s.setStatus(js, "pending_payment")
	} else {
		s.afterPayment(js)
	}
	ok(w, s.jobView(js, "customer"))
	return nil
}

func (s *Server) getJob(w http.ResponseWriter, r *http.Request) error {
	s.syncJobPayment(r.Context(), r.PathValue("id"))
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	ok(w, s.jobView(js, claimsOf(r).App))
	return nil
}

// markJobPaid is used by the dev pay page, PayMongo polling and webhooks.
func (s *Server) markJobPaid(js *JobState, paymentID string) {
	if js.Job.Status != "pending_payment" || js.Job.Payment.Status == "paid" {
		return
	}
	js.Job.Payment.Status = "paid"
	if paymentID != "" {
		js.PMPaymentID = paymentID
	}
	s.afterPayment(js)
}

// syncJobPayment asks PayMongo whether a pending checkout was paid. The app
// polls GET /jobs/{id} while waiting, so this works without public webhooks.
func (s *Server) syncJobPayment(ctx context.Context, jobID string) {
	if !s.pm.Enabled() {
		return
	}
	s.lock()
	js := s.st.Jobs[jobID]
	if js == nil || js.PMCheckoutID == "" || js.Job.Status != "pending_payment" || time.Since(js.PayCheckedAt) < 4*time.Second {
		s.unlock()
		return
	}
	js.PayCheckedAt = time.Now()
	checkoutID := js.PMCheckoutID
	s.unlock()

	c, cancel := context.WithTimeout(ctx, 8*time.Second)
	st, err := s.pm.RetrieveCheckout(c, checkoutID)
	cancel()
	if err != nil {
		logIntegration("paymongo retrieve", err)
		return
	}
	if st.Paid {
		s.lock()
		s.markJobPaid(js, st.PaymentID)
		s.unlock()
	}
}

// ---------- rider top-ups ----------

func (s *Server) riderTopup(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		AmountCentavos int    `json:"amount_centavos"`
		Method         string `json:"method"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.AmountCentavos < 10000 || b.AmountCentavos > 2000000 {
		return fieldErr("amount_centavos", "out_of_range", "Top up between ₱100 and ₱20,000")
	}
	if b.Method != "gcash" && b.Method != "maya" {
		return fieldErr("method", "invalid", "GCash or Maya only")
	}
	uid := claimsOf(r).Sub
	idem := r.Header.Get("Idempotency-Key")
	s.lock()
	if id, seen := s.st.Idempotency[uid+":"+idem]; idem != "" && seen {
		if t := s.st.Topups[id]; t != nil {
			url := s.topupURL(t)
			s.unlock()
			ok(w, map[string]string{"topup_id": t.ID, "checkout_url": url})
			return nil
		}
	}
	s.unlock()

	t := &Topup{ID: newID(), UserID: uid, AmountCentavos: b.AmountCentavos, Method: b.Method, Status: "pending"}
	if s.pm.Enabled() {
		ctx, cancel := reqCtx(r)
		co, err := s.pm.CreateCheckout(ctx, "TOPUP-"+t.ID[:8], "Ngain Rider wallet top-up", b.AmountCentavos, b.Method,
			s.publicBase()+"/pay/return?status=success", s.publicBase()+"/pay/return?status=cancelled",
			map[string]string{"topup_id": t.ID, "kind": "topup"})
		cancel()
		if err != nil {
			logIntegration("paymongo topup checkout", err)
			return apiErr(402, "payment_failed", "Could not start the payment. Please try again.")
		}
		t.PMCheckoutID, t.CheckoutURL = co.ID, co.URL
	}
	s.lock()
	defer s.unlock()
	s.st.Topups[t.ID] = t
	if idem != "" {
		s.st.Idempotency[uid+":"+idem] = t.ID
	}
	s.touch()
	ok(w, map[string]string{"topup_id": t.ID, "checkout_url": s.topupURL(t)})
	return nil
}

func (s *Server) topupURL(t *Topup) string {
	if t.CheckoutURL != "" {
		return t.CheckoutURL
	}
	return s.publicBase() + "/pay/topup/" + t.ID
}

func (s *Server) creditTopup(t *Topup) {
	if t.Status == "paid" {
		return
	}
	t.Status = "paid"
	s.addTx(t.UserID, "topup", t.AmountCentavos, "", map[string]string{"gcash": "GCash", "maya": "Maya"}[t.Method]+" top-up")
	if rd := s.st.Riders[t.UserID]; rd != nil {
		s.emit(t.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
	}
}

// syncTopups checks the rider's pending PayMongo top-ups (wallet screen polls).
func (s *Server) syncTopups(ctx context.Context, uid string) {
	if !s.pm.Enabled() {
		return
	}
	s.lock()
	var pending []*Topup
	for _, t := range s.st.Topups {
		if t.UserID == uid && t.Status == "pending" && t.PMCheckoutID != "" && time.Since(t.CheckedAt) > 4*time.Second {
			t.CheckedAt = time.Now()
			pending = append(pending, t)
		}
	}
	s.unlock()
	for _, t := range pending {
		c, cancel := context.WithTimeout(ctx, 8*time.Second)
		st, err := s.pm.RetrieveCheckout(c, t.PMCheckoutID)
		cancel()
		if err != nil {
			logIntegration("paymongo retrieve topup", err)
			continue
		}
		if st.Paid {
			s.lock()
			s.creditTopup(t)
			s.unlock()
		}
	}
}

func (s *Server) riderWallet(w http.ResponseWriter, r *http.Request) error {
	s.syncTopups(r.Context(), claimsOf(r).Sub)
	s.lock()
	defer s.unlock()
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	ok(w, map[string]int{"balance_centavos": rd.Profile.BalanceCentavos, "min_balance_centavos": rd.Profile.MinBalanceCentavos})
	return nil
}

// ---------- PayMongo webhook ----------

// POST /webhooks/paymongo — needs a public HTTPS URL registered in PayMongo.
// The event only tells us *which* checkout to look at; we always re-fetch it
// from the PayMongo API (with our secret key) before marking anything paid.
func (s *Server) paymongoWebhook(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil || !s.pm.Enabled() {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if !s.pm.VerifyWebhook(raw, r.Header.Get("Paymongo-Signature")) {
		log.Printf("[paymongo webhook] signature not verified; confirming via API before acting")
	}
	var ev struct {
		Data struct {
			Attributes struct {
				Type string `json:"type"`
				Data struct {
					ID         string `json:"id"`
					Attributes struct {
						Metadata map[string]string `json:"metadata"`
					} `json:"attributes"`
				} `json:"data"`
			} `json:"attributes"`
		} `json:"data"`
	}
	if json.Unmarshal(raw, &ev) != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	a := ev.Data.Attributes
	w.WriteHeader(http.StatusOK) // ack fast; work continues below
	if a.Type != "checkout_session.payment.paid" || a.Data.ID == "" {
		return
	}
	go func(checkoutID string, meta map[string]string) {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		st, err := s.pm.RetrieveCheckout(ctx, checkoutID)
		if err != nil || !st.Paid {
			logIntegration("paymongo webhook confirm", err)
			return
		}
		s.lock()
		defer s.unlock()
		for _, js := range s.st.Jobs {
			if js.PMCheckoutID == checkoutID {
				s.markJobPaid(js, st.PaymentID)
				return
			}
		}
		for _, t := range s.st.Topups {
			if t.PMCheckoutID == checkoutID {
				s.creditTopup(t)
				return
			}
		}
	}(a.Data.ID, a.Data.Attributes.Metadata)
}

// ---------- Didit KYC ----------

func (s *Server) kycStatus(rd *Rider) *string {
	if !s.didit.Enabled() {
		return nil
	}
	if rd.Profile.KycStatus == nil {
		rd.Profile.KycStatus = strp("not_started")
	}
	return rd.Profile.KycStatus
}

func (s *Server) riderMe(w http.ResponseWriter, r *http.Request) error {
	uid := claimsOf(r).Sub
	s.syncKyc(r.Context(), uid)
	s.syncTopups(r.Context(), uid)
	s.lock()
	defer s.unlock()
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	s.kycStatus(rd)
	ok(w, rd.Profile)
	return nil
}

// POST /rider/kyc/session (ADDED): returns Didit's hosted verification URL.
func (s *Server) riderKycSession(w http.ResponseWriter, r *http.Request) error {
	if !s.didit.Enabled() {
		return apiErr(409, "invalid_status_transition", "Identity verification is not enabled")
	}
	uid := claimsOf(r).Sub
	s.lock()
	rd, err := s.rider(r)
	if err != nil {
		s.unlock()
		return err
	}
	if st := s.kycStatus(rd); *st == "approved" {
		s.unlock()
		ok(w, map[string]any{"session_id": rd.KycSessionID, "url": rd.KycURL, "kyc_status": *st})
		return nil
	}
	phone := s.st.Users[uid].Phone
	s.unlock()

	ctx, cancel := reqCtx(r)
	sess, err := s.didit.CreateSession(ctx, uid, s.publicBase()+"/kyc/return", phone)
	cancel()
	if err != nil {
		logIntegration("didit create session", err)
		return apiErr(502, "server_error", "Identity verification is unavailable right now. Please try again.")
	}
	s.lock()
	defer s.unlock()
	rd.KycSessionID, rd.KycURL = sess.SessionID, sess.URL
	st := kycFromDidit(sess.Status)
	if st == "not_started" {
		st = "in_progress"
	}
	rd.Profile.KycStatus = strp(st)
	s.touch()
	ok(w, map[string]any{"session_id": sess.SessionID, "url": sess.URL, "kyc_status": st})
	return nil
}

func (s *Server) applyKyc(rd *Rider, diditStatus string) {
	st := kycFromDidit(diditStatus)
	if rd.Profile.KycStatus != nil && *rd.Profile.KycStatus == st {
		return
	}
	rd.Profile.KycStatus = strp(st)
	s.touch()
	switch {
	case st == "approved" && rd.Profile.Status == "pending_review":
		s.setRiderReview(rd, true, "") // documents + identity both done
	case st == "declined" && rd.Profile.Status != "suspended":
		s.setRiderReview(rd, false, "Identity verification was declined. Please try again or contact Ngain support.")
	default:
		s.emit(rd.Profile.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
	}
}

// syncKyc polls Didit for an unfinished session (rider app polls GET /rider/me).
func (s *Server) syncKyc(ctx context.Context, uid string) {
	if !s.didit.Enabled() {
		return
	}
	s.lock()
	rd := s.st.Riders[uid]
	if rd == nil || rd.KycSessionID == "" || time.Since(rd.KycCheckedAt) < 8*time.Second ||
		(rd.Profile.KycStatus != nil && (*rd.Profile.KycStatus == "approved" || *rd.Profile.KycStatus == "declined")) {
		s.unlock()
		return
	}
	rd.KycCheckedAt = time.Now()
	sid := rd.KycSessionID
	s.unlock()
	c, cancel := context.WithTimeout(ctx, 8*time.Second)
	status, err := s.didit.Decision(c, sid)
	cancel()
	if err != nil {
		logIntegration("didit decision", err)
		return
	}
	s.lock()
	s.applyKyc(rd, status)
	s.unlock()
}

// POST /webhooks/didit — signature checked, then the decision is re-fetched.
func (s *Server) diditWebhook(w http.ResponseWriter, r *http.Request) {
	raw, err := io.ReadAll(io.LimitReader(r.Body, 2<<20))
	if err != nil || !s.didit.Enabled() {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	if !s.didit.VerifyWebhook(raw, r.Header.Get("X-Signature"), r.Header.Get("X-Signature-Previous"), r.Header.Get("X-Timestamp")) {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}
	var ev struct {
		SessionID  string `json:"session_id"`
		VendorData string `json:"vendor_data"`
	}
	if json.Unmarshal(raw, &ev) != nil || ev.SessionID == "" {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	w.WriteHeader(http.StatusOK)
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		status, err := s.didit.Decision(ctx, ev.SessionID)
		if err != nil {
			logIntegration("didit webhook decision", err)
			return
		}
		s.lock()
		defer s.unlock()
		rd := s.st.Riders[ev.VendorData]
		if rd == nil {
			for _, x := range s.st.Riders {
				if x.KycSessionID == ev.SessionID {
					rd = x
				}
			}
		}
		if rd == nil {
			return
		}
		rd.KycSessionID = ev.SessionID
		s.applyKyc(rd, status)
	}()
}

// ---------- geo (Google Geocoding / Places, local gazetteer fallback) ----------

func (s *Server) geoReverse(w http.ResponseWriter, r *http.Request) error {
	p, err := parseLatLng(r)
	if err != nil {
		return err
	}
	if s.maps.Enabled() {
		ctx, cancel := reqCtx(r)
		addr, err := s.maps.Reverse(ctx, p)
		cancel()
		if err == nil && addr != "" {
			ok(w, map[string]string{"address": addr})
			return nil
		}
		logIntegration("google geocode", err)
	}
	s.lock()
	defer s.unlock()
	best, bestD := GeoPlace{}, 1<<30
	for _, g := range s.gazetteer() {
		if d := distanceM(p, g.Location); d < bestD {
			best, bestD = g, d
		}
	}
	addr := "Bongao, Tawi-Tawi"
	switch {
	case best.Name == "":
	case bestD < 80:
		addr = best.Name + ", Bongao"
	case bestD < 3000:
		addr = "Near " + best.Name + ", Bongao"
	}
	ok(w, map[string]string{"address": addr})
	return nil
}

func (s *Server) geoSearch(w http.ResponseWriter, r *http.Request) error {
	near, err := parseLatLng(r)
	if err != nil {
		return err
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	var google []GeoPlace
	if s.maps.Enabled() && len([]rune(q)) >= 2 {
		ctx, cancel := reqCtx(r)
		google, err = s.maps.Search(ctx, q, near)
		cancel()
		logIntegration("google places", err)
	}
	s.lock()
	defer s.unlock()
	// Local stores/landmarks first (they are bookable), then Google results.
	lq := strings.ToLower(q)
	out := []GeoPlace{}
	for _, g := range s.gazetteer() {
		if lq == "" || strings.Contains(strings.ToLower(g.Name+" "+g.Address), lq) {
			out = append(out, g)
		}
	}
	sort.Slice(out, func(i, j int) bool { return distanceM(near, out[i].Location) < distanceM(near, out[j].Location) })
	out = append(out, google...)
	if len(out) > 10 {
		out = out[:10]
	}
	ok(w, out)
	return nil
}

// ---------- return pages (after PayMongo / Didit in the in-app browser) ----------

func (s *Server) returnPage(title, body string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = io.WriteString(w, `<!doctype html><html><head><title>Ngain</title>`+pageCSS+`</head><body><div class="card"><div class="brand">Ngain</div><h1>`+title+`</h1><p class="muted">`+body+`</p></div></body></html>`)
	}
}
