package integrations

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// GoogleProfile holds user identity information returned from Google tokeninfo endpoint.
type GoogleProfile struct {
	ID            string `json:"sub"`
	Email         string `json:"email"`
	EmailVerified any    `json:"email_verified"` // can be bool or "true" string
	Name          string `json:"name"`
	Picture       string `json:"picture"`
	Audience      string `json:"aud"`
}

// FacebookProfile holds user profile data returned from the Facebook Graph API.
type FacebookProfile struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Email   string `json:"email"`
	Picture struct {
		Data struct {
			URL string `json:"url"`
		} `json:"data"`
	} `json:"picture"`
}

// SocialAuth verifies tokens from Google and Facebook.
type SocialAuth struct {
	GoogleClientID   string
	GoogleTokenURL   string
	FacebookGraphURL string
	HTTPClient       *http.Client
}

// NewSocialAuth returns a SocialAuth instance with standard endpoints.
func NewSocialAuth(googleClientID string) *SocialAuth {
	return &SocialAuth{
		GoogleClientID:   googleClientID,
		GoogleTokenURL:   "https://oauth2.googleapis.com/tokeninfo",
		FacebookGraphURL: "https://graph.facebook.com/me",
		HTTPClient:       &http.Client{Timeout: 10 * time.Second},
	}
}

// VerifyGoogle validates a Google ID token and returns the verified profile.
func (s *SocialAuth) VerifyGoogle(ctx context.Context, idToken string) (*GoogleProfile, error) {
	idToken = strings.TrimSpace(idToken)
	if idToken == "" {
		return nil, fmt.Errorf("empty google id token")
	}

	reqURL := s.GoogleTokenURL + "?id_token=" + url.QueryEscape(idToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	client := s.HTTPClient
	if client == nil {
		client = http.DefaultClient
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("verify google token: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Error            string `json:"error"`
			ErrorDescription string `json:"error_description"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&errResp)
		msg := errResp.ErrorDescription
		if msg == "" {
			msg = errResp.Error
		}
		if msg == "" {
			msg = fmt.Sprintf("HTTP %d", resp.StatusCode)
		}
		return nil, fmt.Errorf("google token invalid: %s", msg)
	}

	var p GoogleProfile
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return nil, fmt.Errorf("decode google response: %w", err)
	}

	if p.ID == "" {
		return nil, fmt.Errorf("missing user id from google")
	}

	if s.GoogleClientID != "" && p.Audience != "" && p.Audience != s.GoogleClientID {
		return nil, fmt.Errorf("google token client id mismatch (got %s, expected %s)", p.Audience, s.GoogleClientID)
	}

	return &p, nil
}

// VerifyFacebook validates a Facebook user access token and returns the user profile.
func (s *SocialAuth) VerifyFacebook(ctx context.Context, accessToken string) (*FacebookProfile, error) {
	accessToken = strings.TrimSpace(accessToken)
	if accessToken == "" {
		return nil, fmt.Errorf("empty facebook access token")
	}

	reqURL := s.FacebookGraphURL + "?fields=id,name,email,picture.type(large)&access_token=" + url.QueryEscape(accessToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, reqURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}

	client := s.HTTPClient
	if client == nil {
		client = http.DefaultClient
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("verify facebook token: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var errResp struct {
			Error struct {
				Message string `json:"message"`
				Type    string `json:"type"`
				Code    int    `json:"code"`
			} `json:"error"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&errResp)
		msg := errResp.Error.Message
		if msg == "" {
			msg = fmt.Sprintf("HTTP %d", resp.StatusCode)
		}
		return nil, fmt.Errorf("facebook token invalid: %s", msg)
	}

	var p FacebookProfile
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		return nil, fmt.Errorf("decode facebook response: %w", err)
	}

	if p.ID == "" {
		return nil, fmt.Errorf("missing user id from facebook")
	}

	return &p, nil
}
