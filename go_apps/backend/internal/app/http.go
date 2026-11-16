package app

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"runtime/debug"
	"strconv"
	"strings"
	"time"
)

// ---------- errors ----------

type APIError struct {
	Status  int               `json:"-"`
	Code    string            `json:"code"`
	Message string            `json:"message"`
	Fields  map[string]string `json:"fields,omitempty"`
}

func (e *APIError) Error() string { return e.Code + ": " + e.Message }

func apiErr(status int, code, msg string) *APIError {
	return &APIError{Status: status, Code: code, Message: msg}
}

func fieldErr(field, problem, msg string) *APIError {
	return &APIError{Status: 422, Code: "validation_failed", Message: msg, Fields: map[string]string{field: problem}}
}

var (
	errUnauthorized = apiErr(401, "unauthorized", "Please log in")
	errForbidden    = apiErr(403, "forbidden", "Not allowed")
	errNotFound     = apiErr(404, "not_found", "Not found")
)

// ---------- envelope ----------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func ok(w http.ResponseWriter, data any) {
	writeJSON(w, 200, map[string]any{"data": data, "meta": map[string]any{}})
}

func okEmpty(w http.ResponseWriter) { ok(w, map[string]any{}) }

func okPage[T any](w http.ResponseWriter, items []T, next *string) {
	if items == nil {
		items = []T{}
	}
	writeJSON(w, 200, map[string]any{"data": items, "meta": map[string]any{"next_cursor": next}})
}

func fail(w http.ResponseWriter, err error) {
	var ae *APIError
	if !errors.As(err, &ae) {
		log.Printf("internal error: %v", err)
		ae = apiErr(500, "server_error", "Something went wrong")
	}
	writeJSON(w, ae.Status, map[string]any{"error": ae})
}

// paginate slices with an integer cursor.
func paginate[T any](all []T, r *http.Request, def int) ([]T, *string) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = def
	}
	start, _ := strconv.Atoi(r.URL.Query().Get("cursor"))
	if start < 0 || start > len(all) {
		start = len(all)
	}
	end := min(start+limit, len(all))
	var next *string
	if end < len(all) {
		next = strp(strconv.Itoa(end))
	}
	return all[start:end], next
}

func decode(r *http.Request, v any) error {
	if r.Body == nil {
		return nil
	}
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	if err := dec.Decode(v); err != nil && err.Error() != "EOF" {
		return apiErr(400, "validation_failed", "Invalid JSON body")
	}
	return nil
}

// ---------- JWT (HS256) ----------

type Claims struct {
	Sub string `json:"sub"`
	App string `json:"app"`
	Exp int64  `json:"exp"`
}

var b64 = base64.RawURLEncoding

func (s *Server) signJWT(c Claims) string {
	head := b64.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	body, _ := json.Marshal(c)
	payload := head + "." + b64.EncodeToString(body)
	mac := hmac.New(sha256.New, s.cfg.JWTSecret)
	mac.Write([]byte(payload))
	return payload + "." + b64.EncodeToString(mac.Sum(nil))
}

// parseJWT returns claims; expired=true when the signature is valid but exp passed.
func (s *Server) parseJWT(tok string) (c Claims, expired bool, err error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return c, false, errUnauthorized
	}
	mac := hmac.New(sha256.New, s.cfg.JWTSecret)
	mac.Write([]byte(parts[0] + "." + parts[1]))
	sig, err := b64.DecodeString(parts[2])
	if err != nil || !hmac.Equal(sig, mac.Sum(nil)) {
		return c, false, errUnauthorized
	}
	body, err := b64.DecodeString(parts[1])
	if err != nil || json.Unmarshal(body, &c) != nil {
		return c, false, errUnauthorized
	}
	if time.Now().Unix() >= c.Exp {
		return c, true, nil
	}
	return c, false, nil
}

const accessTTL = 15 * time.Minute
const refreshTTL = 30 * 24 * time.Hour

func (s *Server) issueTokens(userID, app string) (string, string) {
	access := s.signJWT(Claims{Sub: userID, App: app, Exp: time.Now().Add(accessTTL).Unix()})
	refresh := randToken(32)
	s.st.Refresh[refresh] = RefreshToken{UserID: userID, App: app, Expires: time.Now().Add(refreshTTL)}
	s.touch()
	return access, refresh
}

// ---------- middleware ----------

type ctxKey int

const claimsKey ctxKey = 1

func claimsOf(r *http.Request) Claims { c, _ := r.Context().Value(claimsKey).(Claims); return c }

type handler func(w http.ResponseWriter, r *http.Request) error

// pub wraps a public handler (no auth).
func (s *Server) pub(h handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			fail(w, err)
		}
	}
}

// authed requires a valid access token; `401 token_expired` when expired.
func (s *Server) authed(h handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		c, expired, err := s.parseJWT(tok)
		if err != nil {
			fail(w, errUnauthorized)
			return
		}
		if expired {
			fail(w, apiErr(401, "token_expired", "Access token expired"))
			return
		}
		s.lock()
		_, exists := s.st.Users[c.Sub]
		s.unlock()
		if !exists {
			fail(w, errUnauthorized)
			return
		}
		if err := h(w, r.WithContext(context.WithValue(r.Context(), claimsKey, c))); err != nil {
			fail(w, err)
		}
	}
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) { r.status = code; r.ResponseWriter.WriteHeader(code) }

// Unwrap lets the websocket library reach the hijacker.
func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: 200}
		defer func() {
			if p := recover(); p != nil {
				log.Printf("panic: %v\n%s", p, debug.Stack())
				fail(w, errors.New("panic"))
			}
			if r.URL.Path != "/healthz" {
				log.Printf("%s %s %d %s [%s]", r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond), r.Header.Get("X-App"))
			}
		}()
		next.ServeHTTP(rec, r)
	})
}

// Routes wires every endpoint in API_CONTRACT.md plus dev pages.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	p, a := s.pub, s.authed
	v := "/api/v1"

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	mux.HandleFunc("GET /{$}", s.indexPage)

	// auth
	mux.HandleFunc("POST "+v+"/auth/otp/request", p(s.otpRequest))
	mux.HandleFunc("POST "+v+"/auth/otp/verify", p(s.otpVerify))
	mux.HandleFunc("POST "+v+"/auth/refresh", p(s.refresh))
	mux.HandleFunc("POST "+v+"/auth/logout", p(s.logout))
	mux.HandleFunc("GET "+v+"/me", a(s.getMe))
	mux.HandleFunc("PATCH "+v+"/me", a(s.patchMe))
	mux.HandleFunc("DELETE "+v+"/me", a(s.deleteMe))
	mux.HandleFunc("POST "+v+"/me/devices", a(s.registerDevice))

	// places & geo
	mux.HandleFunc("GET "+v+"/me/places", a(s.listPlaces))
	mux.HandleFunc("POST "+v+"/me/places", a(s.addPlace))
	mux.HandleFunc("DELETE "+v+"/me/places/{id}", a(s.deletePlace))
	mux.HandleFunc("GET "+v+"/geo/reverse", a(s.geoReverse))
	mux.HandleFunc("GET "+v+"/geo/search", a(s.geoSearch))
	mux.HandleFunc("GET "+v+"/service-area", a(s.serviceArea))

	// merchants (public view)
	mux.HandleFunc("GET "+v+"/merchants", a(s.listMerchants))
	mux.HandleFunc("GET "+v+"/merchants/{id}", a(s.getMerchant))

	// quotes & jobs
	mux.HandleFunc("POST "+v+"/quotes", a(s.createQuote))
	mux.HandleFunc("POST "+v+"/jobs", a(s.createJob))
	mux.HandleFunc("GET "+v+"/jobs", a(s.listJobs))
	mux.HandleFunc("GET "+v+"/jobs/{id}", a(s.getJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/cancel", a(s.cancelJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/confirm-items", a(s.confirmItems))
	mux.HandleFunc("POST "+v+"/jobs/{id}/rate", a(s.rateJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/share", a(s.shareJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/sos", a(s.sosJob))
	mux.HandleFunc("POST "+v+"/jobs/{id}/call", a(s.callJob))
	mux.HandleFunc("GET "+v+"/jobs/{id}/messages", a(s.listMessages))
	mux.HandleFunc("POST "+v+"/jobs/{id}/messages", a(s.sendMessage))

	// uploads
	mux.HandleFunc("POST "+v+"/uploads", a(s.createUpload))
	mux.HandleFunc("PUT /upload/{key...}", s.putUpload)
	mux.HandleFunc("GET /files/{key...}", s.getFile)

	// rider
	mux.HandleFunc("GET "+v+"/rider/me", a(s.riderMe))
	mux.HandleFunc("PUT "+v+"/rider/me", a(s.riderSubmit))
	mux.HandleFunc("POST "+v+"/rider/status", a(s.riderStatus))
	mux.HandleFunc("POST "+v+"/rider/location", a(s.riderLocationHTTP))
	mux.HandleFunc("GET "+v+"/rider/offers/current", a(s.currentOffer))
	mux.HandleFunc("POST "+v+"/rider/offers/{id}/accept", a(s.acceptOffer))
	mux.HandleFunc("POST "+v+"/rider/offers/{id}/decline", a(s.declineOffer))
	mux.HandleFunc("GET "+v+"/rider/jobs/active", a(s.riderActiveJob))
	mux.HandleFunc("GET "+v+"/rider/jobs", a(s.riderJobs))
	mux.HandleFunc("POST "+v+"/rider/jobs/{id}/status", a(s.riderJobStatus))
	mux.HandleFunc("GET "+v+"/rider/earnings", a(s.riderEarnings))
	mux.HandleFunc("GET "+v+"/rider/wallet", a(s.riderWallet))
	mux.HandleFunc("GET "+v+"/rider/wallet/transactions", a(s.riderTransactions))
	mux.HandleFunc("POST "+v+"/rider/wallet/topups", a(s.riderTopup))
	mux.HandleFunc("POST "+v+"/rider/kyc/session", a(s.riderKycSession))

	// merchant
	mux.HandleFunc("GET "+v+"/merchant/me", a(s.merchantMe))
	mux.HandleFunc("PATCH "+v+"/merchant/store", a(s.patchStore))
	mux.HandleFunc("GET "+v+"/merchant/orders", a(s.merchantOrders))
	mux.HandleFunc("GET "+v+"/merchant/orders/{id}", a(s.merchantOrder))
	mux.HandleFunc("POST "+v+"/merchant/orders/{id}/accept", a(s.merchantAccept))
	mux.HandleFunc("POST "+v+"/merchant/orders/{id}/reject", a(s.merchantReject))
	mux.HandleFunc("POST "+v+"/merchant/orders/{id}/ready", a(s.merchantReady))
	mux.HandleFunc("GET "+v+"/merchant/menu", a(s.merchantMenu))
	mux.HandleFunc("POST "+v+"/merchant/menu/categories", a(s.addCategory))
	mux.HandleFunc("PATCH "+v+"/merchant/menu/categories/{id}", a(s.renameCategory))
	mux.HandleFunc("DELETE "+v+"/merchant/menu/categories/{id}", a(s.deleteCategory))
	mux.HandleFunc("PUT "+v+"/merchant/menu/categories/order", a(s.reorderCategories))
	mux.HandleFunc("POST "+v+"/merchant/menu/items", a(s.createItem))
	mux.HandleFunc("PUT "+v+"/merchant/menu/items/{id}", a(s.updateItem))
	mux.HandleFunc("DELETE "+v+"/merchant/menu/items/{id}", a(s.deleteItem))
	mux.HandleFunc("PATCH "+v+"/merchant/menu/items/{id}/availability", a(s.itemAvailability))
	mux.HandleFunc("PATCH "+v+"/merchant/menu/addon-options/{id}/availability", a(s.optionAvailability))
	mux.HandleFunc("GET "+v+"/merchant/reports/sales", a(s.salesReport))
	mux.HandleFunc("GET "+v+"/merchant/payouts", a(s.listPayouts))

	// websocket
	mux.HandleFunc("GET /ws", s.serveWS)

	// dev pages: payments, share links, admin
	mux.HandleFunc("GET /pay/{kind}/{id}", s.payPage)
	mux.HandleFunc("POST /pay/{kind}/{id}", s.payAction)
	mux.HandleFunc("GET /t/{token}", s.sharePage)
	mux.HandleFunc("POST /admin/riders/{id}/{action}", s.adminRider)
	mux.HandleFunc("GET /admin", s.adminPage)

	// provider webhooks + return pages (in-app browser lands here afterwards)
	mux.HandleFunc("POST /webhooks/paymongo", s.paymongoWebhook)
	mux.HandleFunc("POST /webhooks/didit", s.diditWebhook)
	mux.HandleFunc("GET /pay/return", s.returnPage("Payment received", "If you paid, your booking updates in a few seconds. You can close this page and go back to Ngain."))
	mux.HandleFunc("GET /kyc/return", s.returnPage("Verification submitted", "Thanks! Close this page and go back to Ngain Rider. Approval usually takes a few minutes."))

	return logging(mux)
}

func b64std(s string) string { return base64.StdEncoding.EncodeToString([]byte(s)) }
