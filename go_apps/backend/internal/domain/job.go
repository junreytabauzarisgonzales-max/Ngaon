package domain

import "time"

type FareLine struct {
	Label          string `json:"label"`
	AmountCentavos int    `json:"amount_centavos"`
}

type Fare struct {
	Breakdown     []FareLine `json:"breakdown"`
	TotalCentavos int        `json:"total_centavos"`
}

type PabiliItem struct {
	Name     string  `json:"name"`
	Quantity int     `json:"quantity"`
	Note     *string `json:"note,omitempty"`
}

type OrderLine struct {
	Name              string   `json:"name"`
	Quantity          int      `json:"quantity"`
	Addons            []string `json:"addons"`
	Note              *string  `json:"note,omitempty"`
	LineTotalCentavos int      `json:"line_total_centavos"`
}

type JobRider struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	PhotoURL    *string  `json:"photo_url,omitempty"`
	PhoneMasked string   `json:"phone_masked"`
	Plate       string   `json:"plate"`
	MakeModel   string   `json:"make_model"`
	Color       string   `json:"color"`
	Rating      *float64 `json:"rating,omitempty"`
	Location    *LatLng  `json:"location,omitempty"`
}

type JobMerchant struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	PhoneMasked string `json:"phone_masked"`
}

type JobFood struct {
	Items                     []OrderLine `json:"items"`
	SubtotalCentavos          int         `json:"subtotal_centavos"`
	PrepTimeMinutes           *int        `json:"prep_time_minutes,omitempty"`
	ReadyAt                   *UTC        `json:"ready_at,omitempty"`
	IsReady                   bool        `json:"is_ready"`
	RiderPaysMerchantCentavos *int        `json:"rider_pays_merchant_centavos,omitempty"`
}

type JobPabili struct {
	StoreName         string       `json:"store_name"`
	Items             []PabiliItem `json:"items"`
	ReceiptURL        *string      `json:"receipt_url,omitempty"`
	ItemTotalCentavos *int         `json:"item_total_centavos,omitempty"`
}

type JobPadala struct {
	Size           string  `json:"size"`
	Description    string  `json:"description"`
	RecipientName  string  `json:"recipient_name"`
	RecipientPhone string  `json:"recipient_phone"`
	PhotoURL       *string `json:"photo_url,omitempty"`
}

type JobRide struct {
	Tier             string `json:"tier"`                         // "solo", "pasabay_tricycle", "pasabay_4w"
	VehicleType      string `json:"vehicle_type"`                 // "motorcycle", "tricycle", "4wheels"
	SeatsBooked      int    `json:"seats_booked"`                 // number of seats booked by this customer (default: 1)
	TotalSharedSeats int    `json:"total_shared_seats,omitempty"` // total seats booked across active shared passengers
	BaseFareCentavos int    `json:"base_fare_centavos"`           // unshared vehicle trip fare
}

type JobPayment struct {
	Method      string  `json:"method"`
	Status      string  `json:"status"`
	CheckoutURL *string `json:"checkout_url,omitempty"`
}

type TimelineEntry struct {
	Status string `json:"status"`
	At     UTC    `json:"at"`
}

type Job struct {
	ID             string          `json:"id"`
	Code           string          `json:"code"`
	Service        string          `json:"service"`
	Status         string          `json:"status"`
	CreatedAt      UTC             `json:"created_at"`
	UpdatedAt      UTC             `json:"updated_at"`
	Pickup         Stop            `json:"pickup"`
	Dropoff        Stop            `json:"dropoff"`
	Rider          *JobRider       `json:"rider,omitempty"`
	Merchant       *JobMerchant    `json:"merchant,omitempty"`
	Food           *JobFood        `json:"food,omitempty"`
	Pabili         *JobPabili      `json:"pabili,omitempty"`
	Padala         *JobPadala      `json:"padala,omitempty"`
	Ride           *JobRide        `json:"ride,omitempty"`
	Fare           Fare            `json:"fare"`
	Payment        JobPayment      `json:"payment"`
	ProofURL       *string         `json:"proof_url,omitempty"`
	CancelReason   *string         `json:"cancel_reason,omitempty"`
	CancelledBy    *string         `json:"cancelled_by,omitempty"`
	AllowedActions []string        `json:"allowed_actions"`
	Timeline       []TimelineEntry `json:"timeline"`
	RoutePolyline  *string         `json:"route_polyline,omitempty"` // ADDED: pickup -> drop-off route
}

type JobState struct {
	Job                Job                 `json:"job"`
	CustomerID         string              `json:"customer_id"`
	RiderUserID        string              `json:"rider_user_id,omitempty"`
	MerchantID         string              `json:"merchant_id,omitempty"`
	FeesCentavos       int                 `json:"fees_centavos"`
	Rated              bool                `json:"rated"`
	SearchingSince     time.Time           `json:"searching_since"`
	MerchantDeadline   time.Time           `json:"merchant_deadline"`
	DeclinedBy         []string            `json:"declined_by"`
	EarningsCentavos   int                 `json:"earnings_centavos"`
	CommissionCentavos int                 `json:"commission_centavos"`
	CompletedAt        time.Time           `json:"completed_at"`
	ShareToken         string              `json:"share_token,omitempty"`
	PMCheckoutID       string              `json:"pm_checkout_id,omitempty"`
	PMPaymentID        string              `json:"pm_payment_id,omitempty"`
	PayCheckedAt       time.Time           `json:"-"`
	Order              *MerchantOrderState `json:"order,omitempty"`
}

type MerchantOrderRider struct {
	Name        string  `json:"name"`
	PhotoURL    *string `json:"photo_url,omitempty"`
	Plate       string  `json:"plate"`
	PhoneMasked string  `json:"phone_masked"`
}

type MerchantOrder struct {
	ID                        string              `json:"id"`
	JobID                     string              `json:"job_id"`
	Code                      string              `json:"code"`
	Status                    string              `json:"status"`
	CreatedAt                 UTC                 `json:"created_at"`
	MerchantAcceptDeadline    *UTC                `json:"merchant_accept_deadline,omitempty"`
	PrepTimeMinutes           *int                `json:"prep_time_minutes,omitempty"`
	ReadyAt                   *UTC                `json:"ready_at,omitempty"`
	Items                     []OrderLine         `json:"items"`
	SubtotalCentavos          int                 `json:"subtotal_centavos"`
	CommissionCentavos        int                 `json:"commission_centavos"`
	NetCentavos               int                 `json:"net_centavos"`
	PaymentMethod             string              `json:"payment_method"`
	RiderPaysAtPickupCentavos *int                `json:"rider_pays_at_pickup_centavos,omitempty"`
	Rider                     *MerchantOrderRider `json:"rider,omitempty"`
	CustomerFirstName         string              `json:"customer_first_name"`
	Notes                     *string             `json:"notes,omitempty"`
	RejectReason              *string             `json:"reject_reason,omitempty"`
	AllowedActions            []string            `json:"allowed_actions"`
}

type MerchantOrderState struct {
	ID           string  `json:"id"`
	Status       string  `json:"status"`
	RejectReason *string `json:"reject_reason,omitempty"`
	Commission   int     `json:"commission"`
}

type QuoteRequest struct {
	Service string `json:"service"`
	Pickup  Stop   `json:"pickup"`
	Dropoff Stop   `json:"dropoff"`
	Food    *struct {
		MerchantID string `json:"merchant_id"`
		Items      []struct {
			ItemID         string   `json:"item_id"`
			Quantity       int      `json:"quantity"`
			AddonOptionIDs []string `json:"addon_option_ids"`
			Note           *string  `json:"note,omitempty"`
		} `json:"items"`
	} `json:"food,omitempty"`
	Pabili *struct {
		StoreName                  string       `json:"store_name"`
		Items                      []PabiliItem `json:"items"`
		EstimatedItemTotalCentavos int          `json:"estimated_item_total_centavos"`
	} `json:"pabili,omitempty"`
	Padala *struct {
		Size           string  `json:"size"`
		Description    string  `json:"description"`
		RecipientName  string  `json:"recipient_name"`
		RecipientPhone string  `json:"recipient_phone"`
		PhotoKey       *string `json:"photo_key,omitempty"`
	} `json:"padala,omitempty"`
	Ride *struct {
		Tier        string `json:"tier,omitempty"`         // "solo", "pasabay_tricycle", "pasabay_4w" (default "solo")
		SeatsBooked int    `json:"seats_booked,omitempty"` // 1..4 (default 1)
	} `json:"ride,omitempty"`
}

type RideTierQuote struct {
	Tier            string     `json:"tier"`              // "solo", "pasabay_tricycle", "pasabay_4w"
	Name            string     `json:"name"`              // "Solo (Motorcycle)", "Pasabay (Tricycle)", "Pasabay (4-Wheels)"
	VehicleType     string     `json:"vehicle_type"`      // "motorcycle", "tricycle", "4wheels"
	MaxCapacity     int        `json:"max_capacity"`      // 1, 4, 4
	SeatsBooked     int        `json:"seats_booked"`      // 1..4
	TotalCentavos   int        `json:"total_centavos"`    // current trip fare for this passenger
	MinFareCentavos int        `json:"min_fare_centavos"` // fare when shared at max capacity
	Breakdown       []FareLine `json:"breakdown"`
}

type Quote struct {
	ID                    string          `json:"id"`
	Service               string          `json:"service"`
	DistanceM             int             `json:"distance_m"`
	DurationS             int             `json:"duration_s"`
	ExpiresAt             UTC             `json:"expires_at"`
	Breakdown             []FareLine      `json:"breakdown"`
	TotalCentavos         int             `json:"total_centavos"`
	MaxItemBudgetCentavos *int            `json:"max_item_budget_centavos,omitempty"`
	RoutePolyline         *string         `json:"route_polyline,omitempty"`
	RideTiers             []RideTierQuote `json:"ride_tiers,omitempty"`

	// internal
	UserID       string        `json:"-"`
	Request      *QuoteRequest `json:"-"`
	FeesCentavos int           `json:"-"`
}
