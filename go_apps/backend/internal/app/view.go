package app

import "time"

var finalStatuses = map[string]bool{"completed": true, "cancelled": true}

func isLive(status string) bool { return !finalStatuses[status] }

// customerActions: API_CONTRACT §4 (customer app).
func customerActions(js *JobState) []string {
	j := &js.Job
	live := isLive(j.Status)
	a := []string{}
	switch j.Status {
	case "pending_payment", "merchant_pending", "merchant_preparing", "searching", "rider_assigned":
		a = append(a, "cancel")
	}
	if live && j.Rider != nil {
		a = append(a, "chat", "call")
		if j.Service == "ride" {
			a = append(a, "sos", "share")
		}
	}
	if j.Status == "items_purchased" {
		a = append(a, "confirm_items")
	}
	if j.Status == "completed" && !js.Rated && j.Rider != nil {
		a = append(a, "rate")
	}
	return a
}

// riderNextStatuses: the statuses the rider may set next (ADDED in contract §4).
func riderNextStatuses(j *Job) []string {
	switch j.Status {
	case "rider_assigned":
		return []string{"arrived_pickup"}
	case "arrived_pickup":
		switch j.Service {
		case "pabili":
			return []string{"items_purchased"}
		case "food":
			if j.Food != nil && j.Food.IsReady {
				return []string{"picked_up"}
			}
			return nil
		default:
			return []string{"picked_up"}
		}
	case "picked_up":
		return []string{"arrived_dropoff"}
	case "arrived_dropoff":
		return []string{"completed"}
	}
	return nil
}

func riderActions(js *JobState) []string {
	a := append([]string{}, riderNextStatuses(&js.Job)...)
	if isLive(js.Job.Status) {
		a = append(a, "chat", "call")
	}
	return a
}

// jobView returns a copy of the job with allowed_actions for the given app.
func (s *Server) jobView(js *JobState, app string) Job {
	j := deepCopy(js.Job)
	if app == "rider" {
		j.AllowedActions = riderActions(js)
	} else {
		j.AllowedActions = customerActions(js)
	}
	// Riders see the live rider location only via their own GPS.
	if r := s.st.Riders[js.RiderUserID]; r != nil && j.Rider != nil && r.Location != nil {
		loc := *r.Location
		j.Rider.Location = &loc
	}
	return j
}

// merchantOrderStatus implements the §5 mapping.
func merchantOrderStatus(js *JobState) string {
	j := &js.Job
	if js.Order != nil && js.Order.Status == "rejected" {
		return "rejected"
	}
	switch j.Status {
	case "pending_payment", "merchant_pending":
		return "new"
	case "merchant_preparing", "searching", "rider_assigned", "arrived_pickup", "items_purchased":
		if j.Food != nil && j.Food.IsReady {
			return "ready"
		}
		return "preparing"
	case "picked_up", "arrived_dropoff":
		return "picked_up"
	case "completed":
		return "completed"
	case "cancelled":
		if j.CancelledBy != nil && *j.CancelledBy == "merchant" {
			return "rejected"
		}
		return "cancelled"
	}
	return "new"
}

func (s *Server) orderView(js *JobState) MerchantOrder {
	j := &js.Job
	status := merchantOrderStatus(js)
	sub := 0
	var lines []OrderLine
	var prep *int
	var ready *UTC
	if j.Food != nil {
		sub = j.Food.SubtotalCentavos
		lines = j.Food.Items
		prep = j.Food.PrepTimeMinutes
		ready = j.Food.ReadyAt
	}
	commission := js.Order.Commission
	if status == "rejected" || status == "cancelled" {
		commission = 0
	}
	net := sub - commission
	if status == "rejected" || status == "cancelled" {
		net = 0
	}
	o := MerchantOrder{
		ID:                 js.Order.ID,
		JobID:              j.ID,
		Code:               j.Code,
		Status:             status,
		CreatedAt:          j.CreatedAt,
		PrepTimeMinutes:    prep,
		ReadyAt:            ready,
		Items:              lines,
		SubtotalCentavos:   sub,
		CommissionCentavos: commission,
		NetCentavos:        net,
		PaymentMethod:      j.Payment.Method,
		CustomerFirstName:  firstName(s.userName(js.CustomerID)),
		Notes:              j.Dropoff.Notes,
		RejectReason:       js.Order.RejectReason,
		AllowedActions:     []string{},
	}
	if status == "new" && !js.MerchantDeadline.IsZero() {
		o.MerchantAcceptDeadline = at(js.MerchantDeadline)
	}
	if j.Payment.Method == "cash" && status != "rejected" && status != "cancelled" {
		o.RiderPaysAtPickupCentavos = intp(net)
	}
	if j.Rider != nil {
		o.Rider = &MerchantOrderRider{Name: j.Rider.Name, PhotoURL: j.Rider.PhotoURL, Plate: j.Rider.Plate, PhoneMasked: j.Rider.PhoneMasked}
	}
	switch status {
	case "new":
		if j.Status == "merchant_pending" {
			o.AllowedActions = []string{"accept", "reject"}
		}
	case "preparing":
		o.AllowedActions = []string{"ready"}
	}
	return o
}

func (s *Server) userName(id string) string {
	if u := s.st.Users[id]; u != nil {
		return u.Name
	}
	return ""
}

// publishJob sends job.updated to customer + rider and order.updated to the merchant.
func (s *Server) publishJob(js *JobState) {
	js.Job.UpdatedAt = Now()
	s.touch()
	s.emit(js.CustomerID, "customer", "job.updated", map[string]any{"job": s.jobView(js, "customer")})
	if js.RiderUserID != "" {
		s.emit(js.RiderUserID, "rider", "job.updated", map[string]any{"job": s.jobView(js, "rider")})
	}
	if js.Order != nil && js.MerchantID != "" {
		ov := s.orderView(js)
		for _, uid := range s.merchantUserIDs(js.MerchantID) {
			s.emit(uid, "merchant", "order.updated", map[string]any{"order": ov})
		}
	}
}

func (s *Server) setStatus(js *JobState, status string) {
	js.Job.Status = status
	js.Job.Timeline = append(js.Job.Timeline, TimelineEntry{Status: status, At: Now()})
	if status == "searching" {
		js.SearchingSince = time.Now()
	}
	if js.Order != nil {
		js.Order.Status = merchantOrderStatus(js)
	}
	s.publishJob(js)
}

func (s *Server) merchantUserIDs(merchantID string) []string {
	var ids []string
	for phone, st := range s.st.Staff {
		if st.MerchantID == merchantID {
			if uid, ok := s.st.UserByPhone[phone]; ok {
				ids = append(ids, uid)
			}
		}
	}
	return ids
}
