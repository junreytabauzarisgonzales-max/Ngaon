package app

import "time"

// JSON models. Field names and optionality follow API_CONTRACT.md §3 exactly.
// Times are serialized by the custom UTC type below (no milliseconds).

// UTC marshals as `2026-11-14T14:05:00Z`.
type UTC struct{ time.Time }

func Now() UTC { return UTC{time.Now().UTC().Truncate(time.Second)} }

func (t UTC) MarshalJSON() ([]byte, error) {
	return []byte(`"` + t.Time.UTC().Format("2006-01-02T15:04:05Z") + `"`), nil
}

func (t *UTC) UnmarshalJSON(b []byte) error {
	if string(b) == "null" {
		return nil
	}
	p, err := time.Parse(`"`+time.RFC3339+`"`, string(b))
	if err != nil {
		return err
	}
	t.Time = p.UTC()
	return nil
}

func at(t time.Time) *UTC { u := UTC{t.UTC().Truncate(time.Second)}; return &u }

type LatLng struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type User struct {
	ID        string   `json:"id"`
	Phone     string   `json:"phone"`
	Name      string   `json:"name"`
	Email     *string  `json:"email,omitempty"`
	Language  string   `json:"language"`
	Roles     []string `json:"roles"`
	CreatedAt UTC      `json:"created_at"`
}

type SavedPlace struct {
	ID       string `json:"id"`
	UserID   string `json:"-"`
	Label    string `json:"label"`
	Address  string `json:"address"`
	Location LatLng `json:"location"`
}

type Stop struct {
	Address      string  `json:"address"`
	Location     LatLng  `json:"location"`
	ContactName  *string `json:"contact_name,omitempty"`
	ContactPhone *string `json:"contact_phone,omitempty"`
	Notes        *string `json:"notes,omitempty"`
}

type OpeningHours struct {
	Weekday int    `json:"weekday"`
	Opens   string `json:"opens"`
	Closes  string `json:"closes"`
}

type AddonOption struct {
	ID            string `json:"id"`
	Name          string `json:"name"`
	PriceCentavos int    `json:"price_centavos"`
	IsAvailable   bool   `json:"is_available"`
}

type AddonGroup struct {
	ID        string        `json:"id"`
	Name      string        `json:"name"`
	MinSelect int           `json:"min_select"`
	MaxSelect int           `json:"max_select"`
	Options   []AddonOption `json:"options"`
}

type MenuItem struct {
	ID            string       `json:"id"`
	CategoryID    string       `json:"category_id"`
	Name          string       `json:"name"`
	Description   *string      `json:"description,omitempty"`
	PhotoURL      *string      `json:"photo_url,omitempty"`
	PriceCentavos int          `json:"price_centavos"`
	IsAvailable   bool         `json:"is_available"`
	AddonGroups   []AddonGroup `json:"addon_groups"`
}

type MenuCategory struct {
	ID        string     `json:"id"`
	Name      string     `json:"name"`
	SortOrder int        `json:"sort_order"`
	Items     []MenuItem `json:"items"`
}

type Merchant struct {
	ID               string         `json:"id"`
	Name             string         `json:"name"`
	LogoURL          *string        `json:"logo_url,omitempty"`
	CoverURL         *string        `json:"cover_url,omitempty"`
	Address          string         `json:"address"`
	Location         LatLng         `json:"location"`
	IsOpen           bool           `json:"is_open"`
	PausedUntil      *UTC           `json:"paused_until,omitempty"`
	Hours            []OpeningHours `json:"hours"`
	PrepTimeMinutes  int            `json:"prep_time_minutes"`
	Rating           *float64       `json:"rating,omitempty"`
	MinOrderCentavos int            `json:"min_order_centavos"`
	DistanceM        *int           `json:"distance_m,omitempty"`
	Menu             []MenuCategory `json:"menu,omitempty"`
}

// MerchantRow is the persisted merchant (public fields + internals).
type MerchantRow struct {
	Merchant    Merchant `json:"merchant"`
	RatingSum   int      `json:"rating_sum"`
	RatingCount int      `json:"rating_count"`
	Phone       string   `json:"phone"`
}

func (m *Merchant) acceptsOrders() bool {
	return m.IsOpen && (m.PausedUntil == nil || m.PausedUntil.Before(time.Now()))
}

type FareLine struct {
	Label          string `json:"label"`
	AmountCentavos int    `json:"amount_centavos"`
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
}

type Quote struct {
	ID                    string     `json:"id"`
	Service               string     `json:"service"`
	DistanceM             int        `json:"distance_m"`
	DurationS             int        `json:"duration_s"`
	ExpiresAt             UTC        `json:"expires_at"`
	Breakdown             []FareLine `json:"breakdown"`
	TotalCentavos         int        `json:"total_centavos"`
	MaxItemBudgetCentavos *int       `json:"max_item_budget_centavos,omitempty"`
	RoutePolyline         *string    `json:"route_polyline,omitempty"` // ADDED: Google encoded polyline

	// internal
	UserID  string        `json:"-"`
	Request *QuoteRequest `json:"-"`
	// fees only (what the rider earns from); excludes food subtotal
	FeesCentavos int `json:"-"`
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

type Fare struct {
	Breakdown     []FareLine `json:"breakdown"`
	TotalCentavos int        `json:"total_centavos"`
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

// Job is the stored job. AllowedActions is computed per viewer (see view.go).
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
	Fare           Fare            `json:"fare"`
	Payment        JobPayment      `json:"payment"`
	ProofURL       *string         `json:"proof_url,omitempty"`
	CancelReason   *string         `json:"cancel_reason,omitempty"`
	CancelledBy    *string         `json:"cancelled_by,omitempty"`
	AllowedActions []string        `json:"allowed_actions"`
	Timeline       []TimelineEntry `json:"timeline"`
	RoutePolyline  *string         `json:"route_polyline,omitempty"` // ADDED: pickup -> drop-off route
}

// JobState wraps a job with internal bookkeeping (persisted, never sent).
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
	// ADDED: identity verification (Didit); present when KYC is enabled.
	KycStatus *string `json:"kyc_status,omitempty"` // not_started|in_progress|in_review|approved|declined|expired
}

// Rider is the persisted rider (public profile + internals).
type Rider struct {
	Profile      RiderProfile      `json:"profile"`
	Documents    map[string]string `json:"documents"`
	Location     *LatLng           `json:"location"`
	LocationAt   time.Time         `json:"location_at"`
	ActiveJobID  string            `json:"active_job_id"`
	RatingSum    int               `json:"rating_sum"`
	RatingCount  int               `json:"rating_count"`
	SubmittedAt  time.Time         `json:"submitted_at"`
	KycSessionID string            `json:"kyc_session_id,omitempty"`
	KycURL       string            `json:"kyc_url,omitempty"`
	KycCheckedAt time.Time         `json:"-"`
}

type JobOffer struct {
	ID               string `json:"id"`
	JobID            string `json:"-"`
	RiderUserID      string `json:"-"`
	EarningsCentavos int    `json:"earnings_centavos"`
	PickupDistanceM  int    `json:"pickup_distance_m"`
	ExpiresAt        UTC    `json:"expires_at"`
}

type WalletTransaction struct {
	ID                   string  `json:"id"`
	UserID               string  `json:"-"`
	Type                 string  `json:"type"`
	AmountCentavos       int     `json:"amount_centavos"`
	BalanceAfterCentavos int     `json:"balance_after_centavos"`
	JobID                *string `json:"job_id,omitempty"`
	Note                 *string `json:"note,omitempty"`
	CreatedAt            UTC     `json:"created_at"`
}

type ChatMessage struct {
	ID        string  `json:"id"`
	JobID     string  `json:"job_id"`
	Sender    string  `json:"sender"`
	Text      *string `json:"text,omitempty"`
	ImageURL  *string `json:"image_url,omitempty"`
	CreatedAt UTC     `json:"created_at"`
}

type Payout struct {
	ID             string `json:"id"`
	MerchantID     string `json:"-"`
	PeriodFrom     string `json:"period_from"`
	PeriodTo       string `json:"period_to"`
	AmountCentavos int    `json:"amount_centavos"`
	Type           string `json:"type"`
	Status         string `json:"status"`
	PaidAt         *UTC   `json:"paid_at,omitempty"`
}

type MerchantStaff struct {
	UserPhone  string `json:"user_phone"`
	MerchantID string `json:"merchant_id"`
	Role       string `json:"role"`
	StaffName  string `json:"staff_name"`
}

type Topup struct {
	ID             string    `json:"id"`
	UserID         string    `json:"user_id"`
	AmountCentavos int       `json:"amount_centavos"`
	Method         string    `json:"method"`
	Status         string    `json:"status"`
	PMCheckoutID   string    `json:"pm_checkout_id,omitempty"`
	CheckoutURL    string    `json:"checkout_url,omitempty"`
	CheckedAt      time.Time `json:"-"`
}

type Device struct {
	UserID   string `json:"user_id"`
	Token    string `json:"token"`
	Platform string `json:"platform"`
	App      string `json:"app"`
}

type SOSAlert struct {
	JobID    string `json:"job_id"`
	UserID   string `json:"user_id"`
	Location LatLng `json:"location"`
	At       UTC    `json:"at"`
}

type Rating struct {
	JobID          string   `json:"job_id"`
	RiderRating    int      `json:"rider_rating"`
	RiderTags      []string `json:"rider_tags"`
	Comment        *string  `json:"comment,omitempty"`
	MerchantRating *int     `json:"merchant_rating,omitempty"`
}
