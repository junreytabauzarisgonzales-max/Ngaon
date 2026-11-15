package app

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

type wsConn struct {
	userID string
	app    string
	out    chan []byte
}

type Hub struct {
	mu    sync.Mutex
	conns map[string]map[*wsConn]bool // userID -> conns
}

func newHub() *Hub { return &Hub{conns: map[string]map[*wsConn]bool{}} }

func (h *Hub) add(c *wsConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[c.userID] == nil {
		h.conns[c.userID] = map[*wsConn]bool{}
	}
	h.conns[c.userID][c] = true
}

func (h *Hub) remove(c *wsConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.conns[c.userID], c)
}

// send delivers `{type, id, data}` to every socket of the user in that app.
func (h *Hub) send(userID, app, typ string, data any) {
	msg, err := json.Marshal(map[string]any{"type": typ, "id": newID(), "data": data})
	if err != nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.conns[userID] {
		if c.app != app {
			continue
		}
		select {
		case c.out <- msg:
		default: // slow client: drop; it refetches over REST on reconnect
		}
	}
}

func (h *Hub) count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for _, m := range h.conns {
		n += len(m)
	}
	return n
}

// serveWS: `${WS_URL}/ws?token=<access_token>`. Expired token -> close 4001.
func (s *Server) serveWS(w http.ResponseWriter, r *http.Request) {
	claims, expired, err := s.parseJWT(r.URL.Query().Get("token"))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	if expired {
		ws.Close(4001, "token_expired")
		return
	}
	c := &wsConn{userID: claims.Sub, app: claims.App, out: make(chan []byte, 64)}
	s.hub.add(c)
	defer s.hub.remove(c)
	log.Printf("ws connected: %s (%s), %d sockets", s.userNameLocked(claims.Sub), claims.App, s.hub.count())

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	// Close with 4001 when the access token expires; the app refreshes and reconnects.
	expiry := time.Until(time.Unix(claims.Exp, 0))
	timer := time.AfterFunc(expiry, func() { ws.Close(4001, "token_expired"); cancel() })
	defer timer.Stop()

	go func() { // writer
		for {
			select {
			case <-ctx.Done():
				return
			case msg := <-c.out:
				wctx, wc := context.WithTimeout(ctx, 10*time.Second)
				err := ws.Write(wctx, websocket.MessageText, msg)
				wc()
				if err != nil {
					cancel()
					return
				}
			}
		}
	}()

	for { // reader
		_, data, err := ws.Read(ctx)
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
			s.hub.send(c.userID, c.app, "pong", map[string]any{})
		case "rider.location":
			var p struct {
				Location LatLng   `json:"location"`
				Heading  *float64 `json:"heading"`
			}
			if json.Unmarshal(m.Data, &p) == nil {
				s.lock()
				s.updateRiderLocation(c.userID, p.Location, p.Heading)
				s.unlock()
			}
		case "job.subscribe", "job.unsubscribe":
			// Customers already receive updates for their own jobs.
		}
	}
}

func (s *Server) userNameLocked(id string) string {
	s.lock()
	defer s.unlock()
	if n := s.userName(id); n != "" {
		return n
	}
	return id[:8]
}
