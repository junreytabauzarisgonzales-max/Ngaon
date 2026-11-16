package domain

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"strings"
	"time"
)

// Manila timezone is UTC+8, no DST.
var Manila = time.FixedZone("Asia/Manila", 8*3600)

func ManilaDate(t time.Time) string {
	return t.In(Manila).Format("2006-01-02")
}

func FirstName(name string) string {
	f := strings.Fields(name)
	if len(f) == 0 {
		return "Customer"
	}
	return f[0]
}

func MaskPhone(e164 string) string {
	if !strings.HasPrefix(e164, "+63") || len(e164) != 13 {
		return e164
	}
	l := e164[3:]
	return "+63 " + l[:3] + " ••• " + l[6:]
}

func StrPtr(s string) *string { return &s }
func IntPtr(i int) *int       { return &i }

func DeepCopy[T any](v T) T {
	b, _ := json.Marshal(v)
	var out T
	_ = json.Unmarshal(b, &out)
	return out
}

func NewID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b)
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

func RandToken(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
