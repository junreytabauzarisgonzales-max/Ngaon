package app

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

type client struct {
	t     *testing.T
	base  string
	app   string
	token string
}

func (c *client) do(method, path string, body any, hdr ...string) (int, map[string]any) {
	c.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.base+"/api/v1"+path, rd)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-App", c.app)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

// must asserts 200 and returns `data`.
func (c *client) must(method, path string, body any, hdr ...string) any {
	c.t.Helper()
	code, out := c.do(method, path, body, hdr...)
	if code != 200 {
		c.t.Fatalf("%s %s -> %d %v", method, path, code, out)
	}
	return out["data"]
}

func (c *client) errCode(method, path string, body any) string {
	c.t.Helper()
	code, out := c.do(method, path, body)
	if code < 400 {
		c.t.Fatalf("%s %s expected error, got %d", method, path, code)
	}
	return out["error"].(map[string]any)["code"].(string)
}

func login(t *testing.T, base, app, phone, name string) *client {
	c := &client{t: t, base: base, app: app}
	c.must("POST", "/auth/otp/request", map[string]any{"phone": phone})
	d := c.must("POST", "/auth/otp/verify", map[string]any{"phone": phone, "code": "123456", "app": app}).(map[string]any)
	c.token = d["access_token"].(string)
	if name != "" && d["is_new_user"] == true {
		c.must("PATCH", "/me", map[string]any{"name": name})
	}
	return c
}

func m(v any) map[string]any { return v.(map[string]any) }

func newTestServer(t *testing.T) (*Server, *httptest.Server) {
	s, err := NewServer(Config{DataDir: t.TempDir(), JWTSecret: []byte("test"), DevOTPCode: "123456", AutoApproveSeconds: 1, RiderStartBalance: 20000, AdminToken: "adm", MaxDispatchM: 15000})
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(s.Routes())
	s.cfg.PublicURL = ts.URL
	t.Cleanup(ts.Close)
	return s, ts
}

var home = map[string]any{"address": "Lamion, Bongao", "location": map[string]any{"lat": 5.0251, "lng": 119.7769}}
var capitol = map[string]any{"address": "Capitol", "location": map[string]any{"lat": 5.0362, "lng": 119.7795}}

// approvedRider signs a rider up, waits for auto-approval and goes online at the pickup.
func approvedRider(t *testing.T, s *Server, base string) *client {
	r := login(t, base, "rider", "+639181112222", "Jamal Hassan")
	docs := map[string]any{}
	for _, f := range []string{"license_key", "orcr_key", "selfie_key", "clearance_key"} {
		u := m(r.must("POST", "/uploads", map[string]any{"purpose": "rider_license", "content_type": "image/jpeg"}))
		put(t, u["upload_url"].(string))
		docs[f] = u["key"]
	}
	p := m(r.must("PUT", "/rider/me", map[string]any{"vehicle": map[string]any{"plate": "123 abc", "make_model": "Honda Click", "color": "Red"}, "documents": docs}))
	if p["status"] != "pending_review" {
		t.Fatalf("status %v", p["status"])
	}
	if r.errCode("POST", "/rider/status", map[string]any{"online": true, "location": home["location"]}) != "rider_not_approved" {
		t.Fatal("should not go online before approval")
	}
	time.Sleep(1100 * time.Millisecond)
	s.Tick()
	r.must("POST", "/rider/status", map[string]any{"online": true, "location": map[string]any{"lat": 5.029, "lng": 119.772}})
	return r
}

func put(t *testing.T, uploadURL string) {
	req, _ := http.NewRequest("PUT", uploadURL, strings.NewReader("\xff\xd8fake-jpeg"))
	req.Header.Set("Content-Type", "image/jpeg")
	res, err := http.DefaultClient.Do(req)
	if err != nil || res.StatusCode != 200 {
		t.Fatalf("upload PUT failed: %v %v", err, res)
	}
}

func step(t *testing.T, r *client, jobID, status string, extra map[string]any) map[string]any {
	body := map[string]any{"status": status, "location": map[string]any{"lat": 5.03, "lng": 119.773}}
	for k, v := range extra {
		body[k] = v
	}
	return m(r.must("POST", "/rider/jobs/"+jobID+"/status", body))
}

func TestFoodCashFlowEndToEnd(t *testing.T) {
	s, ts := newTestServer(t)
	merchant := login(t, ts.URL, "merchant", "+639193334444", "Mering")
	acct := m(merchant.must("GET", "/merchant/me", nil))
	mid := m(acct["merchant"])["id"].(string)
	notMerchant := login(t, ts.URL, "merchant", "+639170000000", "")
	if notMerchant.errCode("GET", "/merchant/me", nil) != "forbidden" {
		t.Fatal("non-merchant must be forbidden")
	}

	cust := login(t, ts.URL, "customer", "+639171234567", "Aisha Tan")
	menu := m(cust.must("GET", "/merchants/"+mid, nil))["menu"].([]any)
	item := m(m(menu[0])["items"].([]any)[0])
	opt := m(m(item["addon_groups"].([]any)[0])["options"].([]any)[1])
	q := m(cust.must("POST", "/quotes", map[string]any{"service": "food", "pickup": home, "dropoff": home,
		"food": map[string]any{"merchant_id": mid, "items": []any{map[string]any{"item_id": item["id"], "quantity": 2, "addon_option_ids": []any{opt["id"]}}}}}))
	job := m(cust.must("POST", "/jobs", map[string]any{"quote_id": q["id"], "payment_method": "cash"}, "Idempotency-Key", "k1"))
	again := m(cust.must("POST", "/jobs", map[string]any{"quote_id": q["id"], "payment_method": "cash"}, "Idempotency-Key", "k1"))
	if job["id"] != again["id"] || job["status"] != "merchant_pending" {
		t.Fatalf("idempotency/status: %v %v", job["status"], again["id"])
	}
	jid := job["id"].(string)

	orders := merchant.must("GET", "/merchant/orders?status=new", nil).([]any)
	if len(orders) != 1 {
		t.Fatalf("expected 1 new order, got %d", len(orders))
	}
	order := m(orders[0])
	if order["rider_pays_at_pickup_centavos"] == nil {
		t.Fatal("cash order must show rider pays at pickup")
	}
	rider := approvedRider(t, s, ts.URL)
	merchant.must("POST", "/merchant/orders/"+order["id"].(string)+"/accept", map[string]any{"prep_time_minutes": 15})
	if merchant.errCode("POST", "/merchant/orders/"+order["id"].(string)+"/accept", map[string]any{"prep_time_minutes": 15}) != "order_already_handled" {
		t.Fatal("double accept")
	}
	offer := m(rider.must("GET", "/rider/offers/current", nil))
	if m(offer["job"])["id"] != jid {
		t.Fatal("offer for wrong job")
	}
	j := m(rider.must("POST", "/rider/offers/"+offer["id"].(string)+"/accept", nil))
	if j["status"] != "rider_assigned" || !hasAction(j, "arrived_pickup") {
		t.Fatalf("assigned: %v %v", j["status"], j["allowed_actions"])
	}
	j = step(t, rider, jid, "arrived_pickup", nil)
	if hasAction(j, "picked_up") {
		t.Fatal("food not ready yet: picked_up must not be allowed")
	}
	if rider.errCode("POST", "/rider/jobs/"+jid+"/status", map[string]any{"status": "picked_up"}) != "invalid_status_transition" {
		t.Fatal("expected invalid transition")
	}
	merchant.must("POST", "/merchant/orders/"+order["id"].(string)+"/ready", nil)
	step(t, rider, jid, "picked_up", nil)
	step(t, rider, jid, "arrived_dropoff", nil)
	if code := rider.errCode("POST", "/rider/jobs/"+jid+"/status", map[string]any{"status": "completed"}); code != "validation_failed" {
		t.Fatalf("proof required, got %s", code)
	}
	u := m(rider.must("POST", "/uploads", map[string]any{"purpose": "proof_of_delivery", "content_type": "image/jpeg"}))
	put(t, u["upload_url"].(string))
	done := step(t, rider, jid, "completed", map[string]any{"proof_key": u["key"]})
	if done["proof_url"] == nil || m(done["payment"])["status"] != "paid" {
		t.Fatalf("completed job: %v", done)
	}
	// customer can rate once; merchant sees completed; rider paid commission
	cj := m(cust.must("GET", "/jobs/"+jid, nil))
	if !hasAction(cj, "rate") {
		t.Fatal("rate should be allowed")
	}
	cust.must("POST", "/jobs/"+jid+"/rate", map[string]any{"rider_rating": 5, "rider_tags": []any{"friendly"}, "merchant_rating": 4})
	if hasAction(m(cust.must("GET", "/jobs/"+jid, nil)), "rate") {
		t.Fatal("rate should disappear after rating")
	}
	if len(merchant.must("GET", "/merchant/orders?status=done", nil).([]any)) != 1 {
		t.Fatal("order should be done")
	}
	txs := rider.must("GET", "/rider/wallet/transactions", nil).([]any)
	if m(txs[0])["type"] != "commission" {
		t.Fatalf("latest tx %v", txs[0])
	}
	today := manilaDate(time.Now())
	rep := m(merchant.must("GET", "/merchant/reports/sales?from="+today+"&to="+today, nil))
	if rep["orders_count"].(float64) != 1 {
		t.Fatalf("sales report %v", rep)
	}
	chat := cust.must("GET", "/jobs/"+jid+"/messages", nil).([]any)
	if len(chat) == 0 {
		t.Fatal("system message expected")
	}
}

func TestOnlinePaymentRideAndPabili(t *testing.T) {
	s, ts := newTestServer(t)
	cust := login(t, ts.URL, "customer", "+639171234567", "Aisha")
	rider := approvedRider(t, s, ts.URL)

	q := m(cust.must("POST", "/quotes", map[string]any{"service": "ride", "pickup": home, "dropoff": capitol}))
	job := m(cust.must("POST", "/jobs", map[string]any{"quote_id": q["id"], "payment_method": "gcash"}))
	if job["status"] != "pending_payment" || m(job["payment"])["checkout_url"] == nil {
		t.Fatalf("online job: %v", job)
	}
	// pay via the dev checkout page
	res, err := http.PostForm(m(job["payment"])["checkout_url"].(string), url.Values{"result": {"paid"}})
	if err != nil || res.StatusCode != 200 {
		t.Fatal("pay page failed")
	}
	j := m(cust.must("GET", "/jobs/"+job["id"].(string), nil))
	if j["status"] != "searching" || m(j["payment"])["status"] != "paid" {
		t.Fatalf("after pay: %v %v", j["status"], j["payment"])
	}
	offer := m(rider.must("GET", "/rider/offers/current", nil))
	rider.must("POST", "/rider/offers/"+offer["id"].(string)+"/decline", map[string]any{"reason": "busy"})
	if rider.must("GET", "/rider/offers/current", nil) != nil {
		t.Fatal("declined rider should not be re-offered immediately")
	}
	cust.must("POST", "/jobs/"+job["id"].(string)+"/cancel", map[string]any{"reason": "changed mind"})
	j = m(cust.must("GET", "/jobs/"+job["id"].(string), nil))
	if j["status"] != "cancelled" || m(j["payment"])["status"] != "refunded" {
		t.Fatalf("cancel: %v %v", j["status"], j["payment"])
	}

	// Pabili: receipt -> customer confirms
	q = m(cust.must("POST", "/quotes", map[string]any{"service": "pabili", "pickup": home, "dropoff": capitol,
		"pabili": map[string]any{"store_name": "Market", "items": []any{map[string]any{"name": "Eggs", "quantity": 12}}, "estimated_item_total_centavos": 30000}}))
	job = m(cust.must("POST", "/jobs", map[string]any{"quote_id": q["id"], "payment_method": "cash"}))
	jid := job["id"].(string)
	s.Tick()
	offer = m(rider.must("GET", "/rider/offers/current", nil))
	rider.must("POST", "/rider/offers/"+offer["id"].(string)+"/accept", nil)
	step(t, rider, jid, "arrived_pickup", nil)
	u := m(rider.must("POST", "/uploads", map[string]any{"purpose": "receipt", "content_type": "image/jpeg"}))
	put(t, u["upload_url"].(string))
	step(t, rider, jid, "items_purchased", map[string]any{"receipt_key": u["key"], "item_total_centavos": 28500})
	cj := m(cust.must("GET", "/jobs/"+jid, nil))
	if !hasAction(cj, "confirm_items") || m(cj["pabili"])["receipt_url"] == nil {
		t.Fatalf("confirm: %v", cj["allowed_actions"])
	}
	if hasAction(m(rider.must("GET", "/rider/jobs/active", nil)), "picked_up") {
		t.Fatal("rider must wait for customer")
	}
	cust.must("POST", "/jobs/"+jid+"/confirm-items", map[string]any{"approved": true})
	if m(rider.must("GET", "/rider/jobs/active", nil))["status"] != "picked_up" {
		t.Fatal("should be picked_up after confirm")
	}
	_ = fmt.Sprint()
}

func TestAuthTokensAndErrors(t *testing.T) {
	_, ts := newTestServer(t)
	c := &client{t: t, base: ts.URL, app: "customer"}
	if c.errCode("POST", "/auth/otp/request", map[string]any{"phone": "+6312"}) != "validation_failed" {
		t.Fatal("phone validation")
	}
	c.must("POST", "/auth/otp/request", map[string]any{"phone": "+639171231111"})
	if c.errCode("POST", "/auth/otp/verify", map[string]any{"phone": "+639171231111", "code": "000000", "app": "customer"}) != "otp_invalid" {
		t.Fatal("otp invalid")
	}
	d := m(c.must("POST", "/auth/otp/verify", map[string]any{"phone": "+639171231111", "code": "123456", "app": "customer"}))
	if d["is_new_user"] != true {
		t.Fatal("new user expected")
	}
	ref := m(c.must("POST", "/auth/refresh", map[string]any{"refresh_token": d["refresh_token"]}))
	if c.errCode("POST", "/auth/refresh", map[string]any{"refresh_token": d["refresh_token"]}) != "unauthorized" {
		t.Fatal("refresh tokens must rotate")
	}
	c.token = ref["access_token"].(string)
	c.must("GET", "/me", nil)
	if c.errCode("POST", "/quotes", map[string]any{"service": "ride", "pickup": map[string]any{"address": "Jolo", "location": map[string]any{"lat": 6.05, "lng": 121}}, "dropoff": home}) != "out_of_service_area" {
		t.Fatal("service area")
	}
	c.token = "bad"
	if c.errCode("GET", "/me", nil) != "unauthorized" {
		t.Fatal("bad token")
	}
}

func hasAction(job map[string]any, a string) bool {
	for _, x := range job["allowed_actions"].([]any) {
		if x == a {
			return true
		}
	}
	return false
}
