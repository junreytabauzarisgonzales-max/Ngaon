package redis

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"

	goredis "github.com/redis/go-redis/v9"
	"goapp/backend/internal/domain"
	"goapp/backend/internal/repository"
)

const keyPrefix = "goapp:"

// Store wraps a Redis client and provides typed operations for caching,
// sessions, rate limiting, OTP verification, geospatial rider tracking,
// idempotency keys, and WebSocket Pub/Sub fan-out.
type Store struct {
	client *goredis.Client
}

// Connect parses the Redis URL, configures secure connection pool and timeout
// parameters, and verifies connectivity via PING.
func Connect(redisURL string) (*Store, error) {
	u := strings.TrimSpace(redisURL)
	if !strings.HasPrefix(u, "redis://") && !strings.HasPrefix(u, "rediss://") {
		u = "redis://" + u
	}
	opts, err := goredis.ParseURL(u)
	if err != nil {
		return nil, fmt.Errorf("parse redis url: %w", err)
	}
	opts.DialTimeout = 5 * time.Second
	opts.ReadTimeout = 3 * time.Second
	opts.WriteTimeout = 3 * time.Second
	opts.PoolSize = 25
	opts.MinIdleConns = 5
	opts.ConnMaxIdleTime = 5 * time.Minute

	client := goredis.NewClient(opts)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := client.Ping(ctx).Err(); err != nil {
		_ = client.Close()
		return nil, fmt.Errorf("ping redis: %w", err)
	}

	log.Printf("connected to Redis (%s, db=%d)", opts.Addr, opts.DB)
	return &Store{client: client}, nil
}

// Client returns the underlying go-redis client.
func (s *Store) Client() *goredis.Client {
	return s.client
}

// Ping verifies Redis connectivity.
func (s *Store) Ping(ctx context.Context) error {
	if s == nil || s.client == nil {
		return errors.New("redis not configured")
	}
	return s.client.Ping(ctx).Err()
}

// Close cleanly closes the Redis connection pool.
func (s *Store) Close() error {
	if s == nil || s.client == nil {
		return nil
	}
	return s.client.Close()
}

func k(parts ...string) string {
	return keyPrefix + strings.Join(parts, ":")
}

// ---------- Distributed Rate Limiting ----------

var rateLimitScript = goredis.NewScript(`
local current = redis.call("INCR", KEYS[1])
if current == 1 then
    redis.call("PEXPIRE", KEYS[1], ARGV[1])
end
local ttl = redis.call("PTTL", KEYS[1])
if ttl < 0 then
    redis.call("PEXPIRE", KEYS[1], ARGV[1])
    ttl = tonumber(ARGV[1])
end
return {current, ttl}
`)

// AllowRate atomically increments a rate limit counter in Redis within a time window.
func (s *Store) AllowRate(ctx context.Context, scope, id string, limit int, window time.Duration) (allowed bool, remaining int, retryAfter time.Duration, err error) {
	key := k("rl", scope, id)
	res, err := rateLimitScript.Run(ctx, s.client, []string{key}, window.Milliseconds()).Int64Slice()
	if err != nil {
		return true, limit, 0, err
	}
	count := int(res[0])
	ttlMs := res[1]
	if ttlMs < 0 {
		ttlMs = window.Milliseconds()
	}
	remaining = limit - count
	if remaining < 0 {
		remaining = 0
	}
	return count <= limit, remaining, time.Duration(ttlMs) * time.Millisecond, nil
}

// ---------- OTP Management & Sliding-Window Rate Limiting ----------

var otpRateScript = goredis.NewScript(`
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local maxReqs = tonumber(ARGV[3])
local member = ARGV[4]

redis.call("ZREMRANGEBYSCORE", key, "-inf", now - window)
local count = redis.call("ZCARD", key)
if count >= maxReqs then
    return 0
end
redis.call("ZADD", key, now, member)
redis.call("PEXPIRE", key, math.ceil(window / 1000000))
return 1
`)

// CheckAndRecordOTPRequest enforces a sliding window limit on OTP requests per phone number.
func (s *Store) CheckAndRecordOTPRequest(ctx context.Context, phone string, window time.Duration, maxReqs int) (bool, error) {
	now := time.Now().UnixNano()
	member := fmt.Sprintf("%d:%s", now, domain.RandToken(4))
	val, err := otpRateScript.Run(ctx, s.client, []string{k("otp", "sent", phone)}, now, window.Nanoseconds(), maxReqs, member).Int()
	if err != nil {
		return false, err
	}
	return val == 1, nil
}

// SaveOTP stores the HMAC-hashed OTP code and resets its verification attempt counter.
func (s *Store) SaveOTP(ctx context.Context, phone, codeHash string, ttl time.Duration) error {
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, k("otp", "code", phone), codeHash, ttl)
	pipe.Set(ctx, k("otp", "attempts", phone), 0, ttl)
	_, err := pipe.Exec(ctx)
	return err
}

// GetOTP retrieves the stored OTP hash and current verification attempt count.
func (s *Store) GetOTP(ctx context.Context, phone string) (codeHash string, attempts int, exists bool, err error) {
	codeKey := k("otp", "code", phone)
	attKey := k("otp", "attempts", phone)

	pipe := s.client.Pipeline()
	codeCmd := pipe.Get(ctx, codeKey)
	attCmd := pipe.Get(ctx, attKey)
	_, _ = pipe.Exec(ctx)

	codeHash, err = codeCmd.Result()
	if errors.Is(err, goredis.Nil) {
		return "", 0, false, nil
	}
	if err != nil {
		return "", 0, false, err
	}
	att, _ := attCmd.Int()
	return codeHash, att, true, nil
}

// IncrementOTPAttempts atomically increments the failed verification counter for a phone's OTP.
func (s *Store) IncrementOTPAttempts(ctx context.Context, phone string, ttl time.Duration) (int, error) {
	attKey := k("otp", "attempts", phone)
	pipe := s.client.TxPipeline()
	incr := pipe.Incr(ctx, attKey)
	pipe.Expire(ctx, attKey, ttl)
	if _, err := pipe.Exec(ctx); err != nil {
		return 0, err
	}
	return int(incr.Val()), nil
}

// DeleteOTP deletes an OTP code and its attempt counter after successful verification.
func (s *Store) DeleteOTP(ctx context.Context, phone string) error {
	return s.client.Del(ctx, k("otp", "code", phone), k("otp", "attempts", phone)).Err()
}

// ---------- Refresh Tokens & Access Token Revocation ----------

// SaveRefreshToken stores a SHA-256 hashed refresh token in Redis with automatic expiration.
func (s *Store) SaveRefreshToken(ctx context.Context, tokenHash string, rt domain.RefreshToken) error {
	ttl := time.Until(rt.Expires)
	if ttl <= 0 {
		return nil
	}
	b, err := json.Marshal(rt)
	if err != nil {
		return err
	}
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, k("refresh", tokenHash), b, ttl)
	pipe.SAdd(ctx, k("user", "refresh", rt.UserID), tokenHash)
	pipe.Expire(ctx, k("user", "refresh", rt.UserID), 30*24*time.Hour)
	_, err = pipe.Exec(ctx)
	return err
}

// GetRefreshToken looks up a refresh token by its hash.
func (s *Store) GetRefreshToken(ctx context.Context, tokenHash string) (domain.RefreshToken, bool, error) {
	var rt domain.RefreshToken
	b, err := s.client.Get(ctx, k("refresh", tokenHash)).Bytes()
	if errors.Is(err, goredis.Nil) {
		return rt, false, nil
	}
	if err != nil {
		return rt, false, err
	}
	if err := json.Unmarshal(b, &rt); err != nil {
		return rt, false, err
	}
	if time.Now().After(rt.Expires) {
		_ = s.DeleteRefreshToken(ctx, tokenHash)
		return rt, false, nil
	}
	return rt, true, nil
}

// DeleteRefreshToken removes a refresh token hash from Redis, cleans up its user-set membership,
// and records a revocation tombstone so peer instances do not resurrect it.
func (s *Store) DeleteRefreshToken(ctx context.Context, tokenHash string) error {
	if tokenHash == "" {
		return nil
	}
	var userID string
	if b, err := s.client.Get(ctx, k("refresh", tokenHash)).Bytes(); err == nil {
		var rt domain.RefreshToken
		if json.Unmarshal(b, &rt) == nil {
			userID = rt.UserID
		}
	}
	pipe := s.client.TxPipeline()
	pipe.Del(ctx, k("refresh", tokenHash))
	pipe.Set(ctx, k("jwt", "revoked", "rt:"+tokenHash), "1", 30*24*time.Hour)
	if userID != "" {
		pipe.SRem(ctx, k("user", "refresh", userID), tokenHash)
	}
	_, err := pipe.Exec(ctx)
	return err
}

// DeleteUserRefreshTokens removes all active refresh tokens belonging to a user and records revocation tombstones.
func (s *Store) DeleteUserRefreshTokens(ctx context.Context, userID string) error {
	setKey := k("user", "refresh", userID)
	hashes, err := s.client.SMembers(ctx, setKey).Result()
	if err != nil && !errors.Is(err, goredis.Nil) {
		return err
	}
	pipe := s.client.TxPipeline()
	pipe.Del(ctx, setKey)
	pipe.Set(ctx, k("jwt", "revoked", "user:"+userID), "1", 24*time.Hour)
	for _, h := range hashes {
		pipe.Del(ctx, k("refresh", h))
		pipe.Set(ctx, k("jwt", "revoked", "rt:"+h), "1", 30*24*time.Hour)
	}
	_, err = pipe.Exec(ctx)
	return err
}

// SaveUser stores a user profile in Redis for cross-instance session and profile resolution.
func (s *Store) SaveUser(ctx context.Context, u *domain.User) error {
	if u == nil || u.ID == "" {
		return nil
	}
	b, err := json.Marshal(u)
	if err != nil {
		return err
	}
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, k("user", "profile", u.ID), b, 30*24*time.Hour)
	if u.Phone != "" {
		pipe.Set(ctx, k("user", "phone", u.Phone), u.ID, 30*24*time.Hour)
	}
	_, err = pipe.Exec(ctx)
	return err
}

// GetUser retrieves a user profile from Redis by user ID.
func (s *Store) GetUser(ctx context.Context, userID string) (*domain.User, bool, error) {
	if userID == "" {
		return nil, false, nil
	}
	b, err := s.client.Get(ctx, k("user", "profile", userID)).Bytes()
	if errors.Is(err, goredis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	var u domain.User
	if err := json.Unmarshal(b, &u); err != nil {
		return nil, false, err
	}
	return &u, true, nil
}

// DeleteUser removes a user profile and phone lookup index from Redis.
func (s *Store) DeleteUser(ctx context.Context, userID, phone string) error {
	keys := []string{k("user", "profile", userID)}
	if phone != "" {
		keys = append(keys, k("user", "phone", phone))
	}
	return s.client.Del(ctx, keys...).Err()
}

// RevokeToken blacklists an access token identifier (JTI or token hash) until its expiration.
func (s *Store) RevokeToken(ctx context.Context, tokenID string, ttl time.Duration) error {
	if tokenID == "" || ttl <= 0 {
		return nil
	}
	return s.client.Set(ctx, k("jwt", "revoked", tokenID), "1", ttl).Err()
}

// IsTokenRevoked checks whether an access token identifier has been blacklisted.
func (s *Store) IsTokenRevoked(ctx context.Context, tokenID string) (bool, error) {
	if tokenID == "" {
		return false, nil
	}
	n, err := s.client.Exists(ctx, k("jwt", "revoked", tokenID)).Result()
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

// ---------- Quotes Cache ----------

type cachedQuote struct {
	Quote        domain.Quote         `json:"quote"`
	UserID       string               `json:"user_id"`
	Request      *domain.QuoteRequest `json:"request"`
	FeesCentavos int                  `json:"fees_centavos"`
}

// SaveQuote caches a price quote in Redis until its expiration timestamp.
func (s *Store) SaveQuote(ctx context.Context, q *domain.Quote) error {
	if q == nil {
		return nil
	}
	ttl := time.Until(q.ExpiresAt.Time)
	if ttl <= 0 {
		return nil
	}
	rec := cachedQuote{
		Quote:        *q,
		UserID:       q.UserID,
		Request:      q.Request,
		FeesCentavos: q.FeesCentavos,
	}
	b, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	return s.client.Set(ctx, k("quote", q.ID), b, ttl).Err()
}

// GetQuote retrieves a cached quote from Redis, restoring internal metadata fields.
func (s *Store) GetQuote(ctx context.Context, id string) (*domain.Quote, bool, error) {
	b, err := s.client.Get(ctx, k("quote", id)).Bytes()
	if errors.Is(err, goredis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	var rec cachedQuote
	if err := json.Unmarshal(b, &rec); err != nil {
		return nil, false, err
	}
	q := rec.Quote
	q.UserID = rec.UserID
	q.Request = rec.Request
	q.FeesCentavos = rec.FeesCentavos
	if time.Now().After(q.ExpiresAt.Time) {
		_ = s.DeleteQuote(ctx, id)
		return nil, false, nil
	}
	return &q, true, nil
}

// DeleteQuote deletes a quote from Redis once consumed or expired.
func (s *Store) DeleteQuote(ctx context.Context, id string) error {
	return s.client.Del(ctx, k("quote", id)).Err()
}

// ---------- Dispatch Offers ----------

type cachedOffer struct {
	Offer       domain.JobOffer `json:"offer"`
	JobID       string          `json:"job_id"`
	RiderUserID string          `json:"rider_user_id"`
}

// SaveOffer persists a dispatch offer in Redis with its countdown TTL.
func (s *Store) SaveOffer(ctx context.Context, o *domain.JobOffer) error {
	if o == nil {
		return nil
	}
	ttl := time.Until(o.ExpiresAt.Time)
	if ttl <= 0 {
		return nil
	}
	rec := cachedOffer{
		Offer:       *o,
		JobID:       o.JobID,
		RiderUserID: o.RiderUserID,
	}
	b, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, k("offer", o.ID), b, ttl)
	pipe.Set(ctx, k("rider", "offer", o.RiderUserID), o.ID, ttl)
	_, err = pipe.Exec(ctx)
	return err
}

// GetOffer retrieves a dispatch offer by ID from Redis.
func (s *Store) GetOffer(ctx context.Context, id string) (*domain.JobOffer, bool, error) {
	b, err := s.client.Get(ctx, k("offer", id)).Bytes()
	if errors.Is(err, goredis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	var rec cachedOffer
	if err := json.Unmarshal(b, &rec); err != nil {
		return nil, false, err
	}
	o := rec.Offer
	o.JobID = rec.JobID
	o.RiderUserID = rec.RiderUserID
	if time.Now().After(o.ExpiresAt.Time) {
		_ = s.DeleteOffer(ctx, o.ID, o.RiderUserID)
		return nil, false, nil
	}
	return &o, true, nil
}

// GetRiderOffer returns the active offer currently assigned to a rider, if any.
func (s *Store) GetRiderOffer(ctx context.Context, riderUserID string) (*domain.JobOffer, bool, error) {
	offerID, err := s.client.Get(ctx, k("rider", "offer", riderUserID)).Result()
	if errors.Is(err, goredis.Nil) || offerID == "" {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	return s.GetOffer(ctx, offerID)
}

// DeleteOffer removes a dispatch offer and the rider's active offer pointer from Redis.
func (s *Store) DeleteOffer(ctx context.Context, id, riderUserID string) error {
	keys := []string{k("offer", id)}
	if riderUserID != "" {
		keys = append(keys, k("rider", "offer", riderUserID))
	}
	return s.client.Del(ctx, keys...).Err()
}

// ---------- Idempotency Keys ----------

// GetIdempotency retrieves the stored target entity ID for a client Idempotency-Key.
func (s *Store) GetIdempotency(ctx context.Context, key string) (string, bool, error) {
	val, err := s.client.Get(ctx, k("idempotency", key)).Result()
	if errors.Is(err, goredis.Nil) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return val, true, nil
}

// SetIdempotency stores an idempotency key mapping with a TTL (default 24h).
func (s *Store) SetIdempotency(ctx context.Context, key, targetID string, ttl time.Duration) error {
	if ttl <= 0 {
		ttl = 24 * time.Hour
	}
	return s.client.Set(ctx, k("idempotency", key), targetID, ttl).Err()
}

// ---------- Geospatial Rider Location Tracking ----------

// RiderLocationRecord holds a rider's latest coordinates and heading in Redis.
type RiderLocationRecord struct {
	UserID    string        `json:"user_id"`
	Location  domain.LatLng `json:"location"`
	Heading   *float64      `json:"heading,omitempty"`
	UpdatedAt time.Time     `json:"updated_at"`
}

// NearbyRider represents a rider returned from a Redis GEOSEARCH query.
type NearbyRider struct {
	UserID    string
	Location  domain.LatLng
	DistanceM int
}

// UpdateRiderLocation updates the rider's position in the Redis geospatial index and metadata key.
func (s *Store) UpdateRiderLocation(ctx context.Context, userID string, loc domain.LatLng, heading *float64) error {
	rec := RiderLocationRecord{
		UserID:    userID,
		Location:  loc,
		Heading:   heading,
		UpdatedAt: time.Now().UTC(),
	}
	b, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	pipe := s.client.TxPipeline()
	pipe.Set(ctx, k("rider", "loc", userID), b, 15*time.Minute)
	if loc.Lat >= -85.05112878 && loc.Lat <= 85.05112878 && loc.Lng >= -180 && loc.Lng <= 180 {
		pipe.GeoAdd(ctx, k("riders", "geo"), &goredis.GeoLocation{
			Name:      userID,
			Longitude: loc.Lng,
			Latitude:  loc.Lat,
		})
	}
	_, err = pipe.Exec(ctx)
	return err
}

// GetRiderLocation fetches a rider's recent location metadata from Redis.
func (s *Store) GetRiderLocation(ctx context.Context, userID string) (*RiderLocationRecord, bool, error) {
	b, err := s.client.Get(ctx, k("rider", "loc", userID)).Bytes()
	if errors.Is(err, goredis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	var rec RiderLocationRecord
	if err := json.Unmarshal(b, &rec); err != nil {
		return nil, false, err
	}
	return &rec, true, nil
}

// RemoveRiderLocation removes a rider from the active geospatial index when they go offline.
func (s *Store) RemoveRiderLocation(ctx context.Context, userID string) error {
	pipe := s.client.TxPipeline()
	pipe.ZRem(ctx, k("riders", "geo"), userID)
	pipe.Del(ctx, k("rider", "loc", userID))
	_, err := pipe.Exec(ctx)
	return err
}

// NearbyRiders queries the Redis geospatial index for riders within radiusM meters of center.
func (s *Store) NearbyRiders(ctx context.Context, center domain.LatLng, radiusM float64) ([]NearbyRider, error) {
	if radiusM <= 0 {
		radiusM = 20000000 // ~earth circumference when unlimited
	}
	locs, err := s.client.GeoSearchLocation(ctx, k("riders", "geo"), &goredis.GeoSearchLocationQuery{
		GeoSearchQuery: goredis.GeoSearchQuery{
			Longitude:  center.Lng,
			Latitude:   center.Lat,
			Radius:     radiusM,
			RadiusUnit: "m",
			Sort:       "ASC",
		},
		WithCoord: true,
		WithDist:  true,
	}).Result()
	if err != nil {
		return nil, err
	}
	out := make([]NearbyRider, 0, len(locs))
	for _, l := range locs {
		out = append(out, NearbyRider{
			UserID:    l.Name,
			Location:  domain.LatLng{Lat: l.Latitude, Lng: l.Longitude},
			DistanceM: int(l.Dist),
		})
	}
	return out, nil
}

// ---------- Merchant & Catalog Caching ----------

// CacheMerchant stores a merchant projection (with menu) in Redis.
func (s *Store) CacheMerchant(ctx context.Context, m domain.Merchant, ttl time.Duration) error {
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	return s.client.Set(ctx, k("cache", "merchant", m.ID), b, ttl).Err()
}

// GetCachedMerchant retrieves a cached merchant projection (with menu) from Redis.
func (s *Store) GetCachedMerchant(ctx context.Context, id string) (*domain.Merchant, bool, error) {
	b, err := s.client.Get(ctx, k("cache", "merchant", id)).Bytes()
	if errors.Is(err, goredis.Nil) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	var m domain.Merchant
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, false, err
	}
	return &m, true, nil
}

// InvalidateMerchantCache clears the cached merchant entry after store or menu updates.
func (s *Store) InvalidateMerchantCache(ctx context.Context, id string) error {
	return s.client.Del(ctx, k("cache", "merchant", id)).Err()
}

// ---------- WebSocket Pub/Sub Fan-out ----------

type wsPubSubEnvelope struct {
	InstanceID string          `json:"instance_id"`
	UserID     string          `json:"user_id"`
	App        string          `json:"app"`
	Type       string          `json:"type"`
	Data       json.RawMessage `json:"data"`
}

// PublishWSEvent publishes a real-time WebSocket event to Redis Pub/Sub so other server instances can deliver it.
func (s *Store) PublishWSEvent(ctx context.Context, instanceID, userID, app, typ string, data any) error {
	rawData, err := json.Marshal(data)
	if err != nil {
		return err
	}
	env := wsPubSubEnvelope{
		InstanceID: instanceID,
		UserID:     userID,
		App:        app,
		Type:       typ,
		Data:       rawData,
	}
	b, err := json.Marshal(env)
	if err != nil {
		return err
	}
	return s.client.Publish(ctx, k("ws", "events"), b).Err()
}

// SubscribeWSEvents listens on Redis Pub/Sub for WebSocket events from peer instances and delivers them locally.
func (s *Store) SubscribeWSEvents(ctx context.Context, instanceID string, deliver func(userID, app, typ string, data any)) {
	pubsub := s.client.Subscribe(ctx, k("ws", "events"))
	initCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	_, _ = pubsub.Receive(initCtx)
	cancel()
	ch := pubsub.Channel()
	go func() {
		defer pubsub.Close()
		for {
			select {
			case <-ctx.Done():
				return
			case msg, ok := <-ch:
				if !ok {
					return
				}
				var env wsPubSubEnvelope
				if err := json.Unmarshal([]byte(msg.Payload), &env); err != nil {
					continue
				}
				if env.InstanceID == instanceID || env.UserID == "" {
					continue
				}
				var decoded any
				_ = json.Unmarshal(env.Data, &decoded)
				deliver(env.UserID, env.App, env.Type, decoded)
			}
		}
	}()
}

// ---------- State Synchronization ----------

// Load populates active users, refresh tokens, and idempotency keys from Redis into the state cache.
func (s *Store) Load(ctx context.Context, st *repository.State) error {
	if s == nil || s.client == nil || st == nil {
		return nil
	}

	// Scan cached user profiles
	var cursor uint64
	userPrefix := k("user", "profile", "")
	for {
		keys, next, err := s.client.Scan(ctx, cursor, userPrefix+"*", 100).Result()
		if err != nil {
			return fmt.Errorf("scan redis users: %w", err)
		}
		for _, fullKey := range keys {
			uid := strings.TrimPrefix(fullKey, userPrefix)
			if u, ok, err := s.GetUser(ctx, uid); err == nil && ok && u != nil {
				if st.Users[u.ID] == nil {
					st.Users[u.ID] = u
					if u.Phone != "" {
						st.UserByPhone[u.Phone] = u.ID
					}
				}
			}
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}

	// Scan active refresh tokens
	cursor = 0
	prefix := k("refresh", "")
	for {
		keys, next, err := s.client.Scan(ctx, cursor, prefix+"*", 100).Result()
		if err != nil {
			return fmt.Errorf("scan redis refresh tokens: %w", err)
		}
		for _, fullKey := range keys {
			tokenHash := strings.TrimPrefix(fullKey, prefix)
			if revoked, err := s.IsTokenRevoked(ctx, "rt:"+tokenHash); err == nil && revoked {
				continue
			}
			if rt, ok, err := s.GetRefreshToken(ctx, tokenHash); err == nil && ok {
				st.Refresh[tokenHash] = rt
			}
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}

	// Scan active idempotency keys
	cursor = 0
	idemPrefix := k("idempotency", "")
	for {
		keys, next, err := s.client.Scan(ctx, cursor, idemPrefix+"*", 100).Result()
		if err != nil {
			return fmt.Errorf("scan redis idempotency keys: %w", err)
		}
		for _, fullKey := range keys {
			idemKey := strings.TrimPrefix(fullKey, idemPrefix)
			if val, err := s.client.Get(ctx, fullKey).Result(); err == nil && val != "" {
				st.Idempotency[idemKey] = val
			}
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}

	return nil
}

// Save synchronizes users, active refresh tokens, and idempotency keys from state to Redis.
func (s *Store) Save(ctx context.Context, st *repository.State) error {
	if s == nil || s.client == nil || st == nil {
		return nil
	}
	for _, u := range st.Users {
		if u == nil {
			continue
		}
		if revoked, err := s.IsTokenRevoked(ctx, "user:"+u.ID); err == nil && revoked {
			continue
		}
		if err := s.SaveUser(ctx, u); err != nil {
			return fmt.Errorf("save user to redis: %w", err)
		}
	}
	for tokenHash, rt := range st.Refresh {
		if time.Now().Before(rt.Expires) {
			if revoked, err := s.IsTokenRevoked(ctx, "rt:"+tokenHash); err == nil && revoked {
				delete(st.Refresh, tokenHash)
				continue
			}
			if revoked, err := s.IsTokenRevoked(ctx, "user:"+rt.UserID); err == nil && revoked {
				delete(st.Refresh, tokenHash)
				continue
			}
			if err := s.SaveRefreshToken(ctx, tokenHash, rt); err != nil {
				return fmt.Errorf("save refresh token to redis: %w", err)
			}
		}
	}
	for idemKey, targetID := range st.Idempotency {
		if err := s.SetIdempotency(ctx, idemKey, targetID, 24*time.Hour); err != nil {
			return fmt.Errorf("save idempotency to redis: %w", err)
		}
	}
	return nil
}
