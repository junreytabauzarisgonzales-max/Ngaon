package integrations

// Third-party integrations. Each one is enabled by its env keys; when a key is
// missing the backend uses its built-in dev stand-in instead.
//   - Google Maps Platform: Routes API (quotes, ETA, route line), Geocoding
//     (reverse), Places Text Search (search).
//   - Didit: rider identity verification (KYC).
//   - PayMongo: hosted Checkout for GCash / Maya, refunds.
// Network calls are never made while holding the server lock.

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"goapp/backend/internal/config"
	"goapp/backend/internal/domain"
)

var httpc = &http.Client{Timeout: 12 * time.Second}

func b64std(s string) string { return base64.StdEncoding.EncodeToString([]byte(s)) }

func doJSON(ctx context.Context, method, u string, hdr map[string]string, body any, out any) (int, error) {
	var rd io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return 0, err
		}
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, u, rd)
	if err != nil {
		return 0, err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	res, err := httpc.Do(req)
	if err != nil {
		return 0, err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 4<<20))
	if res.StatusCode >= 300 {
		return res.StatusCode, fmt.Errorf("%s %s: HTTP %d: %s", method, u, res.StatusCode, truncate(string(raw), 300))
	}
	if out != nil {
		if err := json.Unmarshal(raw, out); err != nil {
			return res.StatusCode, fmt.Errorf("decode %s: %w", u, err)
		}
	}
	return res.StatusCode, nil
}

func truncate(s string, n int) string {
	if len(s) > n {
		return s[:n] + "…"
	}
	return s
}

// ======================= Google Maps Platform =======================

type MapsConfig = config.MapsConfig

type Maps struct {
	cfg   MapsConfig
	mu    sync.Mutex
	cache map[string]routeCacheEntry
}

type Route struct {
	DistanceM int
	DurationS int
	Polyline  string
}

type routeCacheEntry struct {
	r   Route
	exp time.Time
}

func NewMaps(cfg MapsConfig) *Maps {
	if cfg.TravelMode == "" {
		cfg.TravelMode = "TWO_WHEELER"
	}
	if cfg.RoutesURL == "" {
		cfg.RoutesURL = "https://routes.googleapis.com/directions/v2:computeRoutes"
	}
	if cfg.GeocodeURL == "" {
		cfg.GeocodeURL = "https://maps.googleapis.com/maps/api/geocode/json"
	}
	if cfg.PlacesURL == "" {
		cfg.PlacesURL = "https://places.googleapis.com/v1/places:searchText"
	}
	return &Maps{cfg: cfg, cache: map[string]routeCacheEntry{}}
}

func (m *Maps) Enabled() bool { return m != nil && m.cfg.APIKey != "" }

// Route returns road distance/duration and an encoded polyline. Tries the
// configured travel mode (two-wheeler routing is beta and not available in
// every country), then DRIVE.
func (m *Maps) Route(ctx context.Context, a, b domain.LatLng) (Route, error) {
	if !m.Enabled() {
		return Route{}, errors.New("maps disabled")
	}
	key := fmt.Sprintf("%.4f,%.4f>%.4f,%.4f", a.Lat, a.Lng, b.Lat, b.Lng)
	m.mu.Lock()
	if e, hit := m.cache[key]; hit && time.Now().Before(e.exp) {
		m.mu.Unlock()
		return e.r, nil
	}
	m.mu.Unlock()
	modes := []string{m.cfg.TravelMode}
	if m.cfg.TravelMode != "DRIVE" {
		modes = append(modes, "DRIVE")
	}
	var lastErr error
	for _, mode := range modes {
		r, err := m.computeRoute(ctx, a, b, mode)
		if err == nil {
			m.mu.Lock()
			m.cache[key] = routeCacheEntry{r, time.Now().Add(15 * time.Minute)}
			m.mu.Unlock()
			return r, nil
		}
		lastErr = err
	}
	return Route{}, lastErr
}

func (m *Maps) computeRoute(ctx context.Context, a, b domain.LatLng, mode string) (Route, error) {
	pt := func(p domain.LatLng) map[string]any {
		return map[string]any{"location": map[string]any{"latLng": map[string]any{"latitude": p.Lat, "longitude": p.Lng}}}
	}
	body := map[string]any{"origin": pt(a), "destination": pt(b), "travelMode": mode, "languageCode": "en", "units": "METRIC", "regionCode": "PH"}
	if mode == "DRIVE" || mode == "TWO_WHEELER" {
		body["routingPreference"] = "TRAFFIC_AWARE"
	}
	var out struct {
		Routes []struct {
			DistanceMeters int    `json:"distanceMeters"`
			Duration       string `json:"duration"`
			Polyline       struct {
				EncodedPolyline string `json:"encodedPolyline"`
			} `json:"polyline"`
		} `json:"routes"`
	}
	_, err := doJSON(ctx, "POST", m.cfg.RoutesURL, map[string]string{
		"X-Goog-Api-Key":   m.cfg.APIKey,
		"X-Goog-FieldMask": "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline",
	}, body, &out)
	if err != nil {
		return Route{}, err
	}
	if len(out.Routes) == 0 {
		return Route{}, fmt.Errorf("no %s route", mode)
	}
	rt := out.Routes[0]
	secs, _ := strconv.ParseFloat(strings.TrimSuffix(rt.Duration, "s"), 64)
	return Route{DistanceM: rt.DistanceMeters, DurationS: int(math.Round(secs)), Polyline: rt.Polyline.EncodedPolyline}, nil
}

// Reverse geocodes a point to a readable address.
func (m *Maps) Reverse(ctx context.Context, p domain.LatLng) (string, error) {
	if !m.Enabled() {
		return "", errors.New("maps disabled")
	}
	q := url.Values{"latlng": {fmt.Sprintf("%f,%f", p.Lat, p.Lng)}, "key": {m.cfg.APIKey}, "language": {"en"}, "region": {"ph"}}
	var out struct {
		Status  string `json:"status"`
		Results []struct {
			FormattedAddress string `json:"formatted_address"`
		} `json:"results"`
		ErrorMessage string `json:"error_message"`
	}
	if _, err := doJSON(ctx, "GET", m.cfg.GeocodeURL+"?"+q.Encode(), nil, nil, &out); err != nil {
		return "", err
	}
	if out.Status != "OK" || len(out.Results) == 0 {
		return "", fmt.Errorf("geocode: %s %s", out.Status, out.ErrorMessage)
	}
	return out.Results[0].FormattedAddress, nil
}

// Search finds places near a point (Places API New, Text Search).
func (m *Maps) Search(ctx context.Context, text string, near domain.LatLng) ([]domain.GeoPlace, error) {
	if !m.Enabled() {
		return nil, errors.New("maps disabled")
	}
	body := map[string]any{
		"textQuery": text, "languageCode": "en", "regionCode": "PH", "pageSize": 10,
		"locationBias": map[string]any{"circle": map[string]any{"center": map[string]any{"latitude": near.Lat, "longitude": near.Lng}, "radius": 15000.0}},
	}
	var out struct {
		Places []struct {
			DisplayName struct {
				Text string `json:"text"`
			} `json:"displayName"`
			FormattedAddress string `json:"formattedAddress"`
			Location         *struct {
				Latitude  float64 `json:"latitude"`
				Longitude float64 `json:"longitude"`
			} `json:"location"`
		} `json:"places"`
	}
	_, err := doJSON(ctx, "POST", m.cfg.PlacesURL, map[string]string{
		"X-Goog-Api-Key":   m.cfg.APIKey,
		"X-Goog-FieldMask": "places.displayName,places.formattedAddress,places.location",
	}, body, &out)
	if err != nil {
		return nil, err
	}
	var res []domain.GeoPlace
	for _, p := range out.Places {
		if p.Location == nil {
			continue // pure service-area businesses have no location
		}
		res = append(res, domain.GeoPlace{Name: p.DisplayName.Text, Address: p.FormattedAddress, Location: domain.LatLng{Lat: p.Location.Latitude, Lng: p.Location.Longitude}})
	}
	return res, nil
}

// ============================ Didit KYC ============================

type DiditConfig = config.DiditConfig

type Didit struct{ cfg DiditConfig }

func NewDidit(cfg DiditConfig) *Didit {
	if cfg.BaseURL == "" {
		cfg.BaseURL = "https://verification.didit.me"
	}
	cfg.BaseURL = strings.TrimRight(cfg.BaseURL, "/")
	return &Didit{cfg}
}

func (d *Didit) Enabled() bool { return d != nil && d.cfg.APIKey != "" && d.cfg.WorkflowID != "" }

type DiditSession struct {
	SessionID string `json:"session_id"`
	URL       string `json:"url"`
	Status    string `json:"status"`
}

// CreateSession starts (or, for the same vendor_data, resumes) a verification.
func (d *Didit) CreateSession(ctx context.Context, vendorData, callback, phone string) (DiditSession, error) {
	body := map[string]any{"workflow_id": d.cfg.WorkflowID, "vendor_data": vendorData, "language": "en", "callback_method": "both"}
	if callback != "" {
		body["callback"] = callback
	}
	if phone != "" {
		body["contact_details"] = map[string]any{"phone": phone}
	}
	var out DiditSession
	_, err := doJSON(ctx, "POST", d.cfg.BaseURL+"/v3/session/", map[string]string{"x-api-key": d.cfg.APIKey}, body, &out)
	return out, err
}

// Decision returns the session status ("Approved", "Declined", "In Review", …).
func (d *Didit) Decision(ctx context.Context, sessionID string) (string, error) {
	var out struct {
		Status string `json:"status"`
	}
	_, err := doJSON(ctx, "GET", d.cfg.BaseURL+"/v3/session/"+url.PathEscape(sessionID)+"/decision/", map[string]string{"x-api-key": d.cfg.APIKey}, nil, &out)
	return out.Status, err
}

// VerifyWebhook checks X-Signature (HMAC-SHA256 hex of the raw body) and the
// X-Timestamp freshness window (5 minutes).
func (d *Didit) VerifyWebhook(raw []byte, sig, sigPrev, ts string) bool {
	if d.cfg.WebhookSecret == "" {
		return false
	}
	t, err := strconv.ParseInt(ts, 10, 64)
	if err != nil || math.Abs(float64(time.Now().Unix()-t)) > 300 {
		return false
	}
	mac := hmac.New(sha256.New, []byte(d.cfg.WebhookSecret))
	mac.Write(raw)
	want := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(strings.ToLower(sig)), []byte(want)) || (sigPrev != "" && hmac.Equal([]byte(strings.ToLower(sigPrev)), []byte(want)))
}

// KycFromDidit maps Didit statuses onto the contract's kyc_status values.
func KycFromDidit(status string) string {
	switch strings.ToLower(status) {
	case "approved":
		return "approved"
	case "declined":
		return "declined"
	case "in review", "resubmitted":
		return "in_review"
	case "expired", "kyc expired", "abandoned":
		return "expired"
	case "not started":
		return "not_started"
	default:
		return "in_progress"
	}
}

// ============================ PayMongo ============================

type PayMongoConfig = config.PayMongoConfig

type PayMongo struct{ cfg PayMongoConfig }

func NewPayMongo(cfg PayMongoConfig) *PayMongo {
	if cfg.BaseURL == "" {
		cfg.BaseURL = "https://api.paymongo.com"
	}
	cfg.BaseURL = strings.TrimRight(cfg.BaseURL, "/")
	return &PayMongo{cfg}
}

func (p *PayMongo) Enabled() bool { return p != nil && p.cfg.SecretKey != "" }

func (p *PayMongo) auth() map[string]string {
	return map[string]string{"Authorization": "Basic " + b64std(p.cfg.SecretKey+":")}
}

func paymongoMethod(m string) string {
	if m == "maya" {
		return "paymaya"
	}
	return m // gcash
}

type Checkout struct {
	ID  string
	URL string
}

func (p *PayMongo) CreateCheckout(ctx context.Context, ref, name string, amount int, method, successURL, cancelURL string, meta map[string]string) (Checkout, error) {
	body := map[string]any{"data": map[string]any{"attributes": map[string]any{
		"line_items":           []any{map[string]any{"name": name, "amount": amount, "currency": "PHP", "quantity": 1}},
		"payment_method_types": []string{paymongoMethod(method)},
		"success_url":          successURL,
		"cancel_url":           cancelURL,
		"reference_number":     ref,
		"description":          name,
		"send_email_receipt":   false,
		"show_description":     true,
		"show_line_items":      true,
		"metadata":             meta,
	}}}
	var out struct {
		Data struct {
			ID         string `json:"id"`
			Attributes struct {
				CheckoutURL string `json:"checkout_url"`
			} `json:"attributes"`
		} `json:"data"`
	}
	if _, err := doJSON(ctx, "POST", p.cfg.BaseURL+"/v1/checkout_sessions", p.auth(), body, &out); err != nil {
		return Checkout{}, err
	}
	return Checkout{ID: out.Data.ID, URL: out.Data.Attributes.CheckoutURL}, nil
}

type CheckoutStatus struct {
	Paid      bool
	PaymentID string
	Reference string
}

func checkoutStatusFrom(attrs json.RawMessage) CheckoutStatus {
	var a struct {
		ReferenceNumber string `json:"reference_number"`
		Payments        []struct {
			ID         string `json:"id"`
			Attributes struct {
				Status string `json:"status"`
			} `json:"attributes"`
		} `json:"payments"`
		PaymentIntent *struct {
			Attributes struct {
				Status string `json:"status"`
			} `json:"attributes"`
		} `json:"payment_intent"`
	}
	_ = json.Unmarshal(attrs, &a)
	st := CheckoutStatus{Reference: a.ReferenceNumber}
	for _, pm := range a.Payments {
		if pm.Attributes.Status == "paid" {
			st.Paid, st.PaymentID = true, pm.ID
		}
	}
	if !st.Paid && a.PaymentIntent != nil && a.PaymentIntent.Attributes.Status == "succeeded" {
		st.Paid = true
	}
	return st
}

func (p *PayMongo) RetrieveCheckout(ctx context.Context, id string) (CheckoutStatus, error) {
	var out struct {
		Data struct {
			Attributes json.RawMessage `json:"attributes"`
		} `json:"data"`
	}
	if _, err := doJSON(ctx, "GET", p.cfg.BaseURL+"/v1/checkout_sessions/"+url.PathEscape(id), p.auth(), nil, &out); err != nil {
		return CheckoutStatus{}, err
	}
	return checkoutStatusFrom(out.Data.Attributes), nil
}

func (p *PayMongo) Refund(ctx context.Context, paymentID string, amount int, notes string) error {
	body := map[string]any{"data": map[string]any{"attributes": map[string]any{
		"amount": amount, "payment_id": paymentID, "reason": "requested_by_customer", "notes": truncate(notes, 250),
	}}}
	_, err := doJSON(ctx, "POST", p.cfg.BaseURL+"/v1/refunds", p.auth(), body, nil)
	return err
}

func (p *PayMongo) VerifyWebhook(raw []byte, header string) bool {
	if p.cfg.WebhookSecret == "" || header == "" {
		return false
	}
	sign := func(msg []byte) string {
		mac := hmac.New(sha256.New, []byte(p.cfg.WebhookSecret))
		mac.Write(msg)
		return hex.EncodeToString(mac.Sum(nil))
	}
	if !strings.Contains(header, "=") {
		return hmac.Equal([]byte(header), []byte(sign(raw)))
	}
	parts := map[string]string{}
	for _, kv := range strings.Split(header, ",") {
		if k, v, found := strings.Cut(strings.TrimSpace(kv), "="); found {
			parts[k] = v
		}
	}
	want := sign(append([]byte(parts["t"]+"."), raw...))
	return hmac.Equal([]byte(parts["te"]), []byte(want)) || hmac.Equal([]byte(parts["li"]), []byte(want))
}

func LogIntegration(name string, err error) {
	if err != nil {
		log.Printf("[%s] %v", name, err)
	}
}
