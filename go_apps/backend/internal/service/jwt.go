package service

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"goapp/backend/internal/domain"
)

type Claims struct {
	Sub string `json:"sub"`
	App string `json:"app"`
	Exp int64  `json:"exp"`
	Iat int64  `json:"iat,omitempty"`
	Jti string `json:"jti,omitempty"`
}

var b64 = base64.RawURLEncoding

var ErrUnauthorized = errors.New("unauthorized")

const accessTTL = 15 * time.Minute
const refreshTTL = 30 * 24 * time.Hour

// HashToken returns the SHA-256 hex digest of a token so raw secrets are never stored at rest.
func HashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func (s *Service) SignJWT(c Claims) string {
	if c.Iat == 0 {
		c.Iat = time.Now().Unix()
	}
	if c.Jti == "" {
		c.Jti = domain.NewID()
	}
	head := b64.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	body, _ := json.Marshal(c)
	payload := head + "." + b64.EncodeToString(body)
	mac := hmac.New(sha256.New, s.Cfg.JWTSecret)
	mac.Write([]byte(payload))
	return payload + "." + b64.EncodeToString(mac.Sum(nil))
}

// ParseJWT validates the HS256 header, HMAC signature, revocation state, and expiration.
// Returns expired=true when the signature is valid and unrevoked, but exp has passed.
func (s *Service) ParseJWT(tok string) (c Claims, expired bool, err error) {
	parts := strings.Split(tok, ".")
	if len(parts) != 3 {
		return c, false, ErrUnauthorized
	}

	// Verify header explicitly specifies HS256 to prevent algorithm confusion.
	hdrBytes, err := b64.DecodeString(parts[0])
	if err != nil {
		return c, false, ErrUnauthorized
	}
	var hdr struct {
		Alg string `json:"alg"`
	}
	if json.Unmarshal(hdrBytes, &hdr) != nil || hdr.Alg != "HS256" {
		return c, false, ErrUnauthorized
	}

	mac := hmac.New(sha256.New, s.Cfg.JWTSecret)
	mac.Write([]byte(parts[0] + "." + parts[1]))
	sig, err := b64.DecodeString(parts[2])
	if err != nil || !hmac.Equal(sig, mac.Sum(nil)) {
		return c, false, ErrUnauthorized
	}
	body, err := b64.DecodeString(parts[1])
	if err != nil || json.Unmarshal(body, &c) != nil || c.Sub == "" {
		return c, false, ErrUnauthorized
	}

	// Check token revocation (by JTI and by token hash).
	if s.isAccessTokenRevoked(tok, c) {
		return c, false, ErrUnauthorized
	}

	if time.Now().Unix() >= c.Exp {
		return c, true, nil
	}
	return c, false, nil
}

func (s *Service) isAccessTokenRevoked(rawTok string, c Claims) bool {
	tokID := c.Jti
	if tokID == "" {
		tokID = HashToken(rawTok)
	}
	userRevokeID := "user:" + c.Sub

	s.revokedMu.Lock()
	for _, key := range []string{tokID, userRevokeID} {
		if exp, exists := s.revokedTokens[key]; exists {
			if time.Now().Before(exp) {
				s.revokedMu.Unlock()
				return true
			}
			delete(s.revokedTokens, key)
		}
	}
	s.revokedMu.Unlock()

	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		if revoked, err := s.Redis.IsTokenRevoked(ctx, tokID); err == nil && revoked {
			return true
		}
		if c.Sub != "" {
			if revoked, err := s.Redis.IsTokenRevoked(ctx, userRevokeID); err == nil && revoked {
				return true
			}
		}
	}
	return false
}

// RevokeAccessToken blacklists an access token in memory and Redis until its expiration.
func (s *Service) RevokeAccessToken(rawTok string) {
	rawTok = strings.TrimSpace(strings.TrimPrefix(rawTok, "Bearer "))
	if rawTok == "" {
		return
	}
	c, _, err := s.ParseJWT(rawTok)
	if err != nil {
		return
	}
	ttl := time.Until(time.Unix(c.Exp, 0))
	if ttl <= 0 {
		return
	}
	tokID := c.Jti
	if tokID == "" {
		tokID = HashToken(rawTok)
	}
	s.revokedMu.Lock()
	s.revokedTokens[tokID] = time.Unix(c.Exp, 0)
	s.revokedMu.Unlock()

	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = s.Redis.RevokeToken(ctx, tokID, ttl)
	}
}

func (s *Service) IssueTokens(userID, app string) (string, string) {
	access := s.SignJWT(Claims{
		Sub: userID,
		App: app,
		Exp: time.Now().Add(accessTTL).Unix(),
		Iat: time.Now().Unix(),
		Jti: domain.NewID(),
	})
	rawRefresh := domain.RandToken(32)
	refreshHash := HashToken(rawRefresh)
	rt := domain.RefreshToken{UserID: userID, App: app, Expires: time.Now().Add(refreshTTL)}
	s.St.Refresh[refreshHash] = rt
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = s.Redis.SaveRefreshToken(ctx, refreshHash, rt)
	}
	s.Touch()
	return access, rawRefresh
}

// RotateRefreshToken validates a refresh token, invalidates it (one-time rotation), and issues a new pair.
func (s *Service) RotateRefreshToken(rawToken string) (access, refresh string, ok bool) {
	if rawToken == "" {
		return "", "", false
	}
	tokenHash := HashToken(rawToken)

	s.revokedMu.Lock()
	if exp, revoked := s.revokedTokens["rt:"+tokenHash]; revoked && time.Now().Before(exp) {
		s.revokedMu.Unlock()
		delete(s.St.Refresh, tokenHash)
		delete(s.St.Refresh, rawToken)
		return "", "", false
	}
	s.revokedMu.Unlock()

	var rt domain.RefreshToken
	found := false
	usedKey := tokenHash
	checkedRedis := false

	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		revoked, revErr := s.Redis.IsTokenRevoked(ctx, "rt:"+tokenHash)
		if revErr == nil && revoked {
			cancel()
			delete(s.St.Refresh, tokenHash)
			delete(s.St.Refresh, rawToken)
			return "", "", false
		}
		redisRT, redisFound, err := s.Redis.GetRefreshToken(ctx, tokenHash)
		cancel()
		if err == nil {
			checkedRedis = true
			if redisFound {
				rt = redisRT
				found = true
			}
		}
	}

	if !found {
		if memRT, memFound := s.St.Refresh[tokenHash]; memFound && !checkedRedis {
			rt = memRT
			found = true
		} else if legacyRT, legacyFound := s.St.Refresh[rawToken]; legacyFound {
			rt = legacyRT
			found = true
			usedKey = rawToken
		}
	}

	if !found || time.Now().After(rt.Expires) || !s.EnsureUserLocked(rt.UserID) {
		delete(s.St.Refresh, usedKey)
		delete(s.St.Refresh, tokenHash)
		if s.Redis != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cancel()
			_ = s.Redis.DeleteRefreshToken(ctx, tokenHash)
		}
		return "", "", false
	}

	delete(s.St.Refresh, usedKey)
	delete(s.St.Refresh, tokenHash)
	s.revokedMu.Lock()
	s.revokedTokens["rt:"+tokenHash] = rt.Expires
	s.revokedMu.Unlock()
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = s.Redis.DeleteRefreshToken(ctx, tokenHash)
	}
	access, refresh = s.IssueTokens(rt.UserID, rt.App)
	return access, refresh, true
}

// RevokeRefreshToken deletes a refresh token from memory and Redis.
func (s *Service) RevokeRefreshToken(rawToken string) {
	if rawToken == "" {
		return
	}
	tokenHash := HashToken(rawToken)
	delete(s.St.Refresh, tokenHash)
	delete(s.St.Refresh, rawToken)
	s.revokedMu.Lock()
	s.revokedTokens["rt:"+tokenHash] = time.Now().Add(refreshTTL)
	s.revokedMu.Unlock()
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = s.Redis.DeleteRefreshToken(ctx, tokenHash)
	}
}

// RevokeUserSessions removes all refresh tokens for a user from memory and Redis.
func (s *Service) RevokeUserSessions(userID string) {
	s.revokedMu.Lock()
	s.revokedTokens["user:"+userID] = time.Now().Add(24 * time.Hour)
	for k, t := range s.St.Refresh {
		if t.UserID == userID {
			s.revokedTokens["rt:"+k] = t.Expires
			delete(s.St.Refresh, k)
		}
	}
	s.revokedMu.Unlock()
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = s.Redis.DeleteUserRefreshTokens(ctx, userID)
	}
}

// HashOTP computes an HMAC-SHA256 digest of phone and OTP code bound to JWTSecret.
func (s *Service) HashOTP(phone, code string) string {
	mac := hmac.New(sha256.New, s.Cfg.JWTSecret)
	mac.Write([]byte("otp:" + phone + ":" + code))
	return hex.EncodeToString(mac.Sum(nil))
}

// VerifyOTPCode compares an OTP code in constant time against either an HMAC hash or plaintext fallback.
func (s *Service) VerifyOTPCode(phone, candidate, stored string) bool {
	if candidate == "" || stored == "" {
		return false
	}
	candidateHash := s.HashOTP(phone, candidate)
	if subtle.ConstantTimeCompare([]byte(candidateHash), []byte(stored)) == 1 {
		return true
	}
	return subtle.ConstantTimeCompare([]byte(candidate), []byte(stored)) == 1
}

// VerifyAdminToken performs a constant-time comparison against the configured AdminToken.
func (s *Service) VerifyAdminToken(candidate string) bool {
	if len(s.Cfg.AdminToken) == 0 || len(candidate) == 0 {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(candidate), []byte(s.Cfg.AdminToken)) == 1
}

type memRateBucket struct {
	count   int
	resetAt time.Time
}

// AllowRate checks rate limits using Redis when connected, or an in-memory fixed-window limiter as fallback.
func (s *Service) AllowRate(scope, id string, limit int, window time.Duration) (allowed bool, remaining int, retryAfter time.Duration) {
	if limit <= 0 {
		return true, 1, 0
	}
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
		defer cancel()
		ok, rem, retry, err := s.Redis.AllowRate(ctx, scope, id, limit, window)
		if err == nil {
			return ok, rem, retry
		}
	}

	s.rateMu.Lock()
	defer s.rateMu.Unlock()
	now := time.Now()
	key := scope + ":" + id
	b, exists := s.rateBuckets[key]
	if !exists || now.After(b.resetAt) {
		b = &memRateBucket{count: 0, resetAt: now.Add(window)}
		s.rateBuckets[key] = b
	}
	b.count++
	rem := limit - b.count
	if rem < 0 {
		rem = 0
	}
	return b.count <= limit, rem, time.Until(b.resetAt)
}
