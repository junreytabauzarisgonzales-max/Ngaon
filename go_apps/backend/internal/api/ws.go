package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"goapp/backend/internal/domain"
	ws "goapp/backend/internal/websocket"
)

// ServeWS: `${WS_URL}/ws?token=<access_token>`. Closes with 4001 on token expiration.
func (a *API) ServeWS(w http.ResponseWriter, r *http.Request) {
	claims, expired, err := a.svc.ParseJWT(r.URL.Query().Get("token"))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	if !expired {
		a.svc.Lock()
		userExists := a.svc.EnsureUserLocked(claims.Sub)
		a.svc.Unlock()
		if !userExists {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
	}
	rc := http.NewResponseController(w)
	_ = rc.SetReadDeadline(time.Time{})
	_ = rc.SetWriteDeadline(time.Time{})
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	conn.SetReadLimit(64 << 10)
	if expired {
		conn.Close(4001, "token_expired")
		return
	}
	c := &ws.Conn{UserID: claims.Sub, App: claims.App, Out: make(chan []byte, 64)}
	a.svc.Hub.Add(c)
	defer a.svc.Hub.Remove(c)
	log.Printf("ws connected: %s (%s), %d sockets", a.svc.UserNameLocked(claims.Sub), claims.App, a.svc.Hub.Count())

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	expiry := time.Until(time.Unix(claims.Exp, 0))
	timer := time.AfterFunc(expiry, func() { conn.Close(4001, "token_expired"); cancel() })
	defer timer.Stop()

	go func() { // writer
		for {
			select {
			case <-ctx.Done():
				return
			case msg := <-c.Out:
				wctx, wc := context.WithTimeout(ctx, 10*time.Second)
				err := conn.Write(wctx, websocket.MessageText, msg)
				wc()
				if err != nil {
					cancel()
					return
				}
			}
		}
	}()

	for { // reader
		_, data, err := conn.Read(ctx)
		if err != nil {
			return
		}
		var m struct {
			Type string          `json:"type"`
			Data json.RawMessage `json:"data"`
		}
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		switch m.Type {
		case "ping":
			a.svc.Hub.Send(c.UserID, c.App, "pong", map[string]any{})
		case "rider.location":
			var p struct {
				Location domain.LatLng `json:"location"`
				Heading  *float64      `json:"heading"`
			}
			if json.Unmarshal(m.Data, &p) == nil && p.Location.Lat >= -90 && p.Location.Lat <= 90 && p.Location.Lng >= -180 && p.Location.Lng <= 180 {
				a.svc.Lock()
				a.svc.UpdateRiderLocation(c.UserID, p.Location, p.Heading)
				a.svc.Unlock()
			}
		case "job.subscribe", "job.unsubscribe":
			// Subscription is automatic for personal jobs
		}
	}
}
