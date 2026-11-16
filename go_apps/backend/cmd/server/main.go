// Ngain backend: implements API_CONTRACT.md for Go Customer, Go Rider and Go Merchant.
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"goapp/backend/internal/app"
)

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

func main() {
	cfg := app.Config{
		Port:               env("PORT", "8080"),
		PublicURL:          env("PUBLIC_URL", "http://localhost:8080"),
		DataDir:            env("DATA_DIR", "./data"),
		JWTSecret:          []byte(env("JWT_SECRET", "dev-only-change-me")),
		DevOTPCode:         os.Getenv("DEV_OTP_CODE"),
		AutoApproveSeconds: envInt("AUTO_APPROVE_RIDERS_SECONDS", 0),
		RiderStartBalance:  envInt("RIDER_START_BALANCE", 0),
		AdminToken:         env("ADMIN_TOKEN", "change-me"),
		AnyLocation:        os.Getenv("DEV_ANY_LOCATION") == "true",
		MaxDispatchM:       envInt("MAX_DISPATCH_M", 15000),
		Maps: app.MapsConfig{
			APIKey:     os.Getenv("GOOGLE_MAPS_API_KEY"),
			TravelMode: env("GOOGLE_ROUTES_TRAVEL_MODE", "TWO_WHEELER"),
		},
		Didit: app.DiditConfig{
			APIKey:        os.Getenv("DIDIT_API_KEY"),
			WorkflowID:    os.Getenv("DIDIT_WORKFLOW_ID"),
			WebhookSecret: os.Getenv("DIDIT_WEBHOOK_SECRET"),
			BaseURL:       env("DIDIT_BASE_URL", "https://verification.didit.me"),
		},
		PayMongo: app.PayMongoConfig{
			SecretKey:     os.Getenv("PAYMONGO_SECRET_KEY"),
			WebhookSecret: os.Getenv("PAYMONGO_WEBHOOK_SECRET"),
			BaseURL:       env("PAYMONGO_BASE_URL", "https://api.paymongo.com"),
		},
	}
	s, err := app.NewServer(cfg)
	if err != nil {
		log.Fatal(err)
	}
	srv := &http.Server{Addr: ":" + cfg.Port, Handler: s.Routes(), ReadHeaderTimeout: 10 * time.Second}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		tick, save := time.NewTicker(time.Second), time.NewTicker(3*time.Second)
		for {
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
				s.Tick()
			case <-save.C:
				s.Save()
			}
		}
	}()
	go func() {
		log.Printf("Ngain API listening on :%s (public %s)", cfg.Port, cfg.PublicURL)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()
	<-ctx.Done()
	sctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(sctx)
	s.Save()
	log.Print("state saved, bye")
}
