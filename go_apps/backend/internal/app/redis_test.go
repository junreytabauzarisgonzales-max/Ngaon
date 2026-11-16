package app

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"
	"goapp/backend/internal/service"
)

func TestSecurityHardening(t *testing.T) {
	s, ts := newTestServer(t)
	defer s.Close()

	// 1. Security Headers & Rate Limit Headers
	res, err := http.Get(ts.URL + "/healthz")
	if err != nil {
		t.Fatalf("healthz failed: %v", err)
	}
	res.Body.Close()
	if res.Header.Get("X-Content-Type-Options") != "nosniff" {
		t.Errorf("missing X-Content-Type-Options: nosniff, got %q", res.Header.Get("X-Content-Type-Options"))
	}
	if res.Header.Get("X-Frame-Options") != "DENY" {
		t.Errorf("missing X-Frame-Options: DENY, got %q", res.Header.Get("X-Frame-Options"))
	}
	if res.Header.Get("Referrer-Policy") != "no-referrer" {
		t.Errorf("missing Referrer-Policy: no-referrer, got %q", res.Header.Get("Referrer-Policy"))
	}

	// 2. OTP Hashing at Rest, Brute-Force Lockout (5 attempts), and Request Rate Limit (5 per 10m)
	anon := &client{t: t, base: ts.URL, app: "customer"}
	phone := "+639178889900"
	anon.must("POST", "/auth/otp/request", map[string]any{"phone": phone})

	s.svc.Lock()
	storedOTP := s.st.OTPs[phone]
	if storedOTP == nil {
		s.svc.Unlock()
		t.Fatal("expected OTP record in state")
	}
	if len(storedOTP.Code) == 6 {
		s.svc.Unlock()
		t.Fatalf("OTP code must be HMAC-hashed at rest, got 6-char plaintext: %s", storedOTP.Code)
	}
	s.svc.Unlock()

	// 5 wrong attempts return otp_invalid, 6th returns rate_limited (429)
	for i := 1; i <= 5; i++ {
		if code := anon.errCode("POST", "/auth/otp/verify", map[string]any{"phone": phone, "code": "000000", "app": "customer"}); code != "otp_invalid" {
			t.Fatalf("attempt %d: expected otp_invalid, got %s", i, code)
		}
	}
	if code := anon.errCode("POST", "/auth/otp/verify", map[string]any{"phone": phone, "code": "000000", "app": "customer"}); code != "rate_limited" {
		t.Fatalf("attempt 6: expected rate_limited, got %s", code)
	}
	// Even DEV_OTP_CODE must be rejected once the phone is locked out after 5 failed attempts
	if code := anon.errCode("POST", "/auth/otp/verify", map[string]any{"phone": phone, "code": "123456", "app": "customer"}); code != "rate_limited" {
		t.Fatalf("attempt 7 with DEV_OTP_CODE: expected rate_limited lockout, got %s", code)
	}

	// Request 4 more OTPs (total 5 in 10 minutes), 6th request must be rate_limited (429)
	for i := 2; i <= 5; i++ {
		anon.must("POST", "/auth/otp/request", map[string]any{"phone": phone})
	}
	if code := anon.errCode("POST", "/auth/otp/request", map[string]any{"phone": phone}); code != "rate_limited" {
		t.Fatalf("expected 6th OTP request to be rate_limited, got %s", code)
	}

	// 3. Refresh Token Hashing at Rest & Access Token Revocation on Logout
	cust := login(t, ts.URL, "customer", "+639175556677", "Security Tester")
	rawTok := cust.token

	// Verify raw refresh tokens are never stored as plaintext keys in St.Refresh
	d := m(anon.must("POST", "/auth/otp/verify", map[string]any{"phone": "+639175556677", "code": "123456", "app": "customer"}))
	rawRefresh := d["refresh_token"].(string)
	s.svc.Lock()
	if _, rawExists := s.st.Refresh[rawRefresh]; rawExists {
		s.svc.Unlock()
		t.Fatal("raw refresh token must not be stored unhashed in St.Refresh")
	}
	if _, hashExists := s.st.Refresh[service.HashToken(rawRefresh)]; !hashExists {
		s.svc.Unlock()
		t.Fatal("expected SHA-256 hashed refresh token in St.Refresh")
	}
	s.svc.Unlock()

	// Logout must immediately revoke the current access token AND refresh token
	cust.token = d["access_token"].(string)
	cust.must("GET", "/me", nil)
	cust.must("POST", "/auth/logout", map[string]any{"refresh_token": rawRefresh})
	if code := cust.errCode("GET", "/me", nil); code != "unauthorized" {
		t.Fatalf("expected logged-out access token to be unauthorized, got %s", code)
	}
	if code := cust.errCode("POST", "/auth/refresh", map[string]any{"refresh_token": rawRefresh}); code != "unauthorized" {
		t.Fatalf("expected logged-out refresh token to be unauthorized, got %s", code)
	}

	// 4. Account Deletion revokes active tokens and prevents nil-pointer panics
	cust.token = rawTok
	cust.must("DELETE", "/me", nil)
	if code := cust.errCode("GET", "/me", nil); code != "unauthorized" {
		t.Fatalf("expected deleted user access token to be unauthorized, got %s", code)
	}
	if code := cust.errCode("PATCH", "/me", map[string]any{"name": "Ghost"}); code != "unauthorized" {
		t.Fatalf("expected deleted user PATCH /me to be unauthorized, got %s", code)
	}

	// 5. JWT Algorithm Confusion Attack Rejection (alg: none)
	noneHdr := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"none","typ":"JWT"}`))
	noneBody := base64.RawURLEncoding.EncodeToString([]byte(`{"sub":"admin","app":"customer","exp":9999999999}`))
	cust.token = noneHdr + "." + noneBody + "."
	if code := cust.errCode("GET", "/me", nil); code != "unauthorized" {
		t.Fatalf("alg:none token must be rejected, got %s", code)
	}

	// 6. Upload Security: Reject non-JPEG payload & tampered signature
	rider := login(t, ts.URL, "rider", "+639187778899", "Upload Tester")
	if code := rider.errCode("POST", "/rider/location", map[string]any{"location": map[string]any{"lat": 999.0, "lng": 999.0}}); code != "validation_failed" {
		t.Fatalf("expected invalid rider coordinates to be rejected with validation_failed, got %s", code)
	}
	up := m(rider.must("POST", "/uploads", map[string]any{"purpose": "rider_selfie", "content_type": "image/jpeg"}))
	uploadURL := up["upload_url"].(string)

	// HTML/script payload disguised as upload must fail with 415 Unsupported Media Type
	badReq, _ := http.NewRequest("PUT", uploadURL, strings.NewReader("<html><script>alert(1)</script></html>"))
	badReq.Header.Set("Content-Type", "image/jpeg")
	badRes, err := http.DefaultClient.Do(badReq)
	if err != nil {
		t.Fatal(err)
	}
	badRes.Body.Close()
	if badRes.StatusCode != http.StatusUnsupportedMediaType {
		t.Fatalf("expected 415 for non-JPEG upload, got %d", badRes.StatusCode)
	}

	// Valid JPEG magic bytes succeed
	put(t, uploadURL)

	// Verify served file has nosniff and CSP headers
	fileRes, err := http.Get(ts.URL + "/files/" + up["key"].(string))
	if err != nil {
		t.Fatal(err)
	}
	fileRes.Body.Close()
	if fileRes.StatusCode != 200 || fileRes.Header.Get("X-Content-Type-Options") != "nosniff" || fileRes.Header.Get("Content-Security-Policy") != "default-src 'none'" {
		t.Fatalf("unexpected file security headers: status=%d, headers=%v", fileRes.StatusCode, fileRes.Header)
	}

	// 7. Admin Endpoint Constant-Time Auth Check
	admRes, _ := http.Get(ts.URL + "/admin?token=wrong")
	if admRes.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 on wrong admin token, got %d", admRes.StatusCode)
	}
	admOK, _ := http.Get(ts.URL + "/admin?token=adm")
	if admOK.StatusCode != http.StatusOK {
		t.Fatalf("expected 200 on valid admin token, got %d", admOK.StatusCode)
	}

	// 8. Per-IP Rate Limiter Enforcement
	rlServer, err := NewServer(Config{
		DataDir:             t.TempDir(),
		JWTSecret:           []byte("rl-secret"),
		DevOTPCode:          "123456",
		RateLimitPerMin:     5,
		AuthRateLimitPerMin: 2,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer rlServer.Close()
	rlTS := httptest.NewServer(rlServer.Routes())
	defer rlTS.Close()

	rlClient := &client{t: t, base: rlTS.URL, app: "customer"}
	rlClient.must("POST", "/auth/otp/request", map[string]any{"phone": "+639170000001"})
	rlClient.must("POST", "/auth/otp/request", map[string]any{"phone": "+639170000002"})
	if code := rlClient.errCode("POST", "/auth/otp/request", map[string]any{"phone": "+639170000003"}); code != "rate_limited" {
		t.Fatalf("expected auth IP rate limit on 3rd request, got %s", code)
	}
	// Spoofed X-Forwarded-For must be ignored when TrustedProxies is not configured
	if code, _ := rlClient.do("POST", "/auth/otp/request", map[string]any{"phone": "+639170000004"}, "X-Forwarded-For", "203.0.113.55"); code != http.StatusTooManyRequests {
		t.Fatalf("expected spoofed X-Forwarded-For to be ignored when TrustedProxies is empty, got status %d", code)
	}

	// When TrustedProxies is configured, X-Forwarded-For isolates rate limits per forwarded client IP
	tpServer, err := NewServer(Config{
		DataDir:             t.TempDir(),
		JWTSecret:           []byte("tp-secret"),
		DevOTPCode:          "123456",
		TrustedProxies:      "127.0.0.1/32,::1/128",
		RateLimitPerMin:     5,
		AuthRateLimitPerMin: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer tpServer.Close()
	tpTS := httptest.NewServer(tpServer.Routes())
	defer tpTS.Close()
	tpClient := &client{t: t, base: tpTS.URL, app: "customer"}
	tpClient.must("POST", "/auth/otp/request", map[string]any{"phone": "+639170000011"}, "X-Forwarded-For", "198.51.100.1")
	if code, _ := tpClient.do("POST", "/auth/otp/request", map[string]any{"phone": "+639170000012"}, "X-Forwarded-For", "198.51.100.1"); code != http.StatusTooManyRequests {
		t.Fatalf("expected 429 for second request from 198.51.100.1, got %d", code)
	}
	// Different client IP behind trusted proxy succeeds
	tpClient.must("POST", "/auth/otp/request", map[string]any{"phone": "+639170000013"}, "X-Forwarded-For", "198.51.100.2")

	// 9. Concurrent Save() and State Mutations Race-Safety Test
	var wg sync.WaitGroup
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			for j := 0; j < 10; j++ {
				rider.must("POST", "/rider/location", map[string]any{"location": map[string]any{"lat": 5.029, "lng": 119.772}})
				s.Save()
			}
		}(i)
	}
	wg.Wait()
}

func TestRedisIntegration(t *testing.T) {
	redisURL := os.Getenv("TEST_REDIS_URL")
	if redisURL == "" {
		t.Skip("TEST_REDIS_URL not set; skipping Redis integration test")
	}

	dataDir := t.TempDir()
	cfg := Config{
		RedisURL:           redisURL,
		DataDir:            dataDir,
		JWTSecret:          []byte("redis-test-jwt-secret"),
		DevOTPCode:         "123456",
		AutoApproveSeconds: 1,
		RiderStartBalance:  20000,
		AdminToken:         "redis-admin",
		MaxDispatchM:       15000,
	}

	s1, err := NewServer(cfg)
	if err != nil {
		t.Fatalf("NewServer with Redis failed: %v", err)
	}
	defer s1.Close()

	ctx := context.Background()
	// Clean any prior test keys in Redis
	keys, _ := s1.redis.Client().Keys(ctx, "goapp:*").Result()
	if len(keys) > 0 {
		_ = s1.redis.Client().Del(ctx, keys...).Err()
	}

	ts1 := httptest.NewServer(s1.Routes())
	s1.cfg.PublicURL = ts1.URL
	defer ts1.Close()

	// 1. Healthz checks Redis connectivity
	hRes, err := http.Get(ts1.URL + "/healthz")
	if err != nil || hRes.StatusCode != 200 {
		t.Fatalf("healthz with Redis failed: %v %v", err, hRes)
	}
	hRes.Body.Close()

	// 2. OTP stored hashed in Redis & verified via Redis
	c1 := &client{t: t, base: ts1.URL, app: "customer"}
	phone := "+639171112233"
	c1.must("POST", "/auth/otp/request", map[string]any{"phone": phone})

	codeHash, attempts, exists, err := s1.redis.GetOTP(ctx, phone)
	if err != nil || !exists || codeHash == "" || attempts != 0 {
		t.Fatalf("expected OTP in Redis, got exists=%v hash=%q attempts=%d err=%v", exists, codeHash, attempts, err)
	}
	if len(codeHash) == 6 {
		t.Fatalf("OTP in Redis must be HMAC-hashed, got %q", codeHash)
	}

	// Wrong code increments Redis attempt counter
	if c1.errCode("POST", "/auth/otp/verify", map[string]any{"phone": phone, "code": "999999", "app": "customer"}) != "otp_invalid" {
		t.Fatal("expected otp_invalid")
	}
	_, attemptsAfter, _, _ := s1.redis.GetOTP(ctx, phone)
	if attemptsAfter != 1 {
		t.Fatalf("expected 1 attempt in Redis, got %d", attemptsAfter)
	}

	// Valid verification deletes OTP from Redis and stores hashed refresh token in Redis
	authData := m(c1.must("POST", "/auth/otp/verify", map[string]any{"phone": phone, "code": "123456", "app": "customer"}))
	c1.token = authData["access_token"].(string)
	rawRefresh := authData["refresh_token"].(string)
	c1.must("PATCH", "/me", map[string]any{"name": "Redis Customer"})

	_, _, stillExists, _ := s1.redis.GetOTP(ctx, phone)
	if stillExists {
		t.Fatal("OTP should be deleted from Redis after successful verification")
	}

	rt, rtFound, err := s1.redis.GetRefreshToken(ctx, service.HashToken(rawRefresh))
	if err != nil || !rtFound || rt.App != "customer" {
		t.Fatalf("expected hashed refresh token in Redis, got found=%v rt=%+v err=%v", rtFound, rt, err)
	}

	// 3. Merchant catalog caching & invalidation in Redis
	merchant := login(t, ts1.URL, "merchant", "+639193334444", "Mering")
	acct := m(merchant.must("GET", "/merchant/me", nil))
	mid := m(acct["merchant"])["id"].(string)

	// First GET /merchants/{id} populates Redis cache
	_ = m(c1.must("GET", "/merchants/"+mid, nil))
	cachedMerch, hit, err := s1.redis.GetCachedMerchant(ctx, mid)
	if err != nil || !hit || cachedMerch == nil || cachedMerch.ID != mid {
		t.Fatalf("expected merchant %s cached in Redis, got hit=%v err=%v", mid, hit, err)
	}

	// Updating store invalidates Redis cache
	merchant.must("PATCH", "/merchant/store", map[string]any{"prep_time_minutes": 20})
	_, hitAfterPatch, _ := s1.redis.GetCachedMerchant(ctx, mid)
	if hitAfterPatch {
		t.Fatal("expected merchant cache to be invalidated in Redis after PATCH /merchant/store")
	}

	// 4. Quotes, Jobs, Idempotency, Rider Geospatial Index, and Offers in Redis
	rider := approvedRider(t, s1, ts1.URL)
	riderMe := m(rider.must("GET", "/me", nil))
	riderUID := riderMe["id"].(string)

	// Rider went online at (5.029, 119.772); verify Redis Geospatial index has the rider
	nearby, err := s1.redis.NearbyRiders(ctx, LatLng{Lat: 5.0251, Lng: 119.7769}, 5000)
	if err != nil || len(nearby) == 0 || nearby[0].UserID != riderUID {
		t.Fatalf("expected rider in Redis GEOSEARCH, got nearby=%+v err=%v", nearby, err)
	}

	// Create Quote -> verify stored in Redis
	q := m(c1.must("POST", "/quotes", map[string]any{"service": "ride", "pickup": home, "dropoff": capitol}))
	qid := q["id"].(string)
	rq, qFound, err := s1.redis.GetQuote(ctx, qid)
	if err != nil || !qFound || rq == nil || rq.Request == nil {
		t.Fatalf("expected quote %s in Redis with Request metadata, got found=%v err=%v", qid, qFound, err)
	}

	// Evict quote from in-memory map to prove createJob loads it from Redis!
	s1.svc.Lock()
	delete(s1.st.Quotes, qid)
	s1.svc.Unlock()

	job := m(c1.must("POST", "/jobs", map[string]any{"quote_id": qid, "payment_method": "cash"}, "Idempotency-Key", "redis-idem-1"))
	jid := job["id"].(string)

	// Quote must be deleted from Redis once consumed
	if _, qStillThere, _ := s1.redis.GetQuote(ctx, qid); qStillThere {
		t.Fatal("consumed quote must be deleted from Redis")
	}

	// Idempotency key must be stored in Redis
	idemVal, idemFound, err := s1.redis.GetIdempotency(ctx, authData["user"].(map[string]any)["id"].(string)+":redis-idem-1")
	if err != nil || !idemFound || idemVal != jid {
		t.Fatalf("expected idempotency key in Redis -> %s, got %q (found=%v, err=%v)", jid, idemVal, idemFound, err)
	}

	// Dispatch offer must be stored in Redis
	rOffer, offerFound, err := s1.redis.GetRiderOffer(ctx, riderUID)
	if err != nil || !offerFound || rOffer == nil || rOffer.JobID != jid {
		t.Fatalf("expected rider offer in Redis for job %s, got found=%v offer=%+v err=%v", jid, offerFound, rOffer, err)
	}

	// Accept offer -> offer deleted from Redis
	rider.must("POST", "/rider/offers/"+rOffer.ID+"/accept", nil)
	if _, offerStillThere, _ := s1.redis.GetRiderOffer(ctx, riderUID); offerStillThere {
		t.Fatal("accepted offer must be removed from Redis")
	}

	// 5. Cross-Instance Token Revocation via Redis
	s1.Save()
	s2, err := NewServer(cfg)
	if err != nil {
		t.Fatalf("second NewServer failed: %v", err)
	}
	defer s2.Close()
	ts2 := httptest.NewServer(s2.Routes())
	defer ts2.Close()

	// Customer logs out on instance 1 -> token is blacklisted in Redis -> instance 2 immediately rejects it
	c1.must("POST", "/auth/logout", map[string]any{"refresh_token": rawRefresh})
	c2 := &client{t: t, base: ts2.URL, app: "customer", token: c1.token}
	if code := c2.errCode("GET", "/me", nil); code != "unauthorized" {
		t.Fatalf("expected token revoked on s1 to be rejected on s2 via Redis blacklist, got %s", code)
	}
	// Refresh token revoked on instance 1 must ALSO be rejected on instance 2 (and not resurrected by s2.Save())
	if code := c2.errCode("POST", "/auth/refresh", map[string]any{"refresh_token": rawRefresh}); code != "unauthorized" {
		t.Fatalf("expected refresh token revoked on s1 to be rejected on s2, got %s", code)
	}
	s2.dirty = true
	s2.Save()
	if code := c2.errCode("POST", "/auth/refresh", map[string]any{"refresh_token": rawRefresh}); code != "unauthorized" {
		t.Fatalf("expected revoked refresh token not to be resurrected after s2.Save(), got %s", code)
	}

	// 6. Cross-Instance Live User Resolution, WebSocket Pub/Sub Fan-out, and Account Deletion
	liveUserS1 := login(t, ts1.URL, "customer", "+639174445566", "Cross Instance User")
	liveUserS2 := &client{t: t, base: ts2.URL, app: "customer", token: liveUserS1.token}
	meOnS2 := m(liveUserS2.must("GET", "/me", nil))
	liveUID := meOnS2["id"].(string)
	if meOnS2["name"] != "Cross Instance User" {
		t.Fatalf("expected cross-instance user profile on s2, got %v", meOnS2)
	}

	// Connect WebSocket to Instance 2 (ts2) and emit event from Instance 1 (s1)
	wsURL := "ws" + strings.TrimPrefix(ts2.URL, "http") + "/ws?token=" + liveUserS1.token
	wsCtx, wsCancel := context.WithTimeout(ctx, 5*time.Second)
	defer wsCancel()
	wsConn, _, err := websocket.Dial(wsCtx, wsURL, nil)
	if err != nil {
		t.Fatalf("websocket dial to ts2 failed: %v", err)
	}
	defer wsConn.CloseNow()

	s1.svc.Lock()
	s1.svc.Emit(liveUID, "customer", "job.updated", map[string]any{"job_id": jid, "status": "completed"})
	s1.svc.Unlock()

	_, msgBytes, err := wsConn.Read(wsCtx)
	if err != nil {
		t.Fatalf("failed to read cross-instance WS event on ts2: %v", err)
	}
	var wsFrame map[string]any
	if err := json.Unmarshal(msgBytes, &wsFrame); err != nil || wsFrame["type"] != "job.updated" {
		t.Fatalf("unexpected WS frame on ts2: %s (err=%v)", string(msgBytes), err)
	}
	_ = wsConn.Close(websocket.StatusNormalClosure, "done")

	// Delete user on s1 -> s2 must immediately reject the user's token
	liveUserS1.must("DELETE", "/me", nil)
	if code := liveUserS2.errCode("GET", "/me", nil); code != "unauthorized" {
		t.Fatalf("expected user deleted on s1 to be unauthorized on s2, got %s", code)
	}
}
