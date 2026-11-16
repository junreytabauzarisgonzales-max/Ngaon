package domain

import "time"

type Vehicle struct {
	Plate     string `json:"plate"`
	MakeModel string `json:"make_model"`
	Color     string `json:"color"`
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
}

type Rider struct {
	Profile     RiderProfile      `json:"profile"`
	Documents   map[string]string `json:"documents"`
	Location    *LatLng           `json:"location"`
	LocationAt  time.Time         `json:"location_at"`
	ActiveJobID string            `json:"active_job_id"`
	RatingSum   int               `json:"rating_sum"`
	RatingCount int               `json:"rating_count"`
	SubmittedAt time.Time         `json:"submitted_at"`
}

type JobOffer struct {
	ID               string `json:"id"`
	JobID            string `json:"-"`
	RiderUserID      string `json:"-"`
	EarningsCentavos int    `json:"earnings_centavos"`
	PickupDistanceM  int    `json:"pickup_distance_m"`
	ExpiresAt        UTC    `json:"expires_at"`
}
