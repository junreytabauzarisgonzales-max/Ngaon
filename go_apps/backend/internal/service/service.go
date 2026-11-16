package service

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"goapp/backend/internal/config"
	"goapp/backend/internal/domain"
	"goapp/backend/internal/repository"
	"goapp/backend/internal/repository/file"
	"goapp/backend/internal/repository/postgres"
	"goapp/backend/internal/repository/redis"
	"goapp/backend/internal/repository/seed"
	"goapp/backend/internal/websocket"
)

type OutEvent struct {
	UserID string
	App    string
	Type   string
	Data   any
}

type Service struct {
	Cfg        config.Config
	Mu         sync.Mutex
	St         *repository.State
	Dirty      bool
	Pending    []OutEvent
	Hub        *websocket.Hub
	DB         *sql.DB
	Redis      *redis.Store
	InstanceID string

	revokedMu     sync.Mutex
	revokedTokens map[string]time.Time

	rateMu      sync.Mutex
	rateBuckets map[string]*memRateBucket

	subCancel context.CancelFunc
}

func New(cfg config.Config) (*Service, error) {
	if cfg.CORSAllowedOrigins == "" {
		cfg.CORSAllowedOrigins = "*"
	}
	if cfg.RateLimitPerMin <= 0 {
		cfg.RateLimitPerMin = 300
	}
	if cfg.AuthRateLimitPerMin <= 0 {
		cfg.AuthRateLimitPerMin = 30
	}

	s := &Service{
		Cfg:           cfg,
		Hub:           websocket.NewHub(),
		St:            repository.NewState(),
		InstanceID:    domain.NewID(),
		revokedTokens: map[string]time.Time{},
		rateBuckets:   map[string]*memRateBucket{},
	}

	_ = os.MkdirAll(filepath.Join(cfg.DataDir, "uploads"), 0o755)

	if cfg.DatabaseURL != "" {
		db, err := postgres.Connect(cfg.DatabaseURL)
		if err != nil {
			return nil, fmt.Errorf("postgres connect: %w", err)
		}
		s.DB = db
		if err := postgres.Load(db, s.St, cfg.AnyLocation); err != nil {
			return nil, fmt.Errorf("load postgres: %w", err)
		}
	} else {
		statePath := filepath.Join(cfg.DataDir, "state.json")
		if err := file.Load(statePath, s.St); err == nil {
			log.Printf("loaded state from file: %d users, %d jobs, %d riders", len(s.St.Users), len(s.St.Jobs), len(s.St.Riders))
			if err := seed.PopulateInitial(s.St, cfg.AnyLocation); err != nil {
				return nil, err
			}
		} else {
			log.Printf("no state.json found, seeding initial fixtures")
			if err := seed.PopulateInitial(s.St, cfg.AnyLocation); err != nil {
				return nil, err
			}
		}
	}

	if cfg.RedisURL != "" {
		rdb, err := redis.Connect(cfg.RedisURL)
		if err != nil {
			if s.DB != nil {
				_ = s.DB.Close()
			}
			return nil, fmt.Errorf("redis connect: %w", err)
		}
		s.Redis = rdb
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := s.Redis.Load(ctx, s.St); err != nil {
			cancel()
			_ = s.Redis.Close()
			return nil, fmt.Errorf("load redis: %w", err)
		}
		cancel()

		subCtx, subCancel := context.WithCancel(context.Background())
		s.subCancel = subCancel
		s.Redis.SubscribeWSEvents(subCtx, s.InstanceID, func(userID, app, typ string, data any) {
			s.Hub.Send(userID, app, typ, data)
		})
	}

	// Riders can't stay "online" across a server restart without a live socket.
	for _, r := range s.St.Riders {
		r.Profile.IsOnline = false
	}

	return s, nil
}

// Close releases database, Redis, and Pub/Sub resources.
func (s *Service) Close() {
	if s.subCancel != nil {
		s.subCancel()
	}
	if s.Redis != nil {
		_ = s.Redis.Close()
	}
	if s.DB != nil {
		_ = s.DB.Close()
	}
}

// Lock / Unlock: events produced while holding the lock are delivered after unlock.
func (s *Service) Lock() { s.Mu.Lock() }

func (s *Service) Unlock() {
	evs := s.Pending
	s.Pending = nil
	s.Mu.Unlock()
	for _, e := range evs {
		s.Hub.Send(e.UserID, e.App, e.Type, e.Data)
		if s.Redis != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			_ = s.Redis.PublishWSEvent(ctx, s.InstanceID, e.UserID, e.App, e.Type, e.Data)
			cancel()
		}
	}
}

func (s *Service) Emit(userID, app, typ string, data any) {
	if userID == "" {
		return
	}
	s.Pending = append(s.Pending, OutEvent{UserID: userID, App: app, Type: typ, Data: data})
}

func (s *Service) Touch() { s.Dirty = true }

func (s *Service) FileURL(key string) *string {
	if key == "" {
		return nil
	}
	u := strings.TrimRight(s.Cfg.PublicURL, "/") + "/files/" + key
	return &u
}

func (s *Service) NextCode() string {
	s.St.CodeSeq++
	return fmt.Sprintf("GO-%d", s.St.CodeSeq)
}

// EnsureUserLocked verifies that userID exists and has not been revoked across instances.
// Must be called while holding s.Mu.
func (s *Service) EnsureUserLocked(userID string) bool {
	if userID == "" {
		return false
	}
	s.revokedMu.Lock()
	if exp, revoked := s.revokedTokens["user:"+userID]; revoked && time.Now().Before(exp) {
		s.revokedMu.Unlock()
		delete(s.St.Users, userID)
		return false
	}
	s.revokedMu.Unlock()

	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		revoked, err := s.Redis.IsTokenRevoked(ctx, "user:"+userID)
		if err == nil && revoked {
			cancel()
			if u := s.St.Users[userID]; u != nil {
				delete(s.St.UserByPhone, u.Phone)
				delete(s.St.Users, userID)
			}
			return false
		}
		if s.St.Users[userID] == nil {
			if u, ok, gErr := s.Redis.GetUser(ctx, userID); gErr == nil && ok && u != nil {
				s.St.Users[u.ID] = u
				if u.Phone != "" {
					s.St.UserByPhone[u.Phone] = u.ID
				}
			}
		}
		cancel()
	}
	return s.St.Users[userID] != nil
}

func (s *Service) UserName(id string) string {
	if u := s.St.Users[id]; u != nil {
		return u.Name
	}
	return ""
}

func (s *Service) UserNameLocked(id string) string {
	s.Lock()
	defer s.Unlock()
	if n := s.UserName(id); n != "" {
		return n
	}
	if len(id) >= 8 {
		return id[:8]
	}
	return id
}

func (s *Service) MerchantUserIDs(merchantID string) []string {
	var ids []string
	for phone, st := range s.St.Staff {
		if st.MerchantID == merchantID {
			if uid, ok := s.St.UserByPhone[phone]; ok {
				ids = append(ids, uid)
			}
		}
	}
	return ids
}

func (s *Service) PublishJob(js *domain.JobState) {
	js.Job.UpdatedAt = domain.Now()
	s.Touch()
	s.Emit(js.CustomerID, "customer", "job.updated", map[string]any{"job": s.JobView(js, "customer")})
	if js.RiderUserID != "" {
		s.Emit(js.RiderUserID, "rider", "job.updated", map[string]any{"job": s.JobView(js, "rider")})
	}
	if js.Order != nil && js.MerchantID != "" {
		ov := s.OrderView(js)
		for _, uid := range s.MerchantUserIDs(js.MerchantID) {
			s.Emit(uid, "merchant", "order.updated", map[string]any{"order": ov})
		}
	}
}

func (s *Service) SetStatus(js *domain.JobState, status string) {
	js.Job.Status = status
	js.Job.Timeline = append(js.Job.Timeline, domain.TimelineEntry{Status: status, At: domain.Now()})
	if status == "searching" {
		js.SearchingSince = time.Now()
	}
	if js.Order != nil {
		js.Order.Status = MerchantOrderStatus(js)
	}
	s.PublishJob(js)
}

func (s *Service) JobView(js *domain.JobState, app string) domain.Job {
	var loc *domain.LatLng
	if r := s.St.Riders[js.RiderUserID]; r != nil && r.Location != nil {
		loc = r.Location
	} else if js.RiderUserID != "" && s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
		if rec, ok, err := s.Redis.GetRiderLocation(ctx, js.RiderUserID); err == nil && ok && rec != nil {
			loc = &rec.Location
			if r := s.St.Riders[js.RiderUserID]; r != nil {
				r.Location = &rec.Location
				r.LocationAt = rec.UpdatedAt
			}
		}
		cancel()
	}
	return JobView(js, app, loc)
}

func (s *Service) OrderView(js *domain.JobState) domain.MerchantOrder {
	return OrderView(js, s.UserName(js.CustomerID))
}

func (s *Service) Cancel(js *domain.JobState, cancelledBy, reason string) {
	js.Job.CancelledBy = &cancelledBy
	js.Job.CancelReason = &reason
	if js.Job.Payment.Status == "paid" {
		js.Job.Payment.Status = "refunded"
	}
	if js.Order != nil {
		js.Order.Status = "rejected"
	}
	if r := s.St.Riders[js.RiderUserID]; r != nil && r.ActiveJobID == js.Job.ID {
		r.ActiveJobID = ""
	}
	for id, o := range s.St.Offers {
		if o.JobID == js.Job.ID {
			delete(s.St.Offers, id)
			if s.Redis != nil {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				_ = s.Redis.DeleteOffer(ctx, id, o.RiderUserID)
				cancel()
			}
			s.Emit(o.RiderUserID, "rider", "offer.expired", map[string]any{"offer_id": id})
		}
	}
	s.SetStatus(js, "cancelled")
}

func (s *Service) InServiceArea(p domain.LatLng) bool {
	return s.St.ServiceArea.InServiceArea(p, s.Cfg.AnyLocation)
}

func (s *Service) AfterPayment(js *domain.JobState) {
	if js.Job.Service == "food" {
		js.MerchantDeadline = time.Now().Add(3 * time.Minute)
		s.SetStatus(js, "merchant_pending")
		ov := s.OrderView(js)
		for _, uid := range s.MerchantUserIDs(js.MerchantID) {
			s.Emit(uid, "merchant", "order.new", map[string]any{"order": ov})
		}
		return
	}
	s.SetStatus(js, "searching")
	s.Dispatch(js)
}

func (s *Service) SystemMessage(js *domain.JobState, text string) {
	m := &domain.ChatMessage{ID: domain.NewID(), JobID: js.Job.ID, Sender: "system", Text: domain.StrPtr(text), CreatedAt: domain.Now()}
	s.St.Chats[js.Job.ID] = append(s.St.Chats[js.Job.ID], m)
	s.Emit(js.CustomerID, "customer", "chat.message", map[string]any{"message": m})
	if js.RiderUserID != "" {
		s.Emit(js.RiderUserID, "rider", "chat.message", map[string]any{"message": m})
	}
}

func (s *Service) SetRiderReview(rd *domain.Rider, approve bool, reason string) {
	if approve {
		rd.Profile.Status = "approved"
		rd.Profile.RejectionReason = nil
	} else {
		rd.Profile.Status = "rejected"
		rd.Profile.RejectionReason = domain.StrPtr(reason)
	}
	s.Touch()
	log.Printf("rider %s %s", s.UserName(rd.Profile.UserID), rd.Profile.Status)
	s.Emit(rd.Profile.UserID, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
}

func (s *Service) UpdateRiderLocation(userID string, loc domain.LatLng, heading *float64) {
	rd := s.St.Riders[userID]
	if rd == nil {
		return
	}
	rd.Location = &loc
	rd.LocationAt = time.Now()
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_ = s.Redis.UpdateRiderLocation(ctx, userID, loc, heading)
		cancel()
	}
	s.Touch()
	if rd.ActiveJobID != "" {
		if js := s.St.Jobs[rd.ActiveJobID]; js != nil && IsLive(js.Job.Status) {
			s.Emit(js.CustomerID, "customer", "rider.location", map[string]any{
				"job_id":   js.Job.ID,
				"location": loc,
				"heading":  heading,
			})
		}
	}
}

func (s *Service) Save() {
	s.Mu.Lock()
	defer s.Mu.Unlock()
	if !s.Dirty {
		return
	}
	s.Dirty = false

	if s.DB != nil {
		if err := postgres.Save(s.DB, s.St); err != nil {
			log.Printf("save postgres: %v", err)
		}
	}
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		if err := s.Redis.Save(ctx, s.St); err != nil {
			log.Printf("save redis: %v", err)
		}
		cancel()
	}
	if s.Cfg.DataDir != "" {
		statePath := filepath.Join(s.Cfg.DataDir, "state.json")
		if err := file.Save(statePath, s.St); err != nil {
			log.Printf("save file: %v", err)
		}
	}
}

func (s *Service) AddTx(uid, typ string, amount int, jobID, note string) {
	rd := s.St.Riders[uid]
	if rd == nil {
		return
	}
	rd.Profile.BalanceCentavos += amount
	tx := &domain.WalletTransaction{
		ID:                   domain.NewID(),
		UserID:               uid,
		Type:                 typ,
		AmountCentavos:       amount,
		BalanceAfterCentavos: rd.Profile.BalanceCentavos,
		CreatedAt:            domain.Now(),
		Note:                 domain.StrPtr(note),
	}
	if jobID != "" {
		tx.JobID = domain.StrPtr(jobID)
	}
	s.St.Txs = append(s.St.Txs, tx)
	s.Touch()
}

func (s *Service) Settle(js *domain.JobState) {
	uid := js.RiderUserID
	jid := js.Job.ID
	if js.Job.Payment.Method == "cash" {
		cut := js.CommissionCentavos
		note := "Commission " + js.Job.Code
		if js.Order != nil {
			cut += js.Order.Commission
			note += " (incl. merchant fee)"
		}
		s.AddTx(uid, "commission", -cut, jid, note)
	} else {
		credit := js.EarningsCentavos
		if js.Job.Pabili != nil && js.Job.Pabili.ItemTotalCentavos != nil {
			credit += *js.Job.Pabili.ItemTotalCentavos
		}
		s.AddTx(uid, "earning", credit, jid, "Earnings "+js.Job.Code)
	}
	if rd := s.St.Riders[uid]; rd != nil {
		s.Emit(uid, "rider", "rider.profile_updated", map[string]any{"profile": rd.Profile})
	}
}
