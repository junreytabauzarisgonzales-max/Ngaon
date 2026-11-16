package service

import (
	"goapp/backend/internal/domain"
)

var finalStatuses = map[string]bool{"completed": true, "cancelled": true}

// IsLive returns true if the job is active / in-progress.
func IsLive(status string) bool {
	return !finalStatuses[status]
}

// CustomerActions returns allowed customer actions based on current job status.
func CustomerActions(js *domain.JobState) []string {
	j := &js.Job
	live := IsLive(j.Status)
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

// RiderNextStatuses returns the statuses a rider may transition a job to.
func RiderNextStatuses(j *domain.Job) []string {
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

// RiderActions returns all actions allowed for the rider viewer.
func RiderActions(js *domain.JobState) []string {
	a := append([]string{}, RiderNextStatuses(&js.Job)...)
	if IsLive(js.Job.Status) {
		a = append(a, "chat", "call")
	}
	return a
}

// MerchantOrderStatus implements the contract status mapping for merchant orders.
func MerchantOrderStatus(js *domain.JobState) string {
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

// JobView returns a customized copy of the job formatted for a specific app viewer.
func JobView(js *domain.JobState, app string, riderLocation *domain.LatLng) domain.Job {
	j := domain.DeepCopy(js.Job)
	if app == "rider" {
		j.AllowedActions = RiderActions(js)
	} else {
		j.AllowedActions = CustomerActions(js)
	}
	if riderLocation != nil && j.Rider != nil {
		loc := *riderLocation
		j.Rider.Location = &loc
	}
	return j
}

// OrderView generates the MerchantOrder projection for the merchant app.
func OrderView(js *domain.JobState, customerName string) domain.MerchantOrder {
	j := &js.Job
	status := MerchantOrderStatus(js)
	sub := 0
	var lines []domain.OrderLine
	var prep *int
	var ready *domain.UTC
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
	o := domain.MerchantOrder{
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
		CustomerFirstName:  domain.FirstName(customerName),
		Notes:              j.Dropoff.Notes,
		RejectReason:       js.Order.RejectReason,
		AllowedActions:     []string{},
	}
	if status == "new" && !js.MerchantDeadline.IsZero() {
		o.MerchantAcceptDeadline = domain.At(js.MerchantDeadline)
	}
	if j.Payment.Method == "cash" && status != "rejected" && status != "cancelled" {
		o.RiderPaysAtPickupCentavos = domain.IntPtr(net)
	}
	if j.Rider != nil {
		o.Rider = &domain.MerchantOrderRider{
			Name:        j.Rider.Name,
			PhotoURL:    j.Rider.PhotoURL,
			Plate:       j.Rider.Plate,
			PhoneMasked: j.Rider.PhoneMasked,
		}
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
