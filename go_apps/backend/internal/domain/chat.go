package domain

type ChatMessage struct {
	ID        string  `json:"id"`
	JobID     string  `json:"job_id"`
	Sender    string  `json:"sender"`
	Text      *string `json:"text,omitempty"`
	ImageURL  *string `json:"image_url,omitempty"`
	CreatedAt UTC     `json:"created_at"`
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
