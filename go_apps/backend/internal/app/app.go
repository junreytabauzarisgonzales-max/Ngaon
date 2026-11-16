package app

import (
	"database/sql"
	"net/http"
	"time"

	"goapp/backend/internal/api"
	"goapp/backend/internal/config"
	"goapp/backend/internal/domain"
	"goapp/backend/internal/repository"
	"goapp/backend/internal/repository/redis"
	"goapp/backend/internal/repository/seed"
	"goapp/backend/internal/service"
)

type Config = config.Config

type User = domain.User
type LatLng = domain.LatLng
type Stop = domain.Stop
type SavedPlace = domain.SavedPlace
type GeoPlace = domain.GeoPlace
type ServiceZone = domain.ServiceZone
type ServiceArea = domain.ServiceArea
type Vehicle = domain.Vehicle
type RiderProfile = domain.RiderProfile
type Rider = domain.Rider
type OpeningHours = domain.OpeningHours
type AddonOption = domain.AddonOption
type AddonGroup = domain.AddonGroup
type MenuItem = domain.MenuItem
type MenuCategory = domain.MenuCategory
type Merchant = domain.Merchant
type MerchantStaff = domain.MerchantStaff
type MerchantRow = domain.MerchantRow
type MerchantOrder = domain.MerchantOrder
type OrderLine = domain.OrderLine
type PabiliItem = domain.PabiliItem
type MerchantOrderState = domain.MerchantOrderState
type FareLine = domain.FareLine
type Fare = domain.Fare
type JobPayment = domain.JobPayment
type JobMerchant = domain.JobMerchant
type JobRider = domain.JobRider
type JobFood = domain.JobFood
type JobPabili = domain.JobPabili
type JobPadala = domain.JobPadala
type TimelineEntry = domain.TimelineEntry
type Job = domain.Job
type JobState = domain.JobState
type JobOffer = domain.JobOffer
type QuoteRequest = domain.QuoteRequest
type Quote = domain.Quote
type ChatMessage = domain.ChatMessage
type WalletTransaction = domain.WalletTransaction
type Topup = domain.Topup
type Payout = domain.Payout
type Rating = domain.Rating
type SOSAlert = domain.SOSAlert
type Device = domain.Device
type RefreshToken = domain.RefreshToken
type OTP = domain.OTP
type UTC = domain.UTC

type State = repository.State

func newID() string                 { return domain.NewID() }
func strp(s string) *string         { return domain.StrPtr(s) }
func intp(i int) *int               { return domain.IntPtr(i) }
func Now() domain.UTC               { return domain.Now() }
func at(t time.Time) *domain.UTC    { return domain.At(t) }
func newState() *State              { return repository.NewState() }
func manilaDate(t time.Time) string { return domain.ManilaDate(t) }

type Server struct {
	svc   *service.Service
	api   *api.API
	cfg   *config.Config
	st    *repository.State
	dirty bool
	db    *sql.DB
	redis *redis.Store
}

func NewServer(cfg Config) (*Server, error) {
	svc, err := service.New(cfg)
	if err != nil {
		return nil, err
	}
	a := api.New(svc)
	return &Server{
		svc:   svc,
		api:   a,
		cfg:   &svc.Cfg,
		st:    svc.St,
		db:    svc.DB,
		redis: svc.Redis,
	}, nil
}

func NewServerWithService(svc *service.Service) *Server {
	return &Server{
		svc:   svc,
		api:   api.New(svc),
		cfg:   &svc.Cfg,
		st:    svc.St,
		db:    svc.DB,
		redis: svc.Redis,
	}
}

func (s *Server) Close() {
	if s.svc != nil {
		s.svc.Close()
	}
}

func (s *Server) Routes() http.Handler {
	return s.api.Routes()
}

func (s *Server) lock()   { s.svc.Lock() }
func (s *Server) unlock() { s.svc.Unlock() }

func (s *Server) Tick() {
	s.svc.Tick()
}

func (s *Server) Save() {
	s.svc.Mu.Lock()
	if s.st != nil && s.svc.St != s.st {
		s.svc.St = s.st
	}
	if s.dirty {
		s.svc.Dirty = true
		s.dirty = false
	}
	s.svc.Mu.Unlock()
	s.svc.Save()
}

func (s *Server) seed() error {
	return seed.PopulateInitial(s.st, s.cfg.AnyLocation)
}
