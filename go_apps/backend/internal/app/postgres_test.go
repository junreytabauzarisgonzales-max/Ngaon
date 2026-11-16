package app

import (
	"os"
	"testing"
	"time"
)

func TestPostgresIntegration(t *testing.T) {
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping postgres integration test")
	}

	cfg := Config{
		DatabaseURL:        dbURL,
		DataDir:            t.TempDir(),
		JWTSecret:          []byte("test-jwt-secret"),
		DevOTPCode:         "123456",
		AutoApproveSeconds: 1,
		RiderStartBalance:  20000,
		AdminToken:         "test-admin",
		AnyLocation:        true,
	}

	// 1. First server start (initial migration + seeding)
	s1, err := NewServer(cfg)
	if err != nil {
		t.Fatalf("first NewServer failed: %v", err)
	}

	// Clean tables for isolated integration test run
	_, _ = s1.db.Exec(`TRUNCATE TABLE reviews, sos_alerts, chat_messages, wallet_transactions, wallets, topups, merchant_payouts, order_status_history, order_items, orders, kyc_documents, kyc_verifications, riders, menu_modifier_options, menu_modifier_groups, menu_items, menu_categories, merchant_operating_hours, merchant_staff, merchants, user_addresses, users, refresh_tokens, device_tokens, idempotency_keys, upload_records CASCADE;`)
	s1.st = newState()
	if err := s1.seed(); err != nil {
		t.Fatalf("seed failed: %v", err)
	}
	s1.dirty = true
	s1.Save()

	if len(s1.st.Merchants) == 0 {
		t.Fatalf("expected seeded merchants in postgres, got 0")
	}

	// Add test user
	u := &User{
		ID:        newID(),
		Phone:     "+639170009999",
		Name:      "Test Customer",
		Language:  "en",
		Roles:     []string{"customer"},
		CreatedAt: Now(),
	}
	s1.st.Users[u.ID] = u
	s1.st.UserByPhone[u.Phone] = u.ID

	// Add test place
	place := &SavedPlace{
		ID:       newID(),
		UserID:   u.ID,
		Label:    "Office",
		Address:  "Provincial Capitol, Bongao",
		Location: LatLng{Lat: 5.0362, Lng: 119.7795},
	}
	s1.st.Places[place.ID] = place

	// Add test rider
	rUser := &User{
		ID:        newID(),
		Phone:     "+639180008888",
		Name:      "Test Rider",
		Language:  "en",
		Roles:     []string{"customer", "rider"},
		CreatedAt: Now(),
	}
	s1.st.Users[rUser.ID] = rUser
	s1.st.UserByPhone[rUser.Phone] = rUser.ID

	rider := &Rider{
		Profile: RiderProfile{
			ID:                 newID(),
			UserID:             rUser.ID,
			Status:             "approved",
			IsOnline:           false,
			BalanceCentavos:    25000,
			MinBalanceCentavos: 5000,
			Vehicle: &Vehicle{
				Plate:     "TAWI-123",
				MakeModel: "Yamaha NMAX",
				Color:     "Blue",
			},
		},
		Documents:   map[string]string{"license_key": "lic123.jpg"},
		SubmittedAt: time.Now().UTC(),
	}
	s1.st.Riders[rUser.ID] = rider

	// Add test ride job (Transportation)
	rideJob := &JobState{
		Job: Job{
			ID:        newID(),
			Code:      "GO-5001",
			Service:   "ride",
			Status:    "rider_assigned",
			CreatedAt: Now(),
			UpdatedAt: Now(),
			Pickup: Stop{
				Address:  "Lamion, Bongao",
				Location: LatLng{Lat: 5.0251, Lng: 119.7769},
			},
			Dropoff: Stop{
				Address:  "Capitol, Bongao",
				Location: LatLng{Lat: 5.0362, Lng: 119.7795},
			},
			Fare: Fare{
				TotalCentavos: 8000,
				Breakdown:     []FareLine{{Label: "Base fare", AmountCentavos: 8000}},
			},
			Payment: JobPayment{
				Method: "cash",
				Status: "pending",
			},
			Timeline: []TimelineEntry{
				{Status: "searching", At: Now()},
				{Status: "rider_assigned", At: Now()},
			},
		},
		CustomerID:       u.ID,
		RiderUserID:      rUser.ID,
		EarningsCentavos: 6500,
		FeesCentavos:     1500,
	}
	s1.st.Jobs[rideJob.Job.ID] = rideJob
	s1.st.JobIDs = append(s1.st.JobIDs, rideJob.Job.ID)

	// Add test pabili job (Buying)
	pabiliJob := &JobState{
		Job: Job{
			ID:        newID(),
			Code:      "GO-5002",
			Service:   "pabili",
			Status:    "items_purchased",
			CreatedAt: Now(),
			UpdatedAt: Now(),
			Pickup: Stop{
				Address:  "Bongao Public Market",
				Location: LatLng{Lat: 5.0294, Lng: 119.7730},
			},
			Dropoff: Stop{
				Address:  "Lamion, Bongao",
				Location: LatLng{Lat: 5.0251, Lng: 119.7769},
			},
			Pabili: &JobPabili{
				StoreName: "Datu Store",
				Items: []PabiliItem{
					{Name: "Canned Goods", Quantity: 3},
				},
				ReceiptURL:        strp("https://example.com/receipt.jpg"),
				ItemTotalCentavos: intp(35000),
			},
			Fare: Fare{
				TotalCentavos: 12000,
				Breakdown:     []FareLine{{Label: "Delivery fee", AmountCentavos: 12000}},
			},
			Payment: JobPayment{
				Method: "cash",
				Status: "pending",
			},
		},
		CustomerID:  u.ID,
		RiderUserID: rUser.ID,
	}
	s1.st.Jobs[pabiliJob.Job.ID] = pabiliJob
	s1.st.JobIDs = append(s1.st.JobIDs, pabiliJob.Job.ID)

	// Add test food job (Food Delivery)
	firstMerchID := s1.st.MerchantIDs[0]
	foodJob := &JobState{
		Job: Job{
			ID:        newID(),
			Code:      "GO-5003",
			Service:   "food",
			Status:    "merchant_preparing",
			CreatedAt: Now(),
			UpdatedAt: Now(),
			Pickup: Stop{
				Address:  "Kusina Bongao, Datu Halun St.",
				Location: LatLng{Lat: 5.0291, Lng: 119.7712},
			},
			Dropoff: Stop{
				Address:  "Lamion, Bongao",
				Location: LatLng{Lat: 5.0251, Lng: 119.7769},
			},
			Food: &JobFood{
				SubtotalCentavos: 45000,
				PrepTimeMinutes:  intp(25),
				IsReady:          false,
				Items: []OrderLine{
					{Name: "Chicken Inasal", Quantity: 2, LineTotalCentavos: 36000, Addons: []string{"Extra Rice"}},
					{Name: "Iced Tea", Quantity: 2, LineTotalCentavos: 9000},
				},
			},
			Fare: Fare{
				TotalCentavos: 52000,
				Breakdown:     []FareLine{{Label: "Food subtotal", AmountCentavos: 45000}, {Label: "Delivery fee", AmountCentavos: 7000}},
			},
			Payment: JobPayment{
				Method: "cash",
				Status: "pending",
			},
		},
		CustomerID:         u.ID,
		MerchantID:         firstMerchID,
		RiderUserID:        rUser.ID,
		CommissionCentavos: 6750,
		Order: &MerchantOrderState{
			ID:         newID(),
			Status:     "preparing",
			Commission: 6750,
		},
	}
	s1.st.Jobs[foodJob.Job.ID] = foodJob
	s1.st.JobIDs = append(s1.st.JobIDs, foodJob.Job.ID)

	// Add test padala job (Logistics)
	padalaJob := &JobState{
		Job: Job{
			ID:        newID(),
			Code:      "GO-5004",
			Service:   "padala",
			Status:    "searching",
			CreatedAt: Now(),
			UpdatedAt: Now(),
			Pickup: Stop{
				Address:  "Port of Bongao",
				Location: LatLng{Lat: 5.0280, Lng: 119.7700},
			},
			Dropoff: Stop{
				Address:  "MSU Tawi-Tawi",
				Location: LatLng{Lat: 5.0350, Lng: 119.7800},
			},
			Padala: &JobPadala{
				Size:           "medium",
				Description:    "Documents and pouch",
				RecipientName:  "Fatima Omar",
				RecipientPhone: "+639191113333",
			},
			Fare: Fare{
				TotalCentavos: 9000,
				Breakdown:     []FareLine{{Label: "Padala fee", AmountCentavos: 9000}},
			},
			Payment: JobPayment{
				Method: "cash",
				Status: "pending",
			},
		},
		CustomerID: u.ID,
	}
	s1.st.Jobs[padalaJob.Job.ID] = padalaJob
	s1.st.JobIDs = append(s1.st.JobIDs, padalaJob.Job.ID)

	// Add wallet transaction
	tx := &WalletTransaction{
		ID:                   newID(),
		UserID:               rUser.ID,
		Type:                 "delivery_fee_earned",
		AmountCentavos:       6500,
		BalanceAfterCentavos: 25000,
		JobID:                strp(rideJob.Job.ID),
		Note:                 strp("Ride delivery fare"),
		CreatedAt:            Now(),
	}
	s1.st.Txs = append(s1.st.Txs, tx)

	// Add chat message
	cm := &ChatMessage{
		ID:        newID(),
		JobID:     rideJob.Job.ID,
		Sender:    "customer",
		Text:      strp("Waiting at the corner"),
		CreatedAt: Now(),
	}
	s1.st.Chats[rideJob.Job.ID] = append(s1.st.Chats[rideJob.Job.ID], cm)

	// Add rating
	s1.st.Ratings = append(s1.st.Ratings, Rating{
		JobID:          rideJob.Job.ID,
		RiderRating:    5,
		RiderTags:      []string{"polite", "safe_driver"},
		Comment:        strp("Smooth ride!"),
		MerchantRating: intp(5),
	})

	// Add SOS alert
	s1.st.SOS = append(s1.st.SOS, SOSAlert{
		JobID:    rideJob.Job.ID,
		UserID:   u.ID,
		Location: LatLng{Lat: 5.0251, Lng: 119.7769},
		At:       Now(),
	})

	// Add Topup
	tp := &Topup{
		ID:             newID(),
		UserID:         rUser.ID,
		AmountCentavos: 10000,
		Method:         "gcash",
		Status:         "successful",
	}
	s1.st.Topups[tp.ID] = tp

	// Add device and refresh token
	s1.st.Devices[u.ID] = Device{UserID: u.ID, Token: "fcm_test_token", Platform: "android", App: "customer"}
	s1.st.Refresh["refresh_hash_123"] = RefreshToken{UserID: u.ID, App: "customer", Expires: time.Now().Add(30 * 24 * time.Hour).UTC()}

	// Mark dirty and save to Postgres twice to verify idempotency (no duplicate child rows)
	s1.dirty = true
	s1.Save()
	s1.dirty = true
	s1.Save()

	// 2. Second server start: should reload everything from Postgres!
	s2, err := NewServer(cfg)
	if err != nil {
		t.Fatalf("second NewServer failed: %v", err)
	}

	// Verify user
	loadedUser := s2.st.Users[u.ID]
	if loadedUser == nil {
		t.Fatalf("user %s not loaded from postgres", u.ID)
	}
	if loadedUser.Name != u.Name || loadedUser.Phone != u.Phone {
		t.Errorf("user mismatch: got %+v, want %+v", loadedUser, u)
	}

	// Verify place
	loadedPlace := s2.st.Places[place.ID]
	if loadedPlace == nil {
		t.Fatalf("place %s not loaded from postgres", place.ID)
	}
	if loadedPlace.Label != "Office" {
		t.Errorf("place label mismatch: got %s", loadedPlace.Label)
	}

	// Verify rider
	loadedRider := s2.st.Riders[rUser.ID]
	if loadedRider == nil {
		t.Fatalf("rider %s not loaded from postgres", rUser.ID)
	}
	if loadedRider.Profile.Vehicle == nil || loadedRider.Profile.Vehicle.Plate != "TAWI-123" {
		t.Errorf("rider vehicle mismatch: got %+v", loadedRider.Profile.Vehicle)
	}
	if loadedRider.Profile.BalanceCentavos != 25000 {
		t.Errorf("rider balance mismatch: got %d", loadedRider.Profile.BalanceCentavos)
	}

	// Verify transportation ride job
	loadedRide := s2.st.Jobs[rideJob.Job.ID]
	if loadedRide == nil {
		t.Fatalf("ride job %s not loaded from postgres", rideJob.Job.ID)
	}
	if loadedRide.Job.Service != "ride" || loadedRide.Job.Status != "rider_assigned" {
		t.Errorf("ride job details mismatch: got service=%s, status=%s", loadedRide.Job.Service, loadedRide.Job.Status)
	}
	if loadedRide.RiderUserID != rUser.ID {
		t.Errorf("ride job rider mismatch: got %s, want %s", loadedRide.RiderUserID, rUser.ID)
	}
	if len(loadedRide.Job.Timeline) != 2 {
		t.Errorf("ride job timeline count mismatch after repeated saves: got %d, want 2", len(loadedRide.Job.Timeline))
	}

	// Verify buying pabili job
	loadedPabili := s2.st.Jobs[pabiliJob.Job.ID]
	if loadedPabili == nil {
		t.Fatalf("pabili job %s not loaded from postgres", pabiliJob.Job.ID)
	}
	if loadedPabili.Job.Service != "pabili" || loadedPabili.Job.Pabili == nil {
		t.Fatalf("pabili job payload mismatch: %+v", loadedPabili.Job)
	}
	if loadedPabili.Job.Pabili.StoreName != "Datu Store" {
		t.Errorf("pabili store name mismatch: got %s", loadedPabili.Job.Pabili.StoreName)
	}
	if len(loadedPabili.Job.Pabili.Items) != 1 || loadedPabili.Job.Pabili.Items[0].Name != "Canned Goods" {
		t.Errorf("pabili items mismatch: %+v", loadedPabili.Job.Pabili.Items)
	}
	if loadedPabili.Job.Pabili.ItemTotalCentavos == nil || *loadedPabili.Job.Pabili.ItemTotalCentavos != 35000 {
		t.Errorf("pabili item total mismatch: got %v", loadedPabili.Job.Pabili.ItemTotalCentavos)
	}

	// Verify food job (Food delivery)
	loadedFood := s2.st.Jobs[foodJob.Job.ID]
	if loadedFood == nil {
		t.Fatalf("food job %s not loaded from postgres", foodJob.Job.ID)
	}
	if loadedFood.Job.Service != "food" || loadedFood.Job.Food == nil {
		t.Fatalf("food job payload mismatch: %+v", loadedFood.Job)
	}
	if len(loadedFood.Job.Food.Items) != 2 {
		t.Errorf("food items count mismatch: got %d, want 2", len(loadedFood.Job.Food.Items))
	}
	if loadedFood.Order == nil || loadedFood.Order.Status != "preparing" {
		t.Errorf("food merchant order status mismatch: %+v", loadedFood.Order)
	}

	// Verify padala job (Logistics)
	loadedPadala := s2.st.Jobs[padalaJob.Job.ID]
	if loadedPadala == nil {
		t.Fatalf("padala job %s not loaded from postgres", padalaJob.Job.ID)
	}
	if loadedPadala.Job.Service != "padala" || loadedPadala.Job.Padala == nil {
		t.Fatalf("padala job payload mismatch: %+v", loadedPadala.Job)
	}
	if loadedPadala.Job.Padala.RecipientName != "Fatima Omar" {
		t.Errorf("padala recipient mismatch: got %s", loadedPadala.Job.Padala.RecipientName)
	}

	// Verify transaction
	if len(s2.st.Txs) == 0 {
		t.Errorf("expected wallet transactions loaded from postgres")
	} else if s2.st.Txs[0].AmountCentavos != 6500 {
		t.Errorf("tx amount mismatch: got %d, want 6500", s2.st.Txs[0].AmountCentavos)
	}

	// Verify chat message
	chatMsgs := s2.st.Chats[rideJob.Job.ID]
	if len(chatMsgs) == 0 {
		t.Errorf("expected chat messages for ride job, got 0")
	} else if chatMsgs[0].Text == nil || *chatMsgs[0].Text != "Waiting at the corner" {
		t.Errorf("chat message text mismatch: got %v", chatMsgs[0].Text)
	}

	// Verify review / rating
	if len(s2.st.Ratings) == 0 {
		t.Errorf("expected ratings loaded, got 0")
	} else if s2.st.Ratings[0].RiderRating != 5 {
		t.Errorf("rider rating mismatch: got %d", s2.st.Ratings[0].RiderRating)
	}

	// Verify SOS alert
	if len(s2.st.SOS) != 1 {
		t.Errorf("expected 1 SOS alert loaded after repeated saves, got %d", len(s2.st.SOS))
	}

	// Verify topup
	loadedTopup := s2.st.Topups[tp.ID]
	if loadedTopup == nil || loadedTopup.AmountCentavos != 10000 {
		t.Errorf("topup mismatch: got %+v", loadedTopup)
	}

	// Verify device & refresh token
	if dev, ok := s2.st.Devices[u.ID]; !ok || dev.Token != "fcm_test_token" {
		t.Errorf("device token mismatch: %+v", dev)
	}
	if ref, ok := s2.st.Refresh["refresh_hash_123"]; !ok || ref.UserID != u.ID {
		t.Errorf("refresh token mismatch: %+v", ref)
	}
}
