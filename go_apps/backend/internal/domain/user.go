package domain

import "time"

type User struct {
	ID         string   `json:"id"`
	Phone      string   `json:"phone"`
	Name       string   `json:"name"`
	Email      *string  `json:"email,omitempty"`
	Language   string   `json:"language"`
	Roles      []string `json:"roles"`
	GoogleID   *string  `json:"google_id,omitempty"`
	FacebookID *string  `json:"facebook_id,omitempty"`
	AvatarURL  *string  `json:"avatar_url,omitempty"`
	CreatedAt  UTC      `json:"created_at"`
}

type SavedPlace struct {
	ID       string `json:"id"`
	UserID   string `json:"-"`
	Label    string `json:"label"`
	Address  string `json:"address"`
	Location LatLng `json:"location"`
}

type RefreshToken struct {
	UserID  string    `json:"user_id"`
	App     string    `json:"app"`
	Expires time.Time `json:"expires"`
}

type OTP struct {
	Code     string
	Expires  time.Time
	Attempts int
	Sent     []time.Time
}

type Device struct {
	UserID   string `json:"user_id"`
	Token    string `json:"token"`
	Platform string `json:"platform"`
	App      string `json:"app"`
}
