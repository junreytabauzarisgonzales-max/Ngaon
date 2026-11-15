package app

import (
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
)

// ---------- merchants (public) ----------

func (s *Server) publicMerchant(row *MerchantRow, near *LatLng, withMenu bool) Merchant {
	m := deepCopy(row.Merchant)
	if !withMenu {
		m.Menu = nil
	} else {
		sort.Slice(m.Menu, func(i, j int) bool { return m.Menu[i].SortOrder < m.Menu[j].SortOrder })
		if m.Menu == nil {
			m.Menu = []MenuCategory{}
		}
	}
	if near != nil {
		m.DistanceM = intp(distanceM(*near, m.Location))
	}
	if row.RatingCount > 0 {
		v := math.Round(float64(row.RatingSum)/float64(row.RatingCount)*10) / 10
		m.Rating = &v
	}
	return m
}

func (s *Server) listMerchants(w http.ResponseWriter, r *http.Request) error {
	near, err := parseLatLng(r)
	if err != nil {
		return err
	}
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	s.lock()
	defer s.unlock()
	var out []Merchant
	for _, id := range s.st.MerchantIDs {
		row := s.st.Merchants[id]
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
		out = append(out, s.publicMerchant(row, &near, false))
	}
	sort.SliceStable(out, func(i, j int) bool {
		ai, aj := s.st.Merchants[out[i].ID].Merchant.acceptsOrders(), s.st.Merchants[out[j].ID].Merchant.acceptsOrders()
		if ai != aj {
			return ai
		}
		return *out[i].DistanceM < *out[j].DistanceM
	})
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (s *Server) getMerchant(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	row := s.st.Merchants[r.PathValue("id")]
	if row == nil {
		return errNotFound
	}
	ok(w, s.publicMerchant(row, nil, true))
	return nil
}

// ---------- quotes ----------

func findItem(m *Merchant, id string) *MenuItem {
	for ci := range m.Menu {
		for ii := range m.Menu[ci].Items {
			if m.Menu[ci].Items[ii].ID == id {
				return &m.Menu[ci].Items[ii]
			}
		}
	}
	return nil
}

func findOption(it *MenuItem, id string) *AddonOption {
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

func (s *Server) createQuote(w http.ResponseWriter, r *http.Request) error {
	var req QuoteRequest
	if err := decode(r, &req); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	q, err := s.priceQuote(&req)
	if err != nil {
		return err
	}
	q.UserID = claimsOf(r).Sub
	q.Request = &req
	s.st.Quotes[q.ID] = q
	ok(w, q)
	return nil
}

// priceQuote: same tariff as the mock backend.
func (s *Server) priceQuote(req *QuoteRequest) (*Quote, error) {
	if req.Service == "food" && req.Food != nil {
		if m := s.st.Merchants[req.Food.MerchantID]; m != nil {
			req.Pickup = Stop{Address: m.Merchant.Address, Location: m.Merchant.Location, ContactName: strp(m.Merchant.Name)}
		}
	}
	if !s.inServiceArea(req.Pickup.Location) || !s.inServiceArea(req.Dropoff.Location) {
		return nil, apiErr(422, "out_of_service_area", "Outside the Bongao service area")
	}
	dist := int(float64(distanceM(req.Pickup.Location, req.Dropoff.Location)) * 1.3)
	dur := max(180, int(float64(dist)/1000/22*3600))
	km := int(math.Ceil(float64(dist) / 1000))
	kmLabel := fmt.Sprintf("Distance %.1f km", float64(dist)/1000)
	var lines []FareLine
	add := func(l string, a int) { lines = append(lines, FareLine{l, a}) }
	fees := 0
	var maxBudget *int
	switch req.Service {
	case "ride":
		add("Base fare", 4000)
		add(kmLabel, max(0, km-1)*1500)
	case "food":
		if req.Food == nil || len(req.Food.Items) == 0 {
			return nil, fieldErr("food", "required", "No items")
		}
		row := s.st.Merchants[req.Food.MerchantID]
		if row == nil {
			return nil, errNotFound
		}
		m := &row.Merchant
		if !m.acceptsOrders() {
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
		add("Food subtotal", sub)
		add("Delivery fee", 3900+max(0, km-1)*1000)
		add("Service fee", 1000)
	case "pabili":
		if req.Pabili == nil || len(req.Pabili.Items) == 0 || strings.TrimSpace(req.Pabili.StoreName) == "" {
			return nil, fieldErr("pabili", "required", "Store and items required")
		}
		mb := maxPabiliBudget
		maxBudget = &mb
		if req.Pabili.EstimatedItemTotalCentavos > mb {
			return nil, fieldErr("estimated_item_total_centavos", fmt.Sprintf("max_%d", mb), "Budget too high")
		}
		add("Pabili fee", 6000)
		add(kmLabel, max(0, km-1)*1000)
	case "padala":
		if req.Padala == nil || strings.TrimSpace(req.Padala.Description) == "" || !phoneRe.MatchString(req.Padala.RecipientPhone) {
			return nil, fieldErr("padala", "invalid", "Recipient and description required")
		}
		base := map[string]int{"small": 5000, "medium": 6500, "large": 8500}[req.Padala.Size]
		if base == 0 {
			return nil, fieldErr("size", "invalid", "Invalid size")
		}
		add("Base fare ("+req.Padala.Size+")", base)
		add(kmLabel, max(0, km-1)*1500)
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
	return &Quote{
		ID: newID(), Service: req.Service, DistanceM: dist, DurationS: dur, ExpiresAt: *at(time.Now().Add(5 * time.Minute)),
		Breakdown: lines, TotalCentavos: total, MaxItemBudgetCentavos: maxBudget, FeesCentavos: fees,
	}, nil
}

// ---------- jobs ----------

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
	s.lock()
	defer s.unlock()
	idem := r.Header.Get("Idempotency-Key")
	if idem != "" {
		if jid, done := s.st.Idempotency[uid+":"+idem]; done {
			ok(w, s.jobView(s.st.Jobs[jid], "customer"))
			return nil
		}
	}
	q := s.st.Quotes[b.QuoteID]
	if q == nil || q.UserID != uid || time.Now().After(q.ExpiresAt.Time) {
		return apiErr(409, "quote_expired", "Quote expired")
	}
	// Re-validate (menu or store state may have changed since the quote).
	if _, err := s.priceQuote(q.Request); err != nil {
		return err
	}
	js := s.buildJob(uid, q, b.PaymentMethod, b.Notes)
	s.st.Jobs[js.Job.ID] = js
	s.st.JobIDs = append(s.st.JobIDs, js.Job.ID)
	delete(s.st.Quotes, q.ID)
	if idem != "" {
		s.st.Idempotency[uid+":"+idem] = js.Job.ID
	}
	if b.PaymentMethod == "cash" {
		s.afterPayment(js)
	} else {
		s.setStatus(js, "pending_payment")
	}
	ok(w, s.jobView(js, "customer"))
	return nil
}

func (s *Server) buildJob(uid string, q *Quote, method string, notes *string) *JobState {
	req := q.Request
	id := newID()
	dropoff := req.Dropoff
	if notes != nil && strings.TrimSpace(*notes) != "" {
		dropoff.Notes = notes
	}
	j := Job{
		ID: id, Code: s.nextCode(), Service: req.Service, CreatedAt: Now(), UpdatedAt: Now(),
		Pickup: req.Pickup, Dropoff: dropoff,
		Fare:     Fare{Breakdown: q.Breakdown, TotalCentavos: q.TotalCentavos},
		Payment:  JobPayment{Method: method, Status: "pending"},
		Timeline: []TimelineEntry{}, AllowedActions: []string{},
	}
	if method != "cash" {
		j.Payment.CheckoutURL = strp(strings.TrimRight(s.cfg.PublicURL, "/") + "/pay/job/" + id)
	}
	earnings := q.FeesCentavos * 80 / 100
	js := &JobState{CustomerID: uid, FeesCentavos: q.FeesCentavos, EarningsCentavos: earnings, CommissionCentavos: q.FeesCentavos - earnings}
	switch req.Service {
	case "food":
		row := s.st.Merchants[req.Food.MerchantID]
		m := &row.Merchant
		js.MerchantID = m.ID
		j.Merchant = &JobMerchant{ID: m.ID, Name: m.Name, PhoneMasked: maskPhone(row.Phone)}
		sub := 0
		var lines []OrderLine
		for _, it := range req.Food.Items {
			item := findItem(m, it.ItemID)
			unit := item.PriceCentavos
			addons := []string{}
			for _, oid := range it.AddonOptionIDs {
				o := findOption(item, oid)
				unit += o.PriceCentavos
				addons = append(addons, o.Name)
			}
			lines = append(lines, OrderLine{Name: item.Name, Quantity: it.Quantity, Addons: addons, Note: it.Note, LineTotalCentavos: unit * it.Quantity})
			sub += unit * it.Quantity
		}
		commission := sub / 10
		j.Food = &JobFood{Items: lines, SubtotalCentavos: sub}
		if method == "cash" {
			j.Food.RiderPaysMerchantCentavos = intp(sub - commission)
		}
		js.Order = &MerchantOrderState{ID: newID(), Status: "new", Commission: commission}
	case "pabili":
		j.Pabili = &JobPabili{StoreName: req.Pabili.StoreName, Items: req.Pabili.Items}
	case "padala":
		p := req.Padala
		j.Padala = &JobPadala{Size: p.Size, Description: p.Description, RecipientName: p.RecipientName, RecipientPhone: p.RecipientPhone}
		if p.PhotoKey != nil {
			j.Padala.PhotoURL = s.fileURL(*p.PhotoKey)
		}
		if j.Dropoff.ContactName == nil {
			j.Dropoff.ContactName = strp(p.RecipientName)
		}
		if j.Dropoff.ContactPhone == nil {
			j.Dropoff.ContactPhone = strp(p.RecipientPhone)
		}
	}
	js.Job = j
	return js
}

// afterPayment moves a paid (or cash) job into the merchant / dispatch flow.
func (s *Server) afterPayment(js *JobState) {
	if js.Job.Service == "food" {
		js.MerchantDeadline = time.Now().Add(3 * time.Minute)
		s.setStatus(js, "merchant_pending")
		ov := s.orderView(js)
		for _, uid := range s.merchantUserIDs(js.MerchantID) {
			s.emit(uid, "merchant", "order.new", map[string]any{"order": ov})
		}
		return
	}
	s.setStatus(js, "searching")
	s.dispatch(js)
}

func (s *Server) jobFor(r *http.Request) (*JobState, error) {
	js := s.st.Jobs[r.PathValue("id")]
	if js == nil {
		return nil, errNotFound
	}
	uid := claimsOf(r).Sub
	if js.CustomerID == uid || (js.RiderUserID != "" && js.RiderUserID == uid) {
		return js, nil
	}
	return nil, errNotFound
}

func (s *Server) listJobs(w http.ResponseWriter, r *http.Request) error {
	active := r.URL.Query().Get("status") != "past"
	uid := claimsOf(r).Sub
	s.lock()
	defer s.unlock()
	var out []Job
	for i := len(s.st.JobIDs) - 1; i >= 0; i-- {
		js := s.st.Jobs[s.st.JobIDs[i]]
		if js == nil || js.CustomerID != uid || isLive(js.Job.Status) != active {
			continue
		}
		out = append(out, s.jobView(js, "customer"))
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (s *Server) getJob(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	ok(w, s.jobView(js, claimsOf(r).App))
	return nil
}

func (s *Server) cancelJob(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Reason string `json:"reason"`
	}
	_ = decode(r, &b)
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	if js.CustomerID != claimsOf(r).Sub || !contains(customerActions(js), "cancel") {
		return apiErr(409, "job_not_cancellable", "This booking can no longer be cancelled")
	}
	reason := strings.TrimSpace(b.Reason)
	if reason == "" {
		reason = "Cancelled by customer"
	}
	s.cancel(js, "customer", reason)
	ok(w, s.jobView(js, "customer"))
	return nil
}

// cancel ends a job and releases the rider / merchant.
func (s *Server) cancel(js *JobState, by, reason string) {
	js.Job.CancelledBy = strp(by)
	js.Job.CancelReason = strp(reason)
	if js.Job.Payment.Status == "paid" {
		js.Job.Payment.Status = "refunded"
	}
	if r := s.st.Riders[js.RiderUserID]; r != nil && r.ActiveJobID == js.Job.ID {
		r.ActiveJobID = ""
	}
	for id, o := range s.st.Offers {
		if o.JobID == js.Job.ID {
			delete(s.st.Offers, id)
			s.emit(o.RiderUserID, "rider", "offer.expired", map[string]any{"offer_id": id})
		}
	}
	if js.Order != nil && by == "merchant" {
		js.Order.Status = "rejected"
	}
	s.setStatus(js, "cancelled")
}

func (s *Server) confirmItems(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Approved bool `json:"approved"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	if js.CustomerID != claimsOf(r).Sub || js.Job.Status != "items_purchased" {
		return apiErr(409, "invalid_status_transition", "Nothing to confirm")
	}
	if b.Approved {
		s.setStatus(js, "picked_up")
	} else {
		// Open question Q1 in the contract: dispute = cancel + support follow-up.
		s.cancel(js, "customer", "Item total disputed by customer. Go support will contact you.")
	}
	ok(w, s.jobView(js, "customer"))
	return nil
}

func (s *Server) rateJob(w http.ResponseWriter, r *http.Request) error {
	var b Rating
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.RiderRating < 1 || b.RiderRating > 5 || (b.MerchantRating != nil && (*b.MerchantRating < 1 || *b.MerchantRating > 5)) {
		return fieldErr("rider_rating", "invalid", "Ratings are 1–5")
	}
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	if js.CustomerID != claimsOf(r).Sub || !contains(customerActions(js), "rate") {
		return apiErr(409, "invalid_status_transition", "Cannot rate this job")
	}
	js.Rated = true
	b.JobID = js.Job.ID
	s.st.Ratings = append(s.st.Ratings, b)
	if rd := s.st.Riders[js.RiderUserID]; rd != nil {
		rd.RatingSum += b.RiderRating
		rd.RatingCount++
		v := math.Round(float64(rd.RatingSum)/float64(rd.RatingCount)*10) / 10
		rd.Profile.Rating = &v
	}
	if m := s.st.Merchants[js.MerchantID]; m != nil && b.MerchantRating != nil {
		m.RatingSum += *b.MerchantRating
		m.RatingCount++
	}
	s.touch()
	okEmpty(w)
	return nil
}

func (s *Server) shareJob(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	if js.ShareToken == "" {
		js.ShareToken = randToken(12)
		s.st.Shares[js.ShareToken] = js.Job.ID
		s.touch()
	}
	ok(w, map[string]any{"url": strings.TrimRight(s.cfg.PublicURL, "/") + "/t/" + js.ShareToken, "expires_at": at(time.Now().Add(6 * time.Hour))})
	return nil
}

func (s *Server) sosJob(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Location LatLng `json:"location"`
	}
	_ = decode(r, &b)
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	s.st.SOS = append(s.st.SOS, SOSAlert{JobID: js.Job.ID, UserID: claimsOf(r).Sub, Location: b.Location, At: Now()})
	s.touch()
	log.Printf("🚨 SOS on %s by %s at %.5f,%.5f", js.Job.Code, claimsOf(r).Sub, b.Location.Lat, b.Location.Lng)
	okEmpty(w)
	return nil
}

// callJob: no telephony proxy yet, so return the other party's number.
func (s *Server) callJob(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	other := js.RiderUserID
	if claimsOf(r).Sub == js.RiderUserID {
		other = js.CustomerID
	}
	u := s.st.Users[other]
	if u == nil {
		return apiErr(409, "invalid_status_transition", "No one to call yet")
	}
	ok(w, map[string]string{"masked_number": u.Phone})
	return nil
}

// ---------- chat ----------

func (s *Server) listMessages(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	page, next := paginate(s.st.Chats[js.Job.ID], r, 50)
	okPage(w, page, next)
	return nil
}

func (s *Server) sendMessage(w http.ResponseWriter, r *http.Request) error {
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
	s.lock()
	defer s.unlock()
	js, err := s.jobFor(r)
	if err != nil {
		return err
	}
	if !isLive(js.Job.Status) {
		return apiErr(409, "invalid_status_transition", "This chat has ended")
	}
	uid := claimsOf(r).Sub
	sender, to, toApp := "customer", js.RiderUserID, "rider"
	if uid == js.RiderUserID {
		sender, to, toApp = "rider", js.CustomerID, "customer"
	}
	m := &ChatMessage{ID: newID(), JobID: js.Job.ID, Sender: sender, Text: b.Text, CreatedAt: Now()}
	if b.ImageKey != nil {
		m.ImageURL = s.fileURL(*b.ImageKey)
	}
	s.st.Chats[js.Job.ID] = append(s.st.Chats[js.Job.ID], m)
	s.emit(to, toApp, "chat.message", map[string]any{"message": m})
	s.touch()
	ok(w, m)
	return nil
}

func (s *Server) systemMessage(js *JobState, text string) {
	m := &ChatMessage{ID: newID(), JobID: js.Job.ID, Sender: "system", Text: strp(text), CreatedAt: Now()}
	s.st.Chats[js.Job.ID] = append(s.st.Chats[js.Job.ID], m)
	s.emit(js.CustomerID, "customer", "chat.message", map[string]any{"message": m})
	s.emit(js.RiderUserID, "rider", "chat.message", map[string]any{"message": m})
}

// ---------- uploads (presigned PUT served by this backend) ----------

var purposes = map[string]bool{
	"rider_license": true, "rider_orcr": true, "rider_selfie": true, "rider_clearance": true, "receipt": true,
	"proof_of_delivery": true, "parcel_photo": true, "chat_image": true, "menu_item_photo": true,
	"merchant_logo": true, "merchant_cover": true,
}
var keyRe = regexp.MustCompile(`^u/[a-z_]+/[0-9a-f-]{36}\.jpg$`)

func (s *Server) uploadSig(key string, exp int64) string {
	mac := hmac.New(sha256.New, s.cfg.JWTSecret)
	fmt.Fprintf(mac, "%s|%d", key, exp)
	return hex.EncodeToString(mac.Sum(nil))
}

func (s *Server) createUpload(w http.ResponseWriter, r *http.Request) error {
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
	key := "u/" + b.Purpose + "/" + newID() + ".jpg"
	exp := time.Now().Add(15 * time.Minute)
	url := fmt.Sprintf("%s/upload/%s?exp=%d&sig=%s", strings.TrimRight(s.cfg.PublicURL, "/"), key, exp.Unix(), s.uploadSig(key, exp.Unix()))
	s.lock()
	s.st.Uploads[key] = b.Purpose
	s.touch()
	s.unlock()
	ok(w, map[string]any{"upload_url": url, "key": key, "expires_at": at(exp)})
	return nil
}

func (s *Server) putUpload(w http.ResponseWriter, r *http.Request) {
	key := r.PathValue("key")
	exp, _ := strconv.ParseInt(r.URL.Query().Get("exp"), 10, 64)
	if !keyRe.MatchString(key) || time.Now().Unix() > exp || !hmac.Equal([]byte(r.URL.Query().Get("sig")), []byte(s.uploadSig(key, exp))) {
		http.Error(w, "invalid or expired upload URL", http.StatusForbidden)
		return
	}
	path := filepath.Join(s.cfg.DataDir, "uploads", filepath.FromSlash(key))
	_ = os.MkdirAll(filepath.Dir(path), 0o755)
	f, err := os.Create(path)
	if err != nil {
		http.Error(w, "storage error", 500)
		return
	}
	defer f.Close()
	if _, err := io.Copy(f, http.MaxBytesReader(w, r.Body, 10<<20)); err != nil {
		http.Error(w, "upload too large", http.StatusRequestEntityTooLarge)
		return
	}
	w.WriteHeader(200)
}

func (s *Server) getFile(w http.ResponseWriter, r *http.Request) {
	key := r.PathValue("key")
	if !keyRe.MatchString(key) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "image/jpeg")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	http.ServeFile(w, r, filepath.Join(s.cfg.DataDir, "uploads", filepath.FromSlash(key)))
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}
