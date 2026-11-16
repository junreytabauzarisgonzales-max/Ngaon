package app

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeProviders mimics the Google, PayMongo and Didit endpoints we call.
type fakeProviders struct {
	mu          sync.Mutex
	paid        map[string]bool
	refunds     []map[string]any
	kycStatus   string
	routeModes  []string
	checkoutReq map[string]any
}

func newFakes(t *testing.T) (*fakeProviders, *httptest.Server) {
	f := &fakeProviders{paid: map[string]bool{}, kycStatus: "In Progress"}
	mux := http.NewServeMux()
	// Google Routes
	mux.HandleFunc("POST /routes", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Goog-Api-Key") != "gkey" || !strings.Contains(r.Header.Get("X-Goog-FieldMask"), "routes.distanceMeters") {
			w.WriteHeader(403)
			return
		}
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		f.mu.Lock()
		f.routeModes = append(f.routeModes, b["travelMode"].(string))
		f.mu.Unlock()
		if b["travelMode"] == "TWO_WHEELER" { // simulate no two-wheeler coverage
			w.Write([]byte(`{}`))
			return
		}
		w.Write([]byte(`{"routes":[{"distanceMeters":2500,"duration":"420s","polyline":{"encodedPolyline":"_p~iF~ps|U_ulLnnqC"}}]}`))
	})
	mux.HandleFunc("GET /geocode", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"status":"OK","results":[{"formatted_address":"Datu Halun St, Bongao, Tawi-Tawi"}]}`))
	})
	mux.HandleFunc("POST /places", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"places":[{"displayName":{"text":"Google Pharmacy"},"formattedAddress":"Bongao","location":{"latitude":5.03,"longitude":119.77}},{"displayName":{"text":"No location"}}]}`))
	})
	// PayMongo
	mux.HandleFunc("POST /pm/v1/checkout_sessions", func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.Header.Get("Authorization"), "Basic ") {
			w.WriteHeader(401)
			return
		}
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		f.mu.Lock()
		f.checkoutReq = b
		f.mu.Unlock()
		id := "cs_" + newID()[:8]
		fmt.Fprintf(w, `{"data":{"id":%q,"attributes":{"checkout_url":"https://checkout.paymongo.test/%s"}}}`, id, id)
	})
	mux.HandleFunc("GET /pm/v1/checkout_sessions/{id}", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		paid := f.paid[r.PathValue("id")]
		f.mu.Unlock()
		pays := `[]`
		if paid {
			pays = `[{"id":"pay_123","attributes":{"status":"paid"}}]`
		}
		fmt.Fprintf(w, `{"data":{"id":%q,"attributes":{"status":"active","payments":%s}}}`, r.PathValue("id"), pays)
	})
	mux.HandleFunc("POST /pm/v1/refunds", func(w http.ResponseWriter, r *http.Request) {
		var b map[string]any
		_ = json.NewDecoder(r.Body).Decode(&b)
		f.mu.Lock()
		f.refunds = append(f.refunds, b)
		f.mu.Unlock()
		w.Write([]byte(`{"data":{"id":"ref_1","attributes":{"status":"pending"}}}`))
	})
	// Didit
	mux.HandleFunc("POST /didit/v3/session/", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("x-api-key") != "dkey" {
			w.WriteHeader(401)
			return
		}
		w.WriteHeader(201)
		w.Write([]byte(`{"session_id":"sess-1","url":"https://verify.didit.test/sess-1","status":"Not Started"}`))
	})
	mux.HandleFunc("GET /didit/v3/session/{id}/decision/", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		fmt.Fprintf(w, `{"session_id":%q,"status":%q}`, r.PathValue("id"), f.kycStatus)
	})
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return f, ts
}

func newIntegratedServer(t *testing.T) (*Server, *httptest.Server, *fakeProviders) {
	f, fake := newFakes(t)
	s, err := NewServer(Config{
		DataDir: t.TempDir(), JWTSecret: []byte("test"), DevOTPCode: "123456", RiderStartBalance: 20000, AdminToken: "adm", MaxDispatchM: 15000,
		Maps:     MapsConfig{APIKey: "gkey", RoutesURL: fake.URL + "/routes", GeocodeURL: fake.URL + "/geocode", PlacesURL: fake.URL + "/places"},
		PayMongo: PayMongoConfig{SecretKey: "sk_test_x", WebhookSecret: "whsec", BaseURL: fake.URL + "/pm"},
		Didit:    DiditConfig{APIKey: "dkey", WorkflowID: "wf", WebhookSecret: "dsec", BaseURL: fake.URL + "/didit"},
	})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(s.Routes())
	s.cfg.PublicURL = ts.URL
	t.Cleanup(ts.Close)
	return s, ts, f
}

func TestGoogleRoutingAndGeo(t *testing.T) {
	_, ts, f := newIntegratedServer(t)
	c := login(t, ts.URL, "customer", "+639171234567", "Aisha")
	q := m(c.must("POST", "/quotes", map[string]any{"service": "ride", "pickup": home, "dropoff": capitol}))
	if q["distance_m"].(float64) != 2500 || q["duration_s"].(float64) != 420 || q["route_polyline"] == nil {
		t.Fatalf("quote should use Google route: %v", q)
	}
	if strings.Join(f.routeModes, ",") != "TWO_WHEELER,DRIVE" {
		t.Fatalf("expected two-wheeler then drive fallback, got %v", f.routeModes)
	}
	job := m(c.must("POST", "/jobs", map[string]any{"quote_id": q["id"], "payment_method": "cash"}))
	if job["route_polyline"] == nil || !strings.HasPrefix(job["code"].(string), "NG-") {
		t.Fatalf("job: %v %v", job["route_polyline"], job["code"])
	}
	if a := m(c.must("GET", "/geo/reverse?lat=5.03&lng=119.77", nil))["address"]; a != "Datu Halun St, Bongao, Tawi-Tawi" {
		t.Fatalf("reverse: %v", a)
	}
	res := c.must("GET", "/geo/search?q=pharm&lat=5.03&lng=119.77", nil).([]any)
	if len(res) != 1 || m(res[0])["name"] != "Google Pharmacy" {
		t.Fatalf("search: %v", res)
	}
}

func TestPayMongoCheckoutRefundAndTopup(t *testing.T) {
	s, ts, f := newIntegratedServer(t)
	c := login(t, ts.URL, "customer", "+639171234567", "Aisha")
	q := m(c.must("POST", "/quotes", map[string]any{"service": "ride", "pickup": home, "dropoff": capitol}))
	job := m(c.must("POST", "/jobs", map[string]any{"quote_id": q["id"], "payment_method": "maya"}))
	url := m(job["payment"])["checkout_url"].(string)
	if !strings.HasPrefix(url, "https://checkout.paymongo.test/cs_") || job["status"] != "pending_payment" {
		t.Fatalf("checkout: %v %v", url, job["status"])
	}
	attrs := m(m(f.checkoutReq["data"])["attributes"])
	if attrs["payment_method_types"].([]any)[0] != "paymaya" || m(attrs["line_items"].([]any)[0])["amount"].(float64) != q["total_centavos"].(float64) {
		t.Fatalf("checkout request: %v", attrs)
	}
	jid := job["id"].(string)
	if m(c.must("GET", "/jobs/"+jid, nil))["status"] != "pending_payment" {
		t.Fatal("not paid yet")
	}
	cs := strings.TrimPrefix(url, "https://checkout.paymongo.test/")
	f.mu.Lock()
	f.paid[cs] = true
	f.mu.Unlock()
	s.lock()
	s.st.Jobs[jid].PayCheckedAt = time.Time{} // skip the 4 s poll throttle
	s.unlock()
	j := m(c.must("GET", "/jobs/"+jid, nil))
	if j["status"] != "searching" || m(j["payment"])["status"] != "paid" {
		t.Fatalf("after paid: %v %v", j["status"], j["payment"])
	}
	c.must("POST", "/jobs/"+jid+"/cancel", map[string]any{"reason": "changed mind"})
	time.Sleep(200 * time.Millisecond) // refund runs after unlock
	f.mu.Lock()
	if len(f.refunds) != 1 || m(m(f.refunds[0]["data"])["attributes"])["payment_id"] != "pay_123" {
		t.Fatalf("refund: %v", f.refunds)
	}
	f.mu.Unlock()

	// rider top-up through PayMongo, credited when the wallet polls
	r := login(t, ts.URL, "rider", "+639181112222", "Jamal")
	top := m(r.must("POST", "/rider/wallet/topups", map[string]any{"amount_centavos": 50000, "method": "gcash"}))
	tcs := strings.TrimPrefix(top["checkout_url"].(string), "https://checkout.paymongo.test/")
	before := m(r.must("GET", "/rider/wallet", nil))["balance_centavos"].(float64)
	f.mu.Lock()
	f.paid[tcs] = true
	f.mu.Unlock()
	s.lock()
	for _, tp := range s.st.Topups {
		tp.CheckedAt = time.Time{}
	}
	s.unlock()
	after := m(r.must("GET", "/rider/wallet", nil))["balance_centavos"].(float64)
	if after-before != 50000 {
		t.Fatalf("topup credit: %v -> %v", before, after)
	}
}

func TestPayMongoWebhookSignature(t *testing.T) {
	p := NewPayMongo(PayMongoConfig{SecretKey: "sk", WebhookSecret: "whsec"})
	body := []byte(`{"data":{"id":"evt_1"}}`)
	mac := hmac.New(sha256.New, []byte("whsec"))
	mac.Write([]byte("1700000000." + string(body)))
	sig := hex.EncodeToString(mac.Sum(nil))
	if !p.VerifyWebhook(body, "t=1700000000,te="+sig+",li=") {
		t.Fatal("t/te format should verify")
	}
	if p.VerifyWebhook(body, "t=1700000000,te=deadbeef,li=") {
		t.Fatal("bad signature must fail")
	}
	mac = hmac.New(sha256.New, []byte("whsec"))
	mac.Write(body)
	if !p.VerifyWebhook(body, hex.EncodeToString(mac.Sum(nil))) {
		t.Fatal("bare HMAC form should verify")
	}
}

func TestDiditKycApprovesRider(t *testing.T) {
	s, ts, f := newIntegratedServer(t)
	r := login(t, ts.URL, "rider", "+639181112222", "Jamal Hassan")
	if st := m(r.must("GET", "/rider/me", nil))["kyc_status"]; st != "not_started" {
		t.Fatalf("kyc_status: %v", st)
	}
	docs := map[string]any{}
	for _, k := range []string{"license_key", "orcr_key", "selfie_key", "clearance_key"} {
		u := m(r.must("POST", "/uploads", map[string]any{"purpose": "rider_license", "content_type": "image/jpeg"}))
		put(t, u["upload_url"].(string))
		docs[k] = u["key"]
	}
	r.must("PUT", "/rider/me", map[string]any{"vehicle": map[string]any{"plate": "1", "make_model": "Honda", "color": "Red"}, "documents": docs})
	sess := m(r.must("POST", "/rider/kyc/session", nil))
	if sess["url"] != "https://verify.didit.test/sess-1" || sess["kyc_status"] != "in_progress" {
		t.Fatalf("session: %v", sess)
	}
	s.Tick()
	if m(r.must("GET", "/rider/me", nil))["status"] != "pending_review" {
		t.Fatal("must wait for KYC")
	}
	f.mu.Lock()
	f.kycStatus = "Approved"
	f.mu.Unlock()
	s.lock()
	s.st.Riders[s.st.UserByPhone["+639181112222"]].KycCheckedAt = time.Time{}
	s.unlock()
	p := m(r.must("GET", "/rider/me", nil))
	if p["kyc_status"] != "approved" || p["status"] != "approved" {
		t.Fatalf("after KYC approval: %v %v", p["kyc_status"], p["status"])
	}
}

func TestDiditWebhookSignature(t *testing.T) {
	_, ts, _ := newIntegratedServer(t)
	body := []byte(`{"session_id":"sess-1","status":"Approved","vendor_data":"nobody"}`)
	post := func(sig, tsHeader string) int {
		req, _ := http.NewRequest("POST", ts.URL+"/webhooks/didit", strings.NewReader(string(body)))
		req.Header.Set("X-Signature", sig)
		req.Header.Set("X-Timestamp", tsHeader)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, res.Body)
		return res.StatusCode
	}
	mac := hmac.New(sha256.New, []byte("dsec"))
	mac.Write(body)
	good := hex.EncodeToString(mac.Sum(nil))
	now := strconv.FormatInt(time.Now().Unix(), 10)
	if post(good, now) != 200 {
		t.Fatal("valid webhook rejected")
	}
	if post("bad", now) != 401 || post(good, "1000") != 401 {
		t.Fatal("bad signature / stale timestamp must be rejected")
	}
}
