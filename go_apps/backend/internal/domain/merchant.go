package domain

import "time"

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

func (m *Merchant) AcceptsOrders() bool {
	return m.IsOpen && (m.PausedUntil == nil || m.PausedUntil.Before(time.Now()))
}

type MerchantRow struct {
	Merchant    Merchant `json:"merchant"`
	RatingSum   int      `json:"rating_sum"`
	RatingCount int      `json:"rating_count"`
	Phone       string   `json:"phone"`
}

type MerchantStaff struct {
	UserPhone  string `json:"user_phone"`
	MerchantID string `json:"merchant_id"`
	Role       string `json:"role"`
	StaffName  string `json:"staff_name"`
}
