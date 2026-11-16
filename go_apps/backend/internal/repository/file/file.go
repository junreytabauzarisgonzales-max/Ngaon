package file

import (
	"encoding/json"
	"fmt"
	"os"

	"goapp/backend/internal/domain"
	"goapp/backend/internal/repository"
)

// Load reads and unmarshals the persisted JSON snapshot.
func Load(path string, st *repository.State) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, st); err != nil {
		return fmt.Errorf("unmarshal state.json: %w", err)
	}

	fresh := repository.NewState()
	if st.Quotes == nil {
		st.Quotes = fresh.Quotes
	}
	if st.QuoteReqs == nil {
		st.QuoteReqs = fresh.QuoteReqs
	}
	if st.Offers == nil {
		st.Offers = fresh.Offers
	}
	if st.OTPs == nil {
		st.OTPs = fresh.OTPs
	}
	if st.Uploads == nil {
		st.Uploads = fresh.Uploads
	}
	if st.Shares == nil {
		st.Shares = fresh.Shares
	}
	if st.Users == nil {
		st.Users = fresh.Users
	}
	if st.UserByPhone == nil {
		st.UserByPhone = fresh.UserByPhone
	}
	if st.UserByGoogleID == nil {
		st.UserByGoogleID = fresh.UserByGoogleID
	}
	if st.UserByFacebookID == nil {
		st.UserByFacebookID = fresh.UserByFacebookID
	}
	if st.UserByEmail == nil {
		st.UserByEmail = fresh.UserByEmail
	}
	if st.Places == nil {
		st.Places = fresh.Places
	}
	if st.Merchants == nil {
		st.Merchants = fresh.Merchants
	}
	if st.Staff == nil {
		st.Staff = fresh.Staff
	}
	if st.Jobs == nil {
		st.Jobs = fresh.Jobs
	}
	if st.Riders == nil {
		st.Riders = fresh.Riders
	}
	if st.Topups == nil {
		st.Topups = fresh.Topups
	}
	if st.Devices == nil {
		st.Devices = fresh.Devices
	}
	if st.Refresh == nil {
		st.Refresh = fresh.Refresh
	}
	if st.Idempotency == nil {
		st.Idempotency = fresh.Idempotency
	}
	if st.Chats == nil {
		st.Chats = fresh.Chats
	}
	if st.Ratings == nil {
		st.Ratings = []domain.Rating{}
	}
	if st.SOS == nil {
		st.SOS = []domain.SOSAlert{}
	}
	return nil
}

// Save atomically writes a state snapshot into path.
func Save(path string, st *repository.State) error {
	b, err := json.Marshal(st)
	if err != nil {
		return fmt.Errorf("marshal state: %w", err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return fmt.Errorf("write temp state: %w", err)
	}
	return os.Rename(tmp, path)
}
