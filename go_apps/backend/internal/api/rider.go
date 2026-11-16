package api

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"goapp/backend/internal/domain"
	"goapp/backend/internal/integrations"
	"goapp/backend/internal/service"
)

func (a *API) rider(r *http.Request) (*domain.Rider, error) {
	uid := claimsOf(r).Sub
	rd := a.svc.St.Riders[uid]
	if rd == nil {
		if claimsOf(r).App != "rider" {
			return nil, errForbidden
		}
		rd = &domain.Rider{Profile: domain.RiderProfile{
			ID:                 domain.NewID(),
			UserID:             uid,
			Status:             "incomplete",
			BalanceCentavos:    a.svc.Cfg.RiderStartBalance,
			MinBalanceCentavos: 10000,
		}}
		a.svc.St.Riders[uid] = rd
		a.svc.Touch()
	}
	return rd, nil
}

func (a *API) kycStatus(rd *domain.Rider) *string {
	if a.svc.Didit == nil || !a.svc.Didit.Enabled() {
		return nil
	}
	if rd.Profile.KycStatus != nil {
		return rd.Profile.KycStatus
	}
	st := "not_started"
	if rd.KycSessionID != "" {
		st = "in_progress"
	}
	return &st
}

func (a *API) riderMe(w http.ResponseWriter, r *http.Request) error {
	uid := claimsOf(r).Sub
	if a.svc.Didit != nil && a.svc.Didit.Enabled() {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		a.syncKyc(ctx, uid)
		cancel()
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	rd, err := a.rider(r)
	if err != nil {
		return err
	}
	prof := rd.Profile
	prof.KycStatus = a.kycStatus(rd)
	ok(w, prof)
	return nil
}

func (a *API) riderKycSession(w http.ResponseWriter, r *http.Request) error {
	if a.svc.Didit == nil || !a.svc.Didit.Enabled() {
		return apiErr(400, "kyc_not_configured", "Identity verification is not enabled on this server")
	}
	uid := claimsOf(r).Sub
	a.svc.Lock()
	rd, err := a.rider(r)
	if err != nil {
		a.svc.Unlock()
		return err
	}
	if rd.Profile.Status == "approved" {
		a.svc.Unlock()
		return apiErr(409, "already_approved", "Your account is already approved")
	}
	u := a.svc.St.Users[uid]
	phone := ""
	if u != nil {
		phone = u.Phone
	}
	callback := strings.TrimRight(a.svc.Cfg.PublicURL, "/") + "/kyc/return"
	a.svc.Unlock()

	ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
	sess, err := a.svc.Didit.CreateSession(ctx, uid, callback, phone)
	cancel()
	if err != nil {
		integrations.LogIntegration("didit create session", err)
		return apiErr(502, "didit_error", "Could not start identity verification. Please try again.")
	}

	a.svc.Lock()
	defer a.svc.Unlock()
	rd = a.svc.St.Riders[uid]
	if rd != nil {
		rd.KycSessionID = sess.SessionID
		rd.KycURL = sess.URL
		sStatus := integrations.KycFromDidit(sess.Status)
		if sStatus == "not_started" {
			sStatus = "in_progress"
		}
		rd.Profile.KycStatus = domain.StrPtr(sStatus)
		a.svc.Touch()
		token := sess.SessionToken
		if token == "" && sess.URL != "" {
			parts := strings.Split(strings.TrimRight(sess.URL, "/"), "/")
			if len(parts) > 0 {
				token = parts[len(parts)-1]
			}
		}
		ok(w, map[string]string{
			"session_id":    sess.SessionID,
			"session_token": token,
			"url":           sess.URL,
			"kyc_status":    sStatus,
		})
		return nil
	}
	return errNotFound
}

func (a *API) applyKyc(rd *domain.Rider, diditStatus string) {
	mapped := integrations.KycFromDidit(diditStatus)
	rd.Profile.KycStatus = &mapped
	switch mapped {
	case "approved":
		a.svc.SetRiderReview(rd, true, "")
	case "declined":
		a.svc.SetRiderReview(rd, false, "Identity verification declined by provider")
	}
	a.svc.Touch()
	a.svc.Emit(rd.Profile.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
}

func (a *API) syncKyc(ctx context.Context, uid string) {
	a.svc.Lock()
	rd := a.svc.St.Riders[uid]
	if rd == nil || rd.KycSessionID == "" || a.svc.Didit == nil || !a.svc.Didit.Enabled() || time.Since(rd.KycCheckedAt) < 5*time.Second {
		a.svc.Unlock()
		return
	}
	if rd.Profile.KycStatus != nil && (*rd.Profile.KycStatus == "approved" || *rd.Profile.KycStatus == "declined") {
		a.svc.Unlock()
		return
	}
	rd.KycCheckedAt = time.Now()
	sessID := rd.KycSessionID
	a.svc.Unlock()

	st, err := a.svc.Didit.Decision(ctx, sessID)
	if err != nil {
		integrations.LogIntegration("didit poll", err)
		return
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	if rd := a.svc.St.Riders[uid]; rd != nil {
		a.applyKyc(rd, st)
	}
}

func (a *API) riderSubmit(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Vehicle   domain.Vehicle `json:"vehicle"`
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
	a.svc.Lock()
	defer a.svc.Unlock()
	docs := map[string]string{
		"license_key":   b.Documents.LicenseKey,
		"orcr_key":      b.Documents.OrcrKey,
		"selfie_key":    b.Documents.SelfieKey,
		"clearance_key": b.Documents.ClearanceKey,
	}
	for f, k := range docs {
		if _, uploaded := a.svc.St.Uploads[k]; !uploaded {
			return fieldErr(f, "not_uploaded", "Upload all documents first")
		}
	}
	rd, err := a.rider(r)
	if err != nil {
		return err
	}
	if rd.Profile.Status == "approved" || rd.Profile.Status == "suspended" {
		return apiErr(409, "invalid_status_transition", "Profile already reviewed")
	}
	v := b.Vehicle
	v.Plate = strings.ToUpper(strings.TrimSpace(v.Plate))
	if v.Type == "" {
		v.Type = "motorcycle"
	}
	if v.Capacity <= 0 {
		switch v.Type {
		case "tricycle":
			v.Capacity = 4
		case "4wheels", "car":
			v.Capacity = 4
		default:
			v.Capacity = 1
		}
	}
	rd.Profile.Vehicle = &v
	rd.Documents = docs
	rd.Profile.Status = "pending_review"
	rd.Profile.RejectionReason = nil
	rd.SubmittedAt = time.Now()
	a.svc.Touch()
	log.Printf("rider application from %s (%s) waiting for review", a.svc.UserName(rd.Profile.UserID), v.Plate)
	ok(w, rd.Profile)
	return nil
}

func (a *API) riderStatus(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Online   bool           `json:"online"`
		Location *domain.LatLng `json:"location"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	rd, err := a.rider(r)
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
	if b.Location != nil && (b.Location.Lat < -90 || b.Location.Lat > 90 || b.Location.Lng < -180 || b.Location.Lng > 180) {
		return fieldErr("location", "invalid", "Invalid coordinates")
	}
	rd.Profile.IsOnline = b.Online
	if b.Location != nil {
		rd.Location = b.Location
		rd.LocationAt = time.Now()
		if b.Online && a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			_ = a.svc.Redis.UpdateRiderLocation(ctx, rd.Profile.UserID, *b.Location, nil)
			cancel()
		}
	}
	if !b.Online {
		if a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			_ = a.svc.Redis.RemoveRiderLocation(ctx, rd.Profile.UserID)
			cancel()
		}
		for id, o := range a.svc.St.Offers {
			if o.RiderUserID == rd.Profile.UserID {
				delete(a.svc.St.Offers, id)
				if a.svc.Redis != nil {
					ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
					_ = a.svc.Redis.DeleteOffer(ctx, id, o.RiderUserID)
					cancel()
				}
				if js := a.svc.St.Jobs[o.JobID]; js != nil {
					a.svc.Dispatch(js)
				}
			}
		}
	}
	a.svc.Touch()
	ok(w, rd.Profile)
	return nil
}

func (a *API) riderLocationHTTP(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Location   domain.LatLng `json:"location"`
		Heading    *float64      `json:"heading"`
		SpeedKph   *float64      `json:"speed_kph"`
		RecordedAt *string       `json:"recorded_at"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.Location.Lat < -90 || b.Location.Lat > 90 || b.Location.Lng < -180 || b.Location.Lng > 180 {
		return fieldErr("location", "invalid", "Invalid coordinates")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	a.svc.UpdateRiderLocation(claimsOf(r).Sub, b.Location, b.Heading)
	okEmpty(w)
	return nil
}

func (a *API) currentOffer(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	uid := claimsOf(r).Sub
	for _, o := range a.svc.St.Offers {
		if o.RiderUserID == uid && time.Now().Before(o.ExpiresAt.Time) {
			js := a.svc.St.Jobs[o.JobID]
			if js == nil {
				continue
			}
			ok(w, map[string]any{
				"id":                o.ID,
				"job":               a.svc.JobView(js, "rider"),
				"earnings_centavos": o.EarningsCentavos,
				"pickup_distance_m": o.PickupDistanceM,
				"expires_at":        o.ExpiresAt,
			})
			return nil
		}
	}
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		o, found, err := a.svc.Redis.GetRiderOffer(ctx, uid)
		cancel()
		if err == nil && found && o != nil {
			if js := a.svc.St.Jobs[o.JobID]; js != nil {
				a.svc.St.Offers[o.ID] = o
				ok(w, map[string]any{
					"id":                o.ID,
					"job":               a.svc.JobView(js, "rider"),
					"earnings_centavos": o.EarningsCentavos,
					"pickup_distance_m": o.PickupDistanceM,
					"expires_at":        o.ExpiresAt,
				})
				return nil
			}
		}
	}
	ok(w, nil)
	return nil
}

func (a *API) acceptOffer(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	uid := claimsOf(r).Sub
	offerID := r.PathValue("id")
	o := a.svc.St.Offers[offerID]
	if o == nil && a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		if ro, found, err := a.svc.Redis.GetOffer(ctx, offerID); err == nil && found {
			o = ro
		}
		cancel()
	}
	if o == nil || o.RiderUserID != uid || time.Now().After(o.ExpiresAt.Time) {
		return apiErr(409, "offer_expired", "This offer has expired")
	}
	js := a.svc.St.Jobs[o.JobID]
	if js == nil || js.Job.Status != "searching" {
		delete(a.svc.St.Offers, o.ID)
		if a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			_ = a.svc.Redis.DeleteOffer(ctx, o.ID, uid)
			cancel()
		}
		return apiErr(409, "offer_expired", "This job was taken")
	}
	rd := a.svc.St.Riders[uid]
	if rd == nil {
		return errForbidden
	}
	isPasabay := js.Job.Service == "ride" && js.Job.Ride != nil && js.Job.Ride.Tier != "solo"
	if isPasabay {
		seats := js.Job.Ride.SeatsBooked
		if seats <= 0 {
			seats = 1
		}
		if a.svc.RiderOccupiedSeats(rd)+seats > rd.VehicleCapacity() {
			return apiErr(409, "invalid_status_transition", "Your vehicle is full")
		}
	} else {
		if a.svc.RiderOccupiedSeats(rd) > 0 {
			return apiErr(409, "invalid_status_transition", "Finish your active job first")
		}
	}
	delete(a.svc.St.Offers, o.ID)
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.DeleteOffer(ctx, o.ID, uid)
		cancel()
	}
	u := a.svc.St.Users[uid]
	v := rd.Profile.Vehicle
	if v == nil {
		v = &domain.Vehicle{}
	}
	js.RiderUserID = uid
	js.EarningsCentavos = o.EarningsCentavos
	js.Job.Rider = &domain.JobRider{
		ID:          rd.Profile.ID,
		Name:        riderDisplayName(u.Name),
		PhotoURL:    a.svc.FileURL(rd.Documents["selfie_key"]),
		PhoneMasked: domain.MaskPhone(u.Phone),
		Plate:       v.Plate,
		MakeModel:   v.MakeModel,
		Color:       v.Color,
		Rating:      rd.Profile.Rating,
	}
	rd.ActiveJobID = js.Job.ID
	rd.ActiveJobIDs = append(rd.ActiveJobIDs, js.Job.ID)
	a.svc.SetStatus(js, "rider_assigned")
	if isPasabay {
		a.svc.RecalculateSharedRides(uid)
	}
	a.svc.SystemMessage(js, js.Job.Rider.Name+" accepted your booking and is on the way.")
	ok(w, a.svc.JobView(js, "rider"))
	return nil
}

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

func (a *API) declineOffer(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	offerID := r.PathValue("id")
	o := a.svc.St.Offers[offerID]
	if o == nil && a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		if ro, found, err := a.svc.Redis.GetOffer(ctx, offerID); err == nil && found {
			o = ro
		}
		cancel()
	}
	if o != nil && o.RiderUserID == claimsOf(r).Sub {
		delete(a.svc.St.Offers, o.ID)
		if a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			_ = a.svc.Redis.DeleteOffer(ctx, o.ID, o.RiderUserID)
			cancel()
		}
		if js := a.svc.St.Jobs[o.JobID]; js != nil {
			js.DeclinedBy = append(js.DeclinedBy, o.RiderUserID)
			a.svc.Dispatch(js)
		}
	}
	okEmpty(w)
	return nil
}

func (a *API) riderActiveJob(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	rd, err := a.rider(r)
	if err != nil {
		return err
	}
	if js := a.svc.St.Jobs[rd.ActiveJobID]; js != nil && service.IsLive(js.Job.Status) {
		ok(w, a.svc.JobView(js, "rider"))
		return nil
	}
	ok(w, nil)
	return nil
}

func (a *API) riderJobs(w http.ResponseWriter, r *http.Request) error {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	uid := claimsOf(r).Sub
	a.svc.Lock()
	defer a.svc.Unlock()
	var out []domain.Job
	for i := len(a.svc.St.JobIDs) - 1; i >= 0; i-- {
		js := a.svc.St.Jobs[a.svc.St.JobIDs[i]]
		if js == nil || js.RiderUserID != uid {
			continue
		}
		d := domain.ManilaDate(js.Job.CreatedAt.Time)
		if (from != "" && d < from) || (to != "" && d > to) {
			continue
		}
		out = append(out, a.svc.JobView(js, "rider"))
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (a *API) riderJobStatus(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Status            string         `json:"status"`
		Location          *domain.LatLng `json:"location"`
		ProofKey          *string        `json:"proof_key"`
		ReceiptKey        *string        `json:"receipt_key"`
		ItemTotalCentavos *int           `json:"item_total_centavos"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	uid := claimsOf(r).Sub
	js := a.svc.St.Jobs[r.PathValue("id")]
	if js == nil || js.RiderUserID != uid {
		return errNotFound
	}
	if !contains(service.RiderNextStatuses(&js.Job), b.Status) {
		return apiErr(409, "invalid_status_transition", "That step is not possible right now")
	}
	if b.Location != nil {
		a.svc.UpdateRiderLocation(uid, *b.Location, nil)
	}
	j := &js.Job
	switch b.Status {
	case "items_purchased":
		if b.ReceiptKey == nil || b.ItemTotalCentavos == nil || *b.ItemTotalCentavos <= 0 {
			return fieldErr("receipt_key", "required", "Receipt photo and item total required")
		}
		j.Pabili.ReceiptURL = a.svc.FileURL(*b.ReceiptKey)
		j.Pabili.ItemTotalCentavos = b.ItemTotalCentavos
		j.Fare.Breakdown = append(j.Fare.Breakdown, domain.FareLine{Label: "Items (receipt)", AmountCentavos: *b.ItemTotalCentavos})
		j.Fare.TotalCentavos += *b.ItemTotalCentavos
	case "completed":
		if j.Service != "ride" && b.ProofKey == nil {
			return fieldErr("proof_key", "required", "Proof-of-delivery photo required")
		}
		if b.ProofKey != nil {
			j.ProofURL = a.svc.FileURL(*b.ProofKey)
		}
		if j.Payment.Method == "cash" {
			j.Payment.Status = "paid"
		}
		a.svc.Settle(js)
	}
	a.svc.SetStatus(js, b.Status)
	if b.Status == "completed" {
		if rd := a.svc.St.Riders[uid]; rd != nil {
			var remaining []string
			for _, id := range rd.ActiveJobIDs {
				if id != js.Job.ID {
					remaining = append(remaining, id)
				}
			}
			rd.ActiveJobIDs = remaining
			if len(remaining) > 0 {
				rd.ActiveJobID = remaining[0]
			} else {
				rd.ActiveJobID = ""
			}
		}
		js.CompletedAt = time.Now()
		if js.Job.Service == "ride" && js.Job.Ride != nil && js.Job.Ride.Tier != "solo" {
			a.svc.RecalculateSharedRides(uid)
		}
	}
	ok(w, a.svc.JobView(js, "rider"))
	return nil
}

func (a *API) riderEarnings(w http.ResponseWriter, r *http.Request) error {
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	if from == "" || to == "" || from > to {
		return fieldErr("from", "invalid", "from/to required")
	}
	uid := claimsOf(r).Sub
	a.svc.Lock()
	defer a.svc.Unlock()
	byDay := map[string][2]int{}
	for _, js := range a.svc.St.Jobs {
		if js.RiderUserID != uid || js.Job.Status != "completed" {
			continue
		}
		d := domain.ManilaDate(js.CompletedAt)
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
	today := domain.ManilaDate(time.Now())
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

func (a *API) riderWallet(w http.ResponseWriter, r *http.Request) error {
	uid := claimsOf(r).Sub
	if a.svc.PM != nil && a.svc.PM.Enabled() {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		a.syncTopups(ctx, uid)
		cancel()
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	rd := a.svc.St.Riders[uid]
	if rd == nil {
		return errNotFound
	}
	ok(w, map[string]int{"balance_centavos": rd.Profile.BalanceCentavos, "min_balance_centavos": rd.Profile.MinBalanceCentavos})
	return nil
}

func (a *API) syncTopups(ctx context.Context, uid string) {
	a.svc.Lock()
	var pending []*domain.Topup
	for _, t := range a.svc.St.Topups {
		if t.UserID == uid && t.Status != "paid" && t.PMCheckoutID != "" && time.Since(t.CheckedAt) > 4*time.Second {
			t.CheckedAt = time.Now()
			pending = append(pending, t)
		}
	}
	a.svc.Unlock()
	if len(pending) == 0 || a.svc.PM == nil || !a.svc.PM.Enabled() {
		return
	}
	for _, t := range pending {
		st, err := a.svc.PM.RetrieveCheckout(ctx, t.PMCheckoutID)
		if err != nil {
			integrations.LogIntegration("paymongo retrieve topup", err)
			continue
		}
		if st.Paid {
			a.svc.Lock()
			a.creditTopup(t)
			a.svc.Unlock()
		}
	}
}

func (a *API) topupURL(t *domain.Topup) string {
	if t.CheckoutURL != "" {
		return t.CheckoutURL
	}
	return strings.TrimRight(a.svc.Cfg.PublicURL, "/") + "/pay/topup/" + t.ID
}

func (a *API) creditTopup(t *domain.Topup) {
	if t.Status == "paid" {
		return
	}
	t.Status = "paid"
	a.svc.AddTx(t.UserID, "topup", t.AmountCentavos, "", strings.ToUpper(t.Method[:1])+t.Method[1:]+" top-up")
	if rd := a.svc.St.Riders[t.UserID]; rd != nil {
		a.svc.Emit(t.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
	}
	a.svc.Touch()
}

func (a *API) riderTransactions(w http.ResponseWriter, r *http.Request) error {
	uid := claimsOf(r).Sub
	a.svc.Lock()
	defer a.svc.Unlock()
	var out []*domain.WalletTransaction
	for i := len(a.svc.St.Txs) - 1; i >= 0; i-- {
		if a.svc.St.Txs[i].UserID == uid {
			out = append(out, a.svc.St.Txs[i])
		}
	}
	page, next := paginate(out, r, 20)
	okPage(w, page, next)
	return nil
}

func (a *API) riderTopup(w http.ResponseWriter, r *http.Request) error {
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
	a.svc.Lock()
	defer a.svc.Unlock()
	idem := r.Header.Get("Idempotency-Key")
	var t *domain.Topup
	if idem != "" {
		idemKey := uid + ":" + idem
		id, seen := a.svc.St.Idempotency[idemKey]
		if !seen && a.svc.Redis != nil {
			ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
			if rId, found, err := a.svc.Redis.GetIdempotency(ctx, idemKey); err == nil && found {
				id, seen = rId, true
				a.svc.St.Idempotency[idemKey] = rId
			}
			cancel()
		}
		if seen {
			t = a.svc.St.Topups[id]
		}
	}
	if t == nil {
		t = &domain.Topup{
			ID:             domain.NewID(),
			UserID:         uid,
			AmountCentavos: b.AmountCentavos,
			Method:         b.Method,
			Status:         "pending",
		}
		a.svc.St.Topups[t.ID] = t
		if idem != "" {
			idemKey := uid + ":" + idem
			a.svc.St.Idempotency[idemKey] = t.ID
			if a.svc.Redis != nil {
				ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
				_ = a.svc.Redis.SetIdempotency(ctx, idemKey, t.ID, 24*time.Hour)
				cancel()
			}
		}
		a.svc.Touch()
	}
	if t.PMCheckoutID == "" && a.svc.PM != nil && a.svc.PM.Enabled() {
		a.svc.Unlock()
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		co, err := a.svc.PM.CreateCheckout(ctx, "TOP-"+t.ID[:8], fmt.Sprintf("Ngaon rider top-up ₱%d", t.AmountCentavos/100), t.AmountCentavos, t.Method, strings.TrimRight(a.svc.Cfg.PublicURL, "/")+"/pay/return", strings.TrimRight(a.svc.Cfg.PublicURL, "/")+"/pay/return", map[string]string{"type": "topup", "topup_id": t.ID, "user_id": uid})
		cancel()
		a.svc.Lock()
		if err == nil {
			t.PMCheckoutID = co.ID
			t.CheckoutURL = co.URL
		} else {
			integrations.LogIntegration("paymongo topup "+t.ID, err)
		}
	}
	u := a.topupURL(t)
	ok(w, map[string]string{"topup_id": t.ID, "checkout_url": u})
	return nil
}
