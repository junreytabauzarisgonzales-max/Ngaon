package integrations

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFormatPHPhone(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"+639171234567", "639171234567"},
		{"639171234567", "639171234567"},
		{"09171234567", "639171234567"},
		{"+639281112233", "639281112233"},
	}

	for _, tc := range tests {
		got := FormatPHPhone(tc.input)
		if got != tc.expected {
			t.Errorf("FormatPHPhone(%q) = %q; want %q", tc.input, got, tc.expected)
		}
	}
}

func TestInfobipSendOTP(t *testing.T) {
	var receivedBody map[string]any
	var authHeader string

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader = r.Header.Get("Authorization")
		body, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(body, &receivedBody)

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"messages":[{"messageId":"msg-123","status":{"name":"PENDING_ACCEPTED"}}]}`))
	}))
	defer srv.Close()

	ib := NewInfobip(InfobipConfig{
		APIKey:   "test-api-key",
		BaseURL:  srv.URL,
		SenderID: "Ngaon",
	})

	if !ib.Enabled() {
		t.Fatalf("expected Infobip to be enabled")
	}

	err := ib.SendOTP(context.Background(), "+639171234567", "849201")
	if err != nil {
		t.Fatalf("SendOTP returned error: %v", err)
	}

	if authHeader != "App test-api-key" {
		t.Errorf("expected Authorization 'App test-api-key', got %q", authHeader)
	}

	messages, ok := receivedBody["messages"].([]any)
	if !ok || len(messages) == 0 {
		t.Fatalf("expected messages array in payload, got %v", receivedBody)
	}

	msg0 := messages[0].(map[string]any)
	if msg0["from"] != "Ngaon" {
		t.Errorf("expected from 'Ngaon', got %v", msg0["from"])
	}
}
