package app_test

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"goapp/backend/internal/api"
	"goapp/backend/internal/config"
	"goapp/backend/internal/service"
)

func TestAPIKeyProtection(t *testing.T) {
	cfg := config.Config{
		JWTSecret: []byte("test-jwt-secret-key-1234567890"),
		APIKey:    "ngaon-secret-mobile-api-key-2026",
	}

	svc, err := service.New(cfg)
	if err != nil {
		t.Fatalf("service.New: %v", err)
	}
	defer svc.Close()

	router := api.New(svc).Routes()

	// 1. Healthz should always pass without API key
	reqHealth := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rrHealth := httptest.NewRecorder()
	router.ServeHTTP(rrHealth, reqHealth)
	if rrHealth.Code != http.StatusOK {
		t.Errorf("healthz expected 200, got %d", rrHealth.Code)
	}

	// 2. /api/v1/auth/otp/request without X-Api-Key should be rejected with 401
	reqBlocked := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", nil)
	rrBlocked := httptest.NewRecorder()
	router.ServeHTTP(rrBlocked, reqBlocked)
	if rrBlocked.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 without X-Api-Key, got %d: %s", rrBlocked.Code, rrBlocked.Body.String())
	}

	// 3. /api/v1/auth/otp/request with wrong X-Api-Key should be rejected with 401
	reqWrong := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", nil)
	reqWrong.Header.Set("X-Api-Key", "wrong-key")
	rrWrong := httptest.NewRecorder()
	router.ServeHTTP(rrWrong, reqWrong)
	if rrWrong.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 with wrong X-Api-Key, got %d", rrWrong.Code)
	}

	// 4. /api/v1/auth/otp/request with valid X-Api-Key should pass API key check (returns 400 bad request for empty body, not 401)
	reqValid := httptest.NewRequest(http.MethodPost, "/api/v1/auth/otp/request", nil)
	reqValid.Header.Set("X-Api-Key", "ngaon-secret-mobile-api-key-2026")
	rrValid := httptest.NewRecorder()
	router.ServeHTTP(rrValid, reqValid)
	if rrValid.Code == http.StatusUnauthorized {
		t.Errorf("expected request to pass API key check, got 401")
	}
}
