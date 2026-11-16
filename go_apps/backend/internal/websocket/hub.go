package websocket

import (
	"encoding/json"
	"sync"

	"goapp/backend/internal/domain"
)

type Conn struct {
	UserID string
	App    string
	Out    chan []byte
}

type Hub struct {
	mu    sync.Mutex
	conns map[string]map[*Conn]bool // userID -> conns
}

func NewHub() *Hub {
	return &Hub{conns: map[string]map[*Conn]bool{}}
}

func (h *Hub) Add(c *Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[c.UserID] == nil {
		h.conns[c.UserID] = map[*Conn]bool{}
	}
	h.conns[c.UserID][c] = true
}

func (h *Hub) Remove(c *Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.conns[c.UserID], c)
}

// Send delivers `{type, id, data}` to every active socket of the target user for that app.
func (h *Hub) Send(userID, app, typ string, data any) {
	if userID == "" {
		return
	}
	msg, err := json.Marshal(map[string]any{"type": typ, "id": domain.NewID(), "data": data})
	if err != nil {
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	for c := range h.conns[userID] {
		if c.App != app {
			continue
		}
		select {
		case c.Out <- msg:
		default: // slow client: drop packet; client refetches over REST on reconnect
		}
	}
}

func (h *Hub) Count() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	n := 0
	for _, m := range h.conns {
		n += len(m)
	}
	return n
}
