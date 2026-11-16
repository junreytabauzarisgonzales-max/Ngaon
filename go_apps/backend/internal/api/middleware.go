package api

import (
	"context"
	"log"
	"net"
	"net/http"
	"runtime/debug"
	"strconv"
	"strings"
	"time"

	"goapp/backend/internal/service"
)

type ctxKey int

const claimsKey ctxKey = 1

func claimsOf(r *http.Request) service.Claims {
	c, _ := r.Context().Value(claimsKey).(service.Claims)
	return c
}

func remoteHost(r *http.Request) string {
	host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
	if err == nil && host != "" {
		return host
	}
	if r.RemoteAddr != "" {
		return strings.TrimSpace(r.RemoteAddr)
	}
	return "unknown"
}

func isTrustedProxy(remoteIP string, trustedCfg string) bool {
	trustedCfg = strings.TrimSpace(trustedCfg)
	if trustedCfg == "" {
		return false
	}
	if trustedCfg == "*" {
		return true
	}
	parsedRemote := net.ParseIP(remoteIP)
	for _, entry := range strings.Split(trustedCfg, ",") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		if entry == remoteIP {
			return true
		}
		if parsedRemote != nil {
			if _, ipNet, err := net.ParseCIDR(entry); err == nil && ipNet.Contains(parsedRemote) {
				return true
			}
		}
	}
	return false
}

func (a *API) clientIP(r *http.Request) string {
	peer := remoteHost(r)
	if isTrustedProxy(peer, a.svc.Cfg.TrustedProxies) {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			first := strings.TrimSpace(strings.Split(xff, ",")[0])
			if net.ParseIP(first) != nil {
				return first
			}
		}
		if xrip := strings.TrimSpace(r.Header.Get("X-Real-IP")); xrip != "" {
			if net.ParseIP(xrip) != nil {
				return xrip
			}
		}
	}
	return peer
}

type handler func(w http.ResponseWriter, r *http.Request) error

func (a *API) pub(h handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !a.checkRateLimit(w, r) {
			return
		}
		if err := h(w, r); err != nil {
			fail(w, err)
		}
	}
}

func (a *API) authed(h handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !a.checkRateLimit(w, r) {
			return
		}
		authHdr := r.Header.Get("Authorization")
		if !strings.HasPrefix(authHdr, "Bearer ") {
			fail(w, errUnauthorized)
			return
		}
		tok := strings.TrimSpace(strings.TrimPrefix(authHdr, "Bearer "))
		c, expired, err := a.svc.ParseJWT(tok)
		if err != nil {
			fail(w, errUnauthorized)
			return
		}
		if expired {
			fail(w, apiErr(401, "token_expired", "Token has expired"))
			return
		}
		a.svc.Lock()
		userExists := a.svc.EnsureUserLocked(c.Sub)
		a.svc.Unlock()
		if !userExists {
			fail(w, errUnauthorized)
			return
		}
		r = r.WithContext(context.WithValue(r.Context(), claimsKey, c))
		if err := h(w, r); err != nil {
			fail(w, err)
		}
	}
}

func (a *API) checkRateLimit(w http.ResponseWriter, r *http.Request) bool {
	ip := a.clientIP(r)
	scope := "api_ip"
	limit := a.svc.Cfg.RateLimitPerMin
	if strings.HasPrefix(r.URL.Path, "/api/v1/auth/") {
		scope = "auth_ip"
		limit = a.svc.Cfg.AuthRateLimitPerMin
	}
	if limit <= 0 {
		return true
	}
	allowed, rem, retry := a.svc.AllowRate(scope, ip, limit, time.Minute)
	w.Header().Set("X-RateLimit-Limit", strconv.Itoa(limit))
	w.Header().Set("X-RateLimit-Remaining", strconv.Itoa(rem))
	if !allowed {
		secs := int(retry.Seconds())
		if secs < 1 {
			secs = 1
		}
		w.Header().Set("Retry-After", strconv.Itoa(secs))
		fail(w, apiErr(429, "rate_limited", "Too many requests, please try again shortly"))
		return false
	}
	return true
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (r *statusRecorder) WriteHeader(c int) {
	r.code = c
	r.ResponseWriter.WriteHeader(c)
}

func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, code: 200}
		defer func() {
			if p := recover(); p != nil {
				log.Printf("panic: %v\n%s", p, debug.Stack())
				fail(w, apiErr(500, "server_error", "Internal error"))
			}
		}()
		next.ServeHTTP(rec, r)
		app := r.Header.Get("X-App")
		if app != "" {
			app = " [" + app + "]"
		}
		if !strings.HasPrefix(r.URL.Path, "/files/") && r.URL.Path != "/healthz" {
			log.Printf("%s %s %d %s%s", r.Method, r.URL.Path, rec.code, time.Since(start).Round(time.Millisecond), app)
		}
	})
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-XSS-Protection", "0")
		h.Set("Permissions-Policy", "geolocation=(), microphone=(), camera=()")
		if strings.HasPrefix(r.URL.Path, "/api/v1/auth/") || strings.HasPrefix(r.URL.Path, "/api/v1/me") {
			h.Set("Cache-Control", "no-store")
		}
		next.ServeHTTP(w, r)
	})
}

func (a *API) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		allowedCfg := strings.TrimSpace(a.svc.Cfg.CORSAllowedOrigins)
		if allowedCfg == "" || allowedCfg == "*" {
			w.Header().Set("Access-Control-Allow-Origin", "*")
		} else {
			origin := r.Header.Get("Origin")
			for _, o := range strings.Split(allowedCfg, ",") {
				if strings.TrimSpace(o) == origin && origin != "" {
					w.Header().Set("Access-Control-Allow-Origin", origin)
					w.Header().Set("Vary", "Origin")
					break
				}
			}
		}
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-App, X-App-Version, Accept-Language, Idempotency-Key")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		if r.Method == "OPTIONS" {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}
