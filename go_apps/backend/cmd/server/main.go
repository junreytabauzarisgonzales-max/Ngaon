// Ngaon backend: implements API_CONTRACT.md for Go Customer, Go Rider and Go Merchant.
package main

import (
	"context"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"goapp/backend/internal/app"
	"goapp/backend/internal/config"
)

func main() {
	cfg := config.Load()
	s, err := app.NewServer(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer s.Close()

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           s.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       120 * time.Second,
		MaxHeaderBytes:    1 << 20,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		tick, save := time.NewTicker(time.Second), time.NewTicker(3*time.Second)
		defer tick.Stop()
		defer save.Stop()
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
		log.Printf("Ngaon API listening on :%s (public %s)", cfg.Port, cfg.PublicURL)
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
