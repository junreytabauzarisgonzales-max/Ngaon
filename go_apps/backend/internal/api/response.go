package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"goapp/backend/internal/domain"
)

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
		next = domain.StrPtr(strconv.Itoa(end))
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
