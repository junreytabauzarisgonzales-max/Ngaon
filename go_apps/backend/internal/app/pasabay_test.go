package app

import (
	"fmt"
	"testing"
	"time"
)

func approvedTricycleRider(t *testing.T, s *Server, base string) *client {
	r := login(t, base, "rider", "+639189998888", "Kadir Driver")
	docs := map[string]any{}
	for _, f := range []string{"license_key", "orcr_key", "selfie_key", "clearance_key"} {
		u := m(r.must("POST", "/uploads", map[string]any{"purpose": "rider_license", "content_type": "image/jpeg"}))
		put(t, u["upload_url"].(string))
		docs[f] = u["key"]
	}
	p := m(r.must("PUT", "/rider/me", map[string]any{
		"vehicle": map[string]any{
			"plate":      "TRIKE-777",
			"make_model": "Kawasaki Barako",
			"color":      "Blue",
			"type":       "tricycle",
			"capacity":   4,
		},
		"documents": docs,
	}))
	if p["status"] != "pending_review" {
		t.Fatalf("status %v", p["status"])
	}
	time.Sleep(1100 * time.Millisecond)
	s.Tick()
	r.must("POST", "/rider/status", map[string]any{"online": true, "location": map[string]any{"lat": 5.029, "lng": 119.772}})
	return r
}

func TestPasabaySharedRideFlow(t *testing.T) {
	s, ts := newTestServer(t)

	// 1. Create and approve a rider with a Tricycle (Capacity 4)
	r := approvedTricycleRider(t, s, ts.URL)

	// 2. Passenger 1 checks quotes for Ride
	p1 := login(t, ts.URL, "customer", "+639171110001", "Passenger Aisha")
	q1 := m(p1.must("POST", "/quotes", map[string]any{
		"service": "ride",
		"pickup":  home,
		"dropoff": capitol,
	}))

	tiers, ok := q1["ride_tiers"].([]any)
	if !ok || len(tiers) != 3 {
		t.Fatalf("expected 3 ride_tiers, got %v", q1["ride_tiers"])
	}
	// Verify tiers exist
	foundTrike := false
	for _, ti := range tiers {
		tm := ti.(map[string]any)
		if tm["tier"] == "pasabay_tricycle" {
			foundTrike = true
			if int(tm["max_capacity"].(float64)) != 4 {
				t.Fatalf("expected tricycle max_capacity 4, got %v", tm["max_capacity"])
			}
		}
	}
	if !foundTrike {
		t.Fatal("pasabay_tricycle tier missing from quote")
	}

	// 3. Passenger 1 books Pasabay (1 seat)
	q1Pasabay := m(p1.must("POST", "/quotes", map[string]any{
		"service": "ride",
		"pickup":  home,
		"dropoff": capitol,
		"ride": map[string]any{
			"tier":         "pasabay_tricycle",
			"seats_booked": 1,
		},
	}))
	job1 := m(p1.must("POST", "/jobs", map[string]any{
		"quote_id":       q1Pasabay["id"],
		"payment_method": "cash",
	}))
	job1ID := job1["id"].(string)

	// Rider accepts Job 1
	offer1 := m(r.must("GET", "/rider/offers/current", nil))
	if offer1["id"] == nil {
		t.Fatal("expected rider offer for job 1")
	}
	r.must("POST", fmt.Sprintf("/rider/offers/%s/accept", offer1["id"]), nil)

	// Verify Job 1 initial unshared fare
	j1AfterAccept := m(p1.must("GET", "/jobs/"+job1ID, nil))
	initialFare := int(j1AfterAccept["fare"].(map[string]any)["total_centavos"].(float64))
	if initialFare <= 0 {
		t.Fatalf("invalid initial fare: %d", initialFare)
	}

	// 4. Passenger 2 books Pasabay (1 seat) along the same route
	p2 := login(t, ts.URL, "customer", "+639171110002", "Passenger Ben")
	q2Pasabay := m(p2.must("POST", "/quotes", map[string]any{
		"service": "ride",
		"pickup":  home,
		"dropoff": capitol,
		"ride": map[string]any{
			"tier":         "pasabay_tricycle",
			"seats_booked": 1,
		},
	}))
	job2 := m(p2.must("POST", "/jobs", map[string]any{
		"quote_id":       q2Pasabay["id"],
		"payment_method": "cash",
	}))
	job2ID := job2["id"].(string)

	// Driver (already carrying Passenger 1) receives Offer 2 because capacity is 4!
	offer2 := m(r.must("GET", "/rider/offers/current", nil))
	if offer2["id"] == nil {
		t.Fatal("expected driver with remaining seats to receive offer for job 2")
	}
	r.must("POST", fmt.Sprintf("/rider/offers/%s/accept", offer2["id"]), nil)

	// 5. Verify dynamic split: rate is divided by 2 seats!
	j1Updated := m(p1.must("GET", "/jobs/"+job1ID, nil))
	j2Updated := m(p2.must("GET", "/jobs/"+job2ID, nil))

	j1Fare := int(j1Updated["fare"].(map[string]any)["total_centavos"].(float64))
	j2Fare := int(j2Updated["fare"].(map[string]any)["total_centavos"].(float64))

	expectedSplit := initialFare / 2
	if j1Fare != expectedSplit {
		t.Fatalf("expected Passenger 1 fare to drop to %d, got %d", expectedSplit, j1Fare)
	}
	if j2Fare != expectedSplit {
		t.Fatalf("expected Passenger 2 fare to be %d, got %d", expectedSplit, j2Fare)
	}

	// 6. Complete Passenger 1
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job1ID), map[string]any{"status": "arrived_pickup"})
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job1ID), map[string]any{"status": "picked_up"})
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job1ID), map[string]any{"status": "arrived_dropoff"})
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job1ID), map[string]any{"status": "completed"})

	// Passenger 1 is completed; Passenger 2 is still active
	j1Final := m(p1.must("GET", "/jobs/"+job1ID, nil))
	if j1Final["status"] != "completed" {
		t.Fatalf("expected job 1 completed, got %v", j1Final["status"])
	}

	// Active job on rider points to Job 2
	riderActive := m(r.must("GET", "/rider/jobs/active", nil))
	if riderActive["id"] != job2ID {
		t.Fatalf("expected active job to switch to job 2, got %v", riderActive["id"])
	}

	// Complete Passenger 2
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job2ID), map[string]any{"status": "arrived_pickup"})
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job2ID), map[string]any{"status": "picked_up"})
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job2ID), map[string]any{"status": "arrived_dropoff"})
	r.must("POST", fmt.Sprintf("/rider/jobs/%s/status", job2ID), map[string]any{"status": "completed"})

	// Now driver has no active jobs
	riderNoActive := r.must("GET", "/rider/jobs/active", nil)
	if riderNoActive != nil {
		t.Fatalf("expected no active job after completing all, got %v", riderNoActive)
	}
}
