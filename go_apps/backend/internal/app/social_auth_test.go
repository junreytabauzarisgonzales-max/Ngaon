package app

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"goapp/backend/internal/config"
	"goapp/backend/internal/service"
)

func TestGoogleAndFacebookAuth(t *testing.T) {
	// 1. Mock Google and Facebook servers
	mockGoogle := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		idToken := r.URL.Query().Get("id_token")
		if idToken == "valid-google-token" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"sub":            "google-user-12345",
				"email":          "juan.delacruz@gmail.com",
				"email_verified": true,
				"name":           "Juan Dela Cruz",
				"picture":        "https://lh3.googleusercontent.com/photo.jpg",
				"aud":            "mock-client-id",
			})
			return
		}
		http.Error(w, `{"error":"invalid_token","error_description":"Invalid Value"}`, http.StatusBadRequest)
	}))
	defer mockGoogle.Close()

	mockFacebook := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		accessToken := r.URL.Query().Get("access_token")
		if accessToken == "valid-fb-token" {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"id":    "fb-user-67890",
				"name":  "Maria Santos",
				"email": "maria.santos@facebook.com",
				"picture": map[string]any{
					"data": map[string]any{
						"url": "https://graph.facebook.com/picture.jpg",
					},
				},
			})
			return
		}
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":{"message":"Invalid OAuth access token.","type":"OAuthException","code":190}}`))
	}))
	defer mockFacebook.Close()

	// 2. Initialize Service with Mock URLs
	cfg := config.Config{
		DataDir:             t.TempDir(),
		JWTSecret:           []byte("test-social-jwt-secret"),
		GoogleClientID:      "mock-client-id",
		RateLimitPerMin:     300,
		AuthRateLimitPerMin: 30,
		AdminToken:          "adm",
	}

	svc, err := service.New(cfg)
	if err != nil {
		t.Fatalf("failed to create service: %v", err)
	}
	svc.Social.GoogleTokenURL = mockGoogle.URL
	svc.Social.FacebookGraphURL = mockFacebook.URL

	srv := NewServerWithService(svc)
	handler := srv.Routes()

	// 3. Test Invalid Google Token
	{
		body, _ := json.Marshal(map[string]string{
			"id_token": "bad-token",
			"app":      "customer",
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/google", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("expected 401 for bad google token, got %d: %s", rec.Code, rec.Body.String())
		}
	}

	// 4. Test Valid Google Login (New User, Needs Phone)
	var accessToken string
	var userID string
	{
		body, _ := json.Marshal(map[string]string{
			"id_token": "valid-google-token",
			"app":      "customer",
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/google", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 for valid google login, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp struct {
			Data struct {
				AccessToken  string `json:"access_token"`
				RefreshToken string `json:"refresh_token"`
				IsNewUser    bool   `json:"is_new_user"`
				NeedsPhone   bool   `json:"needs_phone"`
				User         struct {
					ID       string `json:"id"`
					Name     string `json:"name"`
					Email    string `json:"email"`
					GoogleID string `json:"google_id"`
				} `json:"user"`
			} `json:"data"`
		}
		if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
			t.Fatalf("failed to decode response: %v", err)
		}

		if resp.Data.AccessToken == "" {
			t.Fatal("expected access_token, got empty")
		}
		if !resp.Data.NeedsPhone {
			t.Fatal("expected needs_phone = true for new google user without phone")
		}
		if resp.Data.User.Name != "Juan Dela Cruz" {
			t.Fatalf("expected name 'Juan Dela Cruz', got '%s'", resp.Data.User.Name)
		}
		if resp.Data.User.GoogleID != "google-user-12345" {
			t.Fatalf("expected google_id 'google-user-12345', got '%s'", resp.Data.User.GoogleID)
		}

		accessToken = resp.Data.AccessToken
		userID = resp.Data.User.ID
	}

	// 5. Test Binding Phone via PATCH /api/v1/me
	{
		patchBody, _ := json.Marshal(map[string]string{
			"phone": "+639175556677",
		})
		req := httptest.NewRequest(http.MethodPatch, "/api/v1/me", bytes.NewReader(patchBody))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+accessToken)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 on PATCH /me to set phone, got %d: %s", rec.Code, rec.Body.String())
		}

		var updated struct {
			Data struct {
				Phone string `json:"phone"`
			} `json:"data"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&updated)
		if updated.Data.Phone != "+639175556677" {
			t.Fatalf("expected phone '+639175556677', got '%s'", updated.Data.Phone)
		}
	}

	// 6. Test Subsequent Google Login (Recognizes User, NeedsPhone = false)
	{
		body, _ := json.Marshal(map[string]string{
			"id_token": "valid-google-token",
			"app":      "customer",
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/google", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp struct {
			Data struct {
				NeedsPhone bool `json:"needs_phone"`
				User       struct {
					ID    string `json:"id"`
					Phone string `json:"phone"`
				} `json:"user"`
			} `json:"data"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Data.User.ID != userID {
			t.Fatalf("expected existing user ID %s, got %s", userID, resp.Data.User.ID)
		}
		if resp.Data.NeedsPhone {
			t.Fatal("expected needs_phone = false after binding phone")
		}
		if resp.Data.User.Phone != "+639175556677" {
			t.Fatalf("expected phone '+639175556677', got '%s'", resp.Data.User.Phone)
		}
	}

	// 7. Test Facebook Login
	{
		body, _ := json.Marshal(map[string]string{
			"access_token": "valid-fb-token",
			"app":          "customer",
		})
		req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/facebook", bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200 on facebook auth, got %d: %s", rec.Code, rec.Body.String())
		}

		var resp struct {
			Data struct {
				AccessToken string `json:"access_token"`
				NeedsPhone  bool   `json:"needs_phone"`
				User        struct {
					Name       string `json:"name"`
					FacebookID string `json:"facebook_id"`
				} `json:"user"`
			} `json:"data"`
		}
		_ = json.NewDecoder(rec.Body).Decode(&resp)
		if resp.Data.AccessToken == "" {
			t.Fatal("expected facebook access token")
		}
		if resp.Data.User.Name != "Maria Santos" {
			t.Fatalf("expected name 'Maria Santos', got '%s'", resp.Data.User.Name)
		}
		if resp.Data.User.FacebookID != "fb-user-67890" {
			t.Fatalf("expected facebook_id 'fb-user-67890', got '%s'", resp.Data.User.FacebookID)
		}
	}
}
