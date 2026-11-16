package config

import (
	"os"
	"strconv"
)

// Config holds all configuration options for the Go backend service.
type MapsConfig struct {
	APIKey     string
	TravelMode string
	RoutesURL  string
	GeocodeURL string
	PlacesURL  string
}

type DiditConfig struct {
	APIKey        string
	WorkflowID    string
	WebhookSecret string
	BaseURL       string
}

type PayMongoConfig struct {
	SecretKey     string
	WebhookSecret string
	BaseURL       string
}

type InfobipConfig struct {
	APIKey   string
	BaseURL  string
	SenderID string
}

type Config struct {
	Port                string
	PublicURL           string // e.g. http://192.168.2.194:8080 (what phones can reach)
	DataDir             string
	DatabaseURL         string // PostgreSQL connection URL (e.g. postgres://user:pass@host:5432/db?sslmode=disable)
	RedisURL            string // Redis connection URL (e.g. redis://:password@host:6379/0)
	JWTSecret           []byte
	DevOTPCode          string // accepted for any phone when set (no SMS provider yet)
	AutoApproveSeconds  int    // >0: rider applications auto-approve after N seconds
	RiderStartBalance   int    // centavos credited to new riders (dev)
	AdminToken          string
	AnyLocation         bool   // dev: accept pickups/drop-offs anywhere (testing outside Bongao)
	MaxDispatchM        int    // max rider-to-pickup distance for offers; 0 = unlimited
	CORSAllowedOrigins  string // comma-separated allowed origins or "*"
	TrustedProxies      string // comma-separated trusted reverse-proxy IPs/CIDRs (or "*") for X-Forwarded-For
	RateLimitPerMin     int    // general API requests per minute per IP (default 300)
	AuthRateLimitPerMin int    // auth/OTP requests per minute per IP (default 30)
	Maps                MapsConfig
	Didit               DiditConfig
	PayMongo            PayMongoConfig
	Infobip             InfobipConfig
	GoogleClientID      string
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt(k string, def int) int {
	if n, err := strconv.Atoi(os.Getenv(k)); err == nil {
		return n
	}
	return def
}

// Load loads configuration from environment variables with sensible defaults.
func Load() Config {
	return Config{
		Port:                env("PORT", "8080"),
		PublicURL:           env("PUBLIC_URL", "http://localhost:8080"),
		DataDir:             env("DATA_DIR", "./data"),
		DatabaseURL:         env("DATABASE_URL", ""),
		RedisURL:            env("REDIS_URL", ""),
		JWTSecret:           []byte(env("JWT_SECRET", "dev-only-change-me")),
		DevOTPCode:          os.Getenv("DEV_OTP_CODE"),
		AutoApproveSeconds:  envInt("AUTO_APPROVE_RIDERS_SECONDS", 0),
		RiderStartBalance:   envInt("RIDER_START_BALANCE", 0),
		AdminToken:          env("ADMIN_TOKEN", "change-me"),
		AnyLocation:         os.Getenv("DEV_ANY_LOCATION") == "true",
		MaxDispatchM:        envInt("MAX_DISPATCH_M", 15000),
		CORSAllowedOrigins:  env("CORS_ALLOWED_ORIGINS", "*"),
		TrustedProxies:      env("TRUSTED_PROXIES", ""),
		RateLimitPerMin:     envInt("RATE_LIMIT_PER_MIN", 300),
		AuthRateLimitPerMin: envInt("AUTH_RATE_LIMIT_PER_MIN", 30),
		Maps: MapsConfig{
			APIKey:     os.Getenv("GOOGLE_MAPS_API_KEY"),
			TravelMode: env("GOOGLE_ROUTES_TRAVEL_MODE", "TWO_WHEELER"),
		},
		Didit: DiditConfig{
			APIKey:        os.Getenv("DIDIT_API_KEY"),
			WorkflowID:    os.Getenv("DIDIT_WORKFLOW_ID"),
			WebhookSecret: os.Getenv("DIDIT_WEBHOOK_SECRET"),
			BaseURL:       env("DIDIT_BASE_URL", "https://verification.didit.me"),
		},
		PayMongo: PayMongoConfig{
			SecretKey:     os.Getenv("PAYMONGO_SECRET_KEY"),
			WebhookSecret: os.Getenv("PAYMONGO_WEBHOOK_SECRET"),
			BaseURL:       env("PAYMONGO_BASE_URL", "https://api.paymongo.com"),
		},
		Infobip: InfobipConfig{
			APIKey:   os.Getenv("INFOBIP_API_KEY"),
			BaseURL:  env("INFOBIP_BASE_URL", "https://w4z2vr.api.infobip.com"),
			SenderID: env("INFOBIP_SENDER_ID", "Ngaon"),
		},
		GoogleClientID: os.Getenv("GOOGLE_CLIENT_ID"),
	}
}
