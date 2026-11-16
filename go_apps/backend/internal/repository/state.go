package repository

import (
	"goapp/backend/internal/domain"
)

// State is the central in-memory store representation.
type State struct {
	Users       map[string]*domain.User          `json:"users"`
	UserByPhone map[string]string                `json:"user_by_phone"`
	Places      map[string]*domain.SavedPlace    `json:"places"`
	Merchants   map[string]*domain.MerchantRow   `json:"merchants"`
	MerchantIDs []string                         `json:"merchant_ids"`
	Staff       map[string]domain.MerchantStaff  `json:"staff"` // by phone
	Quotes      map[string]*domain.Quote         `json:"-"`
	QuoteReqs   map[string]*domain.QuoteRequest  `json:"-"`
	Jobs        map[string]*domain.JobState      `json:"jobs"`
	JobIDs      []string                         `json:"job_ids"` // creation order
	Riders      map[string]*domain.Rider         `json:"riders"`  // by user id
	Offers      map[string]*domain.JobOffer      `json:"-"`
	Txs         []*domain.WalletTransaction      `json:"txs"`
	Chats       map[string][]*domain.ChatMessage `json:"chats"`
	Payouts     []*domain.Payout                 `json:"payouts"`
	Topups      map[string]*domain.Topup         `json:"topups"`
	Devices     map[string]domain.Device         `json:"devices"`
	Refresh     map[string]domain.RefreshToken   `json:"refresh"`
	Idempotency map[string]string                `json:"idempotency"`
	Ratings     []domain.Rating                  `json:"ratings"`
	SOS         []domain.SOSAlert                `json:"sos"`
	CodeSeq     int                              `json:"code_seq"`
	Uploads     map[string]string                `json:"uploads"` // key -> purpose
	Shares      map[string]string                `json:"shares"`  // token -> job id
	OTPs        map[string]*domain.OTP           `json:"-"`
	GeoPlaces   []domain.GeoPlace                `json:"-"`
	ServiceArea domain.ServiceArea               `json:"-"`
}

func NewState() *State {
	return &State{
		Users:       map[string]*domain.User{},
		UserByPhone: map[string]string{},
		Places:      map[string]*domain.SavedPlace{},
		Merchants:   map[string]*domain.MerchantRow{},
		Staff:       map[string]domain.MerchantStaff{},
		Quotes:      map[string]*domain.Quote{},
		QuoteReqs:   map[string]*domain.QuoteRequest{},
		Jobs:        map[string]*domain.JobState{},
		Riders:      map[string]*domain.Rider{},
		Offers:      map[string]*domain.JobOffer{},
		Chats:       map[string][]*domain.ChatMessage{},
		Topups:      map[string]*domain.Topup{},
		Devices:     map[string]domain.Device{},
		Refresh:     map[string]domain.RefreshToken{},
		Idempotency: map[string]string{},
		OTPs:        map[string]*domain.OTP{},
		Uploads:     map[string]string{},
		Shares:      map[string]string{},
		CodeSeq:     4900,
	}
}
