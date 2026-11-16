package domain

import "time"

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
