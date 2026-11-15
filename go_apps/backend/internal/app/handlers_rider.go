package app

import (
	"log"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"
)

func (s *Server) rider(r *http.Request) (*Rider, error) {
	uid := claimsOf(r).Sub
	rd := s.st.Riders[uid]
	if rd == nil {
		if claimsOf(r).App != "rider" {
			return nil, errForbidden
		}
		rd = &Rider{Profile: RiderProfile{ID: newID(), UserID: uid, Status: "incomplete", BalanceCentavos: s.cfg.RiderStartBalance, MinBalanceCentavos: 10000}}
		s.st.Riders[uid] = rd
		s.touch()
	}
	return rd, nil
}

func (s *Server) riderMe(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	ok(w, rd.Profile)
	return nil
}

func (s *Server) riderSubmit(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Vehicle   Vehicle `json:"vehicle"`
		Documents struct {
			LicenseKey   string `json:"license_key"`
			OrcrKey      string `json:"orcr_key"`
			SelfieKey    string `json:"selfie_key"`
			ClearanceKey string `json:"clearance_key"`
		} `json:"documents"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if strings.TrimSpace(b.Vehicle.Plate) == "" || strings.TrimSpace(b.Vehicle.MakeModel) == "" || strings.TrimSpace(b.Vehicle.Color) == "" {
		return fieldErr("vehicle", "required", "Vehicle details required")
	}
	s.lock()
	defer s.unlock()
	docs := map[string]string{"license_key": b.Documents.LicenseKey, "orcr_key": b.Documents.OrcrKey, "selfie_key": b.Documents.SelfieKey, "clearance_key": b.Documents.ClearanceKey}
	for f, k := range docs {
		if _, uploaded := s.st.Uploads[k]; !uploaded {
			return fieldErr(f, "not_uploaded", "Upload all documents first")
		}
	}
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	if rd.Profile.Status == "approved" || rd.Profile.Status == "suspended" {
		return apiErr(409, "invalid_status_transition", "Profile already reviewed")
	}
	v := b.Vehicle
	v.Plate = strings.ToUpper(strings.TrimSpace(v.Plate))
	rd.Profile.Vehicle = &v
	rd.Documents = docs
	rd.Profile.Status = "pending_review"
	rd.Profile.RejectionReason = nil
	rd.SubmittedAt = time.Now()
	s.touch()
	log.Printf("rider application from %s (%s) waiting for review", s.userName(rd.Profile.UserID), v.Plate)
	ok(w, rd.Profile)
	return nil
}

func (s *Server) riderStatus(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Online   bool    `json:"online"`
		Location *LatLng `json:"location"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	if b.Online {
		if rd.Profile.Status != "approved" {
			return apiErr(403, "rider_not_approved", "Your account is not approved yet")
		}
		if rd.Profile.BalanceCentavos < rd.Profile.MinBalanceCentavos {
			return apiErr(402, "insufficient_balance", "Top up your wallet first")
		}
	}
	rd.Profile.IsOnline = b.Online
	if b.Location != nil {
		rd.Location = b.Location
		rd.LocationAt = time.Now()
	}
	if !b.Online {
		for id, o := range s.st.Offers {
			if o.RiderUserID == rd.Profile.UserID {
				delete(s.st.Offers, id)
				if js := s.st.Jobs[o.JobID]; js != nil {
					s.dispatch(js)
				}
			}
		}
	}
	s.touch()
	ok(w, rd.Profile)
	return nil
}

// updateRiderLocation is used by WS `rider.location` and POST /rider/location.
func (s *Server) updateRiderLocation(uid string, loc LatLng, heading *float64) {
	rd := s.st.Riders[uid]
	if rd == nil {
		return
	}
	rd.Location = &loc
	rd.LocationAt = time.Now()
	if js := s.st.Jobs[rd.ActiveJobID]; js != nil && isLive(js.Job.Status) {
		data := map[string]any{"job_id": js.Job.ID, "location": loc}
		if heading != nil {
			data["heading"] = *heading
		}
		s.emit(js.CustomerID, "customer", "rider.location", data)
	}
}

func (s *Server) riderLocationHTTP(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Location LatLng   `json:"location"`
		Heading  *float64 `json:"heading"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	s.updateRiderLocation(claimsOf(r).Sub, b.Location, b.Heading)
	okEmpty(w)
	return nil
}

func (s *Server) offerJSON(o *JobOffer) map[string]any {
	js := s.st.Jobs[o.JobID]
	return map[string]any{
		"id": o.ID, "job": s.jobView(js, "rider"), "earnings_centavos": o.EarningsCentavos,
		"pickup_distance_m": o.PickupDistanceM, "expires_at": o.ExpiresAt,
	}
}

func (s *Server) currentOffer(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	uid := claimsOf(r).Sub
	for _, o := range s.st.Offers {
		if o.RiderUserID == uid && time.Now().Before(o.ExpiresAt.Time) {
			ok(w, s.offerJSON(o))
			return nil
		}
	}
	ok(w, nil)
	return nil
}

func (s *Server) acceptOffer(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	uid := claimsOf(r).Sub
	o := s.st.Offers[r.PathValue("id")]
	if o == nil || o.RiderUserID != uid || time.Now().After(o.ExpiresAt.Time) {
		return apiErr(409, "offer_expired", "This offer has expired")
	}
	js := s.st.Jobs[o.JobID]
	if js == nil || js.Job.Status != "searching" {
		delete(s.st.Offers, o.ID)
		return apiErr(409, "offer_expired", "This job was taken")
	}
	rd := s.st.Riders[uid]
	if rd.ActiveJobID != "" {
		return apiErr(409, "invalid_status_transition", "Finish your active job first")
	}
	delete(s.st.Offers, o.ID)
	u := s.st.Users[uid]
	v := rd.Profile.Vehicle
	if v == nil {
		v = &Vehicle{}
	}
	js.RiderUserID = uid
	js.EarningsCentavos = o.EarningsCentavos
	js.Job.Rider = &JobRider{
		ID: rd.Profile.ID, Name: riderDisplayName(u.Name), PhotoURL: s.fileURL(rd.Documents["selfie_key"]),
		PhoneMasked: maskPhone(u.Phone), Plate: v.Plate, MakeModel: v.MakeModel, Color: v.Color, Rating: rd.Profile.Rating,
	}
	rd.ActiveJobID = js.Job.ID
	s.setStatus(js, "rider_assigned")
	s.systemMessage(js, js.Job.Rider.Name+" accepted your booking and is on the way.")
	ok(w, s.jobView(js, "rider"))
	return nil
}

// "Jamal Hassan" -> "Jamal H."
func riderDisplayName(full string) string {
	f := strings.Fields(full)
	switch len(f) {
	case 0:
		return "Your rider"
	case 1:
		return f[0]
	default:
		return f[0] + " " + string([]rune(f[len(f)-1])[0]) + "."
	}
}

func (s *Server) declineOffer(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	o := s.st.Offers[r.PathValue("id")]
	if o != nil && o.RiderUserID == claimsOf(r).Sub {
		delete(s.st.Offers, o.ID)
		if js := s.st.Jobs[o.JobID]; js != nil {
			js.DeclinedBy = append(js.DeclinedBy, o.RiderUserID)
			s.dispatch(js)
		}
	}
	okEmpty(w)
	return nil
}

func (s *Server) riderActiveJob(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	if js := s.st.Jobs[rd.ActiveJobID]; js != nil && isLive(js.Job.Status) {
		ok(w, s.jobView(js, "rider"))
		return nil
	}
	ok(w, nil)
	return nil
}

func (s *Server) riderJobs(w http.ResponseWriter, r *http.Request) error {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	uid := claimsOf(r).Sub
	s.lock()
	defer s.unlock()
	var out []Job
	for i := len(s.st.JobIDs) - 1; i >= 0; i-- {
		js := s.st.Jobs[s.st.JobIDs[i]]
		if js == nil || js.RiderUserID != uid {
			continue
		}
		d := manilaDate(js.Job.CreatedAt.Time)
		if (from != "" && d < from) || (to != "" && d > to) {
			continue
		}
		out = append(out, s.jobView(js, "rider"))
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (s *Server) riderJobStatus(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Status            string  `json:"status"`
		Location          *LatLng `json:"location"`
		ProofKey          *string `json:"proof_key"`
		ReceiptKey        *string `json:"receipt_key"`
		ItemTotalCentavos *int    `json:"item_total_centavos"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	uid := claimsOf(r).Sub
	js := s.st.Jobs[r.PathValue("id")]
	if js == nil || js.RiderUserID != uid {
		return errNotFound
	}
	if !contains(riderNextStatuses(&js.Job), b.Status) {
		return apiErr(409, "invalid_status_transition", "That step is not possible right now")
	}
	if b.Location != nil {
		s.updateRiderLocation(uid, *b.Location, nil)
	}
	j := &js.Job
	switch b.Status {
	case "items_purchased":
		if b.ReceiptKey == nil || b.ItemTotalCentavos == nil || *b.ItemTotalCentavos <= 0 {
			return fieldErr("receipt_key", "required", "Receipt photo and item total required")
		}
		j.Pabili.ReceiptURL = s.fileURL(*b.ReceiptKey)
		j.Pabili.ItemTotalCentavos = b.ItemTotalCentavos
		j.Fare.Breakdown = append(j.Fare.Breakdown, FareLine{"Items (receipt)", *b.ItemTotalCentavos})
		j.Fare.TotalCentavos += *b.ItemTotalCentavos
	case "completed":
		if j.Service != "ride" && b.ProofKey == nil {
			return fieldErr("proof_key", "required", "Proof-of-delivery photo required")
		}
		if b.ProofKey != nil {
			j.ProofURL = s.fileURL(*b.ProofKey)
		}
		if j.Payment.Method == "cash" {
			j.Payment.Status = "paid"
		}
		s.settle(js)
	}
	s.setStatus(js, b.Status)
	if b.Status == "completed" {
		if rd := s.st.Riders[uid]; rd != nil {
			rd.ActiveJobID = ""
		}
		js.CompletedAt = time.Now()
	}
	ok(w, s.jobView(js, "rider"))
	return nil
}

// settle moves money in the rider's commission wallet when a job completes.
//   - cash: the rider holds the cash, so Go's cut (rider commission + the
//     merchant commission on food) is deducted from the wallet.
//   - online: Go holds the money, so the rider is credited their earnings
//     (+ reimbursed Pabili items they bought with their own cash).
func (s *Server) settle(js *JobState) {
	uid := js.RiderUserID
	jid := js.Job.ID
	if js.Job.Payment.Method == "cash" {
		cut := js.CommissionCentavos
		note := "Commission " + js.Job.Code
		if js.Order != nil {
			cut += js.Order.Commission
			note += " (incl. merchant fee)"
		}
		s.addTx(uid, "commission", -cut, jid, note)
	} else {
		credit := js.EarningsCentavos
		if js.Job.Pabili != nil && js.Job.Pabili.ItemTotalCentavos != nil {
			credit += *js.Job.Pabili.ItemTotalCentavos
		}
		s.addTx(uid, "earning", credit, jid, "Earnings "+js.Job.Code)
	}
	if rd := s.st.Riders[uid]; rd != nil {
		s.emit(uid, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
	}
}

func (s *Server) addTx(uid, typ string, amount int, jobID, note string) {
	rd := s.st.Riders[uid]
	if rd == nil {
		return
	}
	rd.Profile.BalanceCentavos += amount
	tx := &WalletTransaction{ID: newID(), UserID: uid, Type: typ, AmountCentavos: amount, BalanceAfterCentavos: rd.Profile.BalanceCentavos, CreatedAt: Now(), Note: strp(note)}
	if jobID != "" {
		tx.JobID = strp(jobID)
	}
	s.st.Txs = append(s.st.Txs, tx)
	s.touch()
}

func (s *Server) riderEarnings(w http.ResponseWriter, r *http.Request) error {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	if from == "" || to == "" || from > to {
		return fieldErr("from", "invalid", "from/to required")
	}
	uid := claimsOf(r).Sub
	s.lock()
	defer s.unlock()
	byDay := map[string][2]int{}
	for _, js := range s.st.Jobs {
		if js.RiderUserID != uid || js.Job.Status != "completed" {
			continue
		}
		d := manilaDate(js.CompletedAt)
		v := byDay[d]
		byDay[d] = [2]int{v[0] + js.EarningsCentavos, v[1] + 1}
	}
	days := []map[string]any{}
	total, count := 0, 0
	for _, d := range dateRange(from, to) {
		v := byDay[d]
		total += v[0]
		count += v[1]
		days = append(days, map[string]any{"date": d, "total_centavos": v[0], "jobs_count": v[1]})
	}
	ok(w, map[string]any{"total_centavos": total, "jobs_count": count, "days": days})
	return nil
}

func dateRange(from, to string) []string {
	a, e1 := time.Parse("2006-01-02", from)
	b, e2 := time.Parse("2006-01-02", to)
	if e1 != nil || e2 != nil || b.Sub(a) > 400*24*time.Hour {
		return nil
	}
	today := manilaDate(time.Now())
	var out []string
	for d := a; !d.After(b); d = d.AddDate(0, 0, 1) {
		ds := d.Format("2006-01-02")
		if ds > today {
			break
		}
		out = append(out, ds)
	}
	return out
}

func (s *Server) riderWallet(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	rd, err := s.rider(r)
	if err != nil {
		return err
	}
	ok(w, map[string]int{"balance_centavos": rd.Profile.BalanceCentavos, "min_balance_centavos": rd.Profile.MinBalanceCentavos})
	return nil
}

func (s *Server) riderTransactions(w http.ResponseWriter, r *http.Request) error {
	uid := claimsOf(r).Sub
	s.lock()
	defer s.unlock()
	var out []*WalletTransaction
	for i := len(s.st.Txs) - 1; i >= 0; i-- {
		if s.st.Txs[i].UserID == uid {
			out = append(out, s.st.Txs[i])
		}
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

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
	s.lock()
	defer s.unlock()
	idem := r.Header.Get("Idempotency-Key")
	var t *Topup
	if id, seen := s.st.Idempotency[uid+":"+idem]; idem != "" && seen {
		t = s.st.Topups[id]
	}
	if t == nil {
		t = &Topup{ID: newID(), UserID: uid, AmountCentavos: b.AmountCentavos, Method: b.Method, Status: "pending"}
		s.st.Topups[t.ID] = t
		if idem != "" {
			s.st.Idempotency[uid+":"+idem] = t.ID
		}
		s.touch()
	}
	ok(w, map[string]string{"topup_id": t.ID, "checkout_url": strings.TrimRight(s.cfg.PublicURL, "/") + "/pay/topup/" + t.ID})
	return nil
}

// ---------- dispatch ----------

const offerTTL = 15 * time.Second
const searchTimeout = 5 * time.Minute

// dispatch offers a searching job to the nearest eligible rider.
func (s *Server) dispatch(js *JobState) {
	if js.Job.Status != "searching" {
		return
	}
	for _, o := range s.st.Offers {
		if o.JobID == js.Job.ID {
			return // already offered, waiting
		}
	}
	type cand struct {
		r *Rider
		d int
	}
	busy := map[string]bool{}
	for _, o := range s.st.Offers {
		busy[o.RiderUserID] = true
	}
	var cs []cand
	for _, rd := range s.st.Riders {
		p := rd.Profile
		if p.Status != "approved" || !p.IsOnline || rd.ActiveJobID != "" || busy[p.UserID] || rd.Location == nil ||
			p.BalanceCentavos < p.MinBalanceCentavos || time.Since(rd.LocationAt) > 15*time.Minute ||
			contains(js.DeclinedBy, p.UserID) || p.UserID == js.CustomerID {
			continue
		}
		d := distanceM(*rd.Location, js.Job.Pickup.Location)
		if s.cfg.MaxDispatchM == 0 || d <= s.cfg.MaxDispatchM {
			cs = append(cs, cand{rd, d})
		}
	}
	if len(cs) == 0 {
		return
	}
	sort.Slice(cs, func(i, j int) bool { return cs[i].d < cs[j].d })
	c := cs[0]
	earn := js.FeesCentavos * 80 / 100
	if js.Job.Pabili != nil {
		earn = int(math.Max(float64(earn), 4000))
	}
	o := &JobOffer{ID: newID(), JobID: js.Job.ID, RiderUserID: c.r.Profile.UserID, EarningsCentavos: earn, PickupDistanceM: c.d, ExpiresAt: *at(time.Now().Add(offerTTL))}
	s.st.Offers[o.ID] = o
	log.Printf("offer %s for %s -> rider %s (%dm)", o.ID[:8], js.Job.Code, s.userName(c.r.Profile.UserID), c.d)
	s.emit(o.RiderUserID, "rider", "offer.new", map[string]any{"offer": s.offerJSON(o)})
}

// Tick runs every second: expiries, timeouts, re-dispatch, auto-approval.
func (s *Server) Tick() {
	s.lock()
	defer s.unlock()
	now := time.Now()
	for id, o := range s.st.Offers {
		if now.After(o.ExpiresAt.Time) {
			delete(s.st.Offers, id)
			s.emit(o.RiderUserID, "rider", "offer.expired", map[string]any{"offer_id": id})
			if js := s.st.Jobs[o.JobID]; js != nil {
				js.DeclinedBy = append(js.DeclinedBy, o.RiderUserID)
			}
		}
	}
	for _, js := range s.st.Jobs {
		switch js.Job.Status {
		case "searching":
			if now.Sub(js.SearchingSince) > searchTimeout {
				s.cancel(js, "system", "No rider was available nearby. Please try again.")
				continue
			}
			// Give riders who declined/missed a second chance every 45 s.
			if len(js.DeclinedBy) > 0 && int(now.Sub(js.SearchingSince).Seconds())%45 == 0 {
				js.DeclinedBy = nil
			}
			s.dispatch(js)
		case "merchant_pending":
			if !js.MerchantDeadline.IsZero() && now.After(js.MerchantDeadline) {
				s.cancel(js, "system", "The store did not accept the order in time.")
			}
		case "pending_payment":
			if now.Sub(js.Job.CreatedAt.Time) > 30*time.Minute {
				s.cancel(js, "system", "Payment was not completed.")
			}
		}
	}
	if s.cfg.AutoApproveSeconds > 0 {
		for _, rd := range s.st.Riders {
			if rd.Profile.Status == "pending_review" && now.Sub(rd.SubmittedAt) > time.Duration(s.cfg.AutoApproveSeconds)*time.Second {
				s.setRiderReview(rd, true, "")
			}
		}
	}
}

func (s *Server) setRiderReview(rd *Rider, approve bool, reason string) {
	if approve {
		rd.Profile.Status = "approved"
		rd.Profile.RejectionReason = nil
	} else {
		rd.Profile.Status = "rejected"
		rd.Profile.RejectionReason = strp(reason)
	}
	s.touch()
	log.Printf("rider %s %s", s.userName(rd.Profile.UserID), rd.Profile.Status)
	s.emit(rd.Profile.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
}
