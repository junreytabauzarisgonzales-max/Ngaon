package domain

import "time"

// UTC marshals as ISO 8601 UTC string without milliseconds (`2026-11-14T14:05:00Z`).
type UTC struct{ time.Time }

// Now returns the current time truncated to seconds in UTC.
func Now() UTC { return UTC{time.Now().UTC().Truncate(time.Second)} }

func (t UTC) MarshalJSON() ([]byte, error) {
	return []byte(`"` + t.Time.UTC().Format("2006-01-02T15:04:05Z") + `"`), nil
}

func (t *UTC) UnmarshalJSON(b []byte) error {
	if string(b) == "null" {
		return nil
	}
	p, err := time.Parse(`"`+time.RFC3339+`"`, string(b))
	if err != nil {
		return err
	}
	t.Time = p.UTC()
	return nil
}

// At converts a standard time.Time into a truncated UTC pointer.
func At(t time.Time) *UTC {
	u := UTC{t.UTC().Truncate(time.Second)}
	return &u
}
