package integrations

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

// InfobipConfig holds authentication and endpoint parameters for Infobip SMS.
type InfobipConfig struct {
	APIKey   string
	BaseURL  string
	SenderID string
}

// Infobip provides SMS OTP sending capabilities via Infobip.
type Infobip struct {
	cfg        InfobipConfig
	httpClient *http.Client
}

// NewInfobip creates and configures an Infobip SMS client.
func NewInfobip(cfg InfobipConfig) *Infobip {
	baseURL := strings.TrimRight(strings.TrimSpace(cfg.BaseURL), "/")
	if baseURL != "" && !strings.HasPrefix(baseURL, "http://") && !strings.HasPrefix(baseURL, "https://") {
		baseURL = "https://" + baseURL
	}
	sender := strings.TrimSpace(cfg.SenderID)
	if sender == "" {
		sender = "Ngaon"
	}
	return &Infobip{
		cfg: InfobipConfig{
			APIKey:   strings.TrimSpace(cfg.APIKey),
			BaseURL:  baseURL,
			SenderID: sender,
		},
		httpClient: &http.Client{Timeout: 10 * time.Second},
	}
}

// Enabled returns true if Infobip credentials are configured.
func (b *Infobip) Enabled() bool {
	return b != nil && b.cfg.APIKey != "" && b.cfg.BaseURL != ""
}

// FormatPHPhone converts "+639171234567" or "09171234567" to international "639171234567" without '+'.
func FormatPHPhone(phone string) string {
	clean := strings.TrimSpace(phone)
	clean = strings.TrimPrefix(clean, "+")
	if strings.HasPrefix(clean, "09") && len(clean) == 11 {
		clean = "63" + clean[1:]
	}
	return clean
}

// SendOTP sends a 6-digit SMS OTP message to the recipient's phone number.
func (b *Infobip) SendOTP(ctx context.Context, phone, code string) error {
	if !b.Enabled() {
		return nil
	}

	dest := FormatPHPhone(phone)
	msgText := fmt.Sprintf("Your Ngaon verification code is: %s. Valid for 5 minutes. Do not share this code.", code)

	payload := map[string]any{
		"messages": []map[string]any{
			{
				"destinations": []map[string]string{
					{"to": dest},
				},
				"from": b.cfg.SenderID,
				"text": msgText,
			},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal infobip payload: %w", err)
	}

	reqURL := b.cfg.BaseURL + "/sms/2/text/advanced"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, reqURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create infobip request: %w", err)
	}

	req.Header.Set("Authorization", "App "+b.cfg.APIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	client := b.httpClient
	if client == nil {
		client = http.DefaultClient
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("send infobip sms: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var errData any
		_ = json.NewDecoder(resp.Body).Decode(&errData)
		return fmt.Errorf("infobip returned HTTP %d: %v", resp.StatusCode, errData)
	}

	return nil
}
