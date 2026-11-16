package domain

import "time"

type Vehicle struct {
	Plate     string `json:"plate"`
	MakeModel string `json:"make_model"`
	Color     string `json:"color"`
	Type      string `json:"type,omitempty"`     // "motorcycle", "tricycle", "car" (default: "motorcycle")
	Capacity  int    `json:"capacity,omitempty"` // max passenger capacity (default: 1 for motorcycle, 4 for tricycle, 4 for car)
}

func (v *Vehicle) VehicleType() string {
	if v == nil || v.Type == "" {
		return "motorcycle"
	}
	if v.Type == "4wheels" {
		return "car"
	}
	return v.Type
}

func (v *Vehicle) VehicleCapacity() int {
	if v == nil {
		return 1
	}
	if v.Capacity > 0 {
		return v.Capacity
	}
	switch v.Type {
	case "tricycle":
		return 4
	case "car", "4wheels":
		return 4
	default:
		return 1
	}
}

type RiderProfile struct {
	ID                 string   `json:"id"`
	UserID             string   `json:"user_id"`
	Status             string   `json:"status"`
	RejectionReason    *string  `json:"rejection_reason,omitempty"`
	IsOnline           bool     `json:"is_online"`
	Vehicle            *Vehicle `json:"vehicle,omitempty"`
	Rating             *float64 `json:"rating,omitempty"`
	BalanceCentavos    int      `json:"balance_centavos"`
	MinBalanceCentavos int      `json:"min_balance_centavos"`
	KycStatus          *string  `json:"kyc_status,omitempty"`
}

type Rider struct {
	Profile      RiderProfile      `json:"profile"`
	Documents    map[string]string `json:"documents"`
	Location     *LatLng           `json:"location"`
	LocationAt   time.Time         `json:"location_at"`
	ActiveJobID  string            `json:"active_job_id"`
	ActiveJobIDs []string          `json:"active_job_ids,omitempty"`
	RatingSum    int               `json:"rating_sum"`
	RatingCount  int               `json:"rating_count"`
	SubmittedAt  time.Time         `json:"submitted_at"`
	KycSessionID string            `json:"kyc_session_id,omitempty"`
	KycURL       string            `json:"kyc_url,omitempty"`
	KycCheckedAt time.Time         `json:"-"`
}

func (rd *Rider) VehicleType() string {
	if rd == nil || rd.Profile.Vehicle == nil {
		return "motorcycle"
	}
	return rd.Profile.Vehicle.VehicleType()
}

func (rd *Rider) VehicleCapacity() int {
	if rd == nil || rd.Profile.Vehicle == nil {
		return 1
	}
	return rd.Profile.Vehicle.VehicleCapacity()
}

type JobOffer struct {
	ID               string `json:"id"`
	JobID            string `json:"-"`
	RiderUserID      string `json:"-"`
	EarningsCentavos int    `json:"earnings_centavos"`
	PickupDistanceM  int    `json:"pickup_distance_m"`
	ExpiresAt        UTC    `json:"expires_at"`
}
