package app

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"math"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

//go:embed seed/*.json
var seedFS embed.FS

type Config struct {
	Port               string
	PublicURL          string // e.g. http://192.168.2.194:8080 (what phones can reach)
	DataDir            string
	JWTSecret          []byte
	DevOTPCode         string // accepted for any phone when set (no SMS provider yet)
	AutoApproveSeconds int    // >0: rider applications auto-approve after N seconds
	RiderStartBalance  int    // centavos credited to new riders (dev)
	AdminToken         string
	AnyLocation        bool // dev: accept pickups/drop-offs anywhere (testing outside Bongao)
	MaxDispatchM       int  // max rider-to-pickup distance for offers; 0 = unlimited
}

type RefreshToken struct {
	UserID  string    `json:"user_id"`
	App     string    `json:"app"`
	Expires time.Time `json:"expires"`
}

type OTP struct {
	Code     string
	Expires  time.Time
	Attempts int
	Sent     []time.Time
}

type GeoPlace struct {
	Name     string `json:"name"`
	Address  string `json:"address"`
	Location LatLng `json:"location"`
}

type ServiceZone struct {
	ID      string   `json:"id"`
	Name    string   `json:"name"`
	Polygon []LatLng `json:"polygon"`
}

type ServiceArea struct {
	Zones []ServiceZone `json:"zones"`
}

// State is everything the backend knows. Persisted as JSON (dev storage).
type State struct {
	Users       map[string]*User          `json:"users"`
	UserByPhone map[string]string         `json:"user_by_phone"`
	Places      map[string]*SavedPlace    `json:"places"`
	Merchants   map[string]*MerchantRow   `json:"merchants"`
	MerchantIDs []string                  `json:"merchant_ids"`
	Staff       map[string]MerchantStaff  `json:"staff"` // by phone
	Quotes      map[string]*Quote         `json:"-"`
	QuoteReqs   map[string]*QuoteRequest  `json:"-"`
	Jobs        map[string]*JobState      `json:"jobs"`
	JobIDs      []string                  `json:"job_ids"` // creation order
	Riders      map[string]*Rider         `json:"riders"`  // by user id
	Offers      map[string]*JobOffer      `json:"-"`
	Txs         []*WalletTransaction      `json:"txs"`
	Chats       map[string][]*ChatMessage `json:"chats"`
	Payouts     []*Payout                 `json:"payouts"`
	Topups      map[string]*Topup         `json:"topups"`
	Devices     map[string]Device         `json:"devices"`
	Refresh     map[string]RefreshToken   `json:"refresh"`
	Idempotency map[string]string         `json:"idempotency"`
	Ratings     []Rating                  `json:"ratings"`
	SOS         []SOSAlert                `json:"sos"`
	CodeSeq     int                       `json:"code_seq"`
	Uploads     map[string]string         `json:"uploads"` // key -> purpose
	Shares      map[string]string         `json:"shares"`  // token -> job id
	OTPs        map[string]*OTP           `json:"-"`
	GeoPlaces   []GeoPlace                `json:"-"`
	ServiceArea ServiceArea               `json:"-"`
}

type Server struct {
	cfg     Config
	mu      sync.Mutex
	st      *State
	dirty   bool
	pending []outEvent
	hub     *Hub
}

type outEvent struct {
	UserID string
	App    string
	Type   string
	Data   any
}

func NewServer(cfg Config) (*Server, error) {
	s := &Server{cfg: cfg, hub: newHub()}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

// lock / unlock: events produced while holding the lock are delivered after.
func (s *Server) lock() { s.mu.Lock() }

func (s *Server) unlock() {
	evs := s.pending
	s.pending = nil
	s.mu.Unlock()
	for _, e := range evs {
		s.hub.send(e.UserID, e.App, e.Type, e.Data)
	}
}

func (s *Server) emit(userID, app, typ string, data any) {
	if userID == "" {
		return
	}
	s.pending = append(s.pending, outEvent{userID, app, typ, data})
}

func (s *Server) touch() { s.dirty = true }

// ---------- persistence ----------

func (s *Server) statePath() string { return filepath.Join(s.cfg.DataDir, "state.json") }

func newState() *State {
	return &State{
		Users: map[string]*User{}, UserByPhone: map[string]string{}, Places: map[string]*SavedPlace{},
		Merchants: map[string]*MerchantRow{}, Staff: map[string]MerchantStaff{}, Quotes: map[string]*Quote{},
		QuoteReqs: map[string]*QuoteRequest{}, Jobs: map[string]*JobState{}, Riders: map[string]*Rider{},
		Offers: map[string]*JobOffer{}, Chats: map[string][]*ChatMessage{}, Topups: map[string]*Topup{},
		Devices: map[string]Device{}, Refresh: map[string]RefreshToken{}, Idempotency: map[string]string{},
		OTPs: map[string]*OTP{}, Uploads: map[string]string{}, Shares: map[string]string{}, CodeSeq: 4900,
	}
}

func (s *Server) load() error {
	_ = os.MkdirAll(filepath.Join(s.cfg.DataDir, "uploads"), 0o755)
	st := newState()
	if b, err := os.ReadFile(s.statePath()); err == nil {
		if err := json.Unmarshal(b, st); err != nil {
			return fmt.Errorf("state.json: %w", err)
		}
		// maps that may be absent in older snapshots
		fresh := newState()
		if st.Quotes == nil {
			st.Quotes = fresh.Quotes
		}
		if st.QuoteReqs == nil {
			st.QuoteReqs = fresh.QuoteReqs
		}
		if st.Offers == nil {
			st.Offers = fresh.Offers
		}
		if st.OTPs == nil {
			st.OTPs = fresh.OTPs
		}
		if st.Uploads == nil {
			st.Uploads = fresh.Uploads
		}
		if st.Shares == nil {
			st.Shares = fresh.Shares
		}
		log.Printf("loaded state: %d users, %d jobs, %d riders", len(st.Users), len(st.Jobs), len(st.Riders))
	} else {
		log.Printf("no state.json, seeding")
	}
	s.st = st
	if err := s.seed(); err != nil {
		return err
	}
	// Riders can't stay "online" across a restart without a live socket.
	for _, r := range st.Riders {
		r.Profile.IsOnline = false
	}
	return nil
}

func (s *Server) Save() {
	s.mu.Lock()
	if !s.dirty {
		s.mu.Unlock()
		return
	}
	b, err := json.Marshal(s.st)
	s.dirty = false
	s.mu.Unlock()
	if err != nil {
		log.Printf("save: %v", err)
		return
	}
	tmp := s.statePath() + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err == nil {
		_ = os.Rename(tmp, s.statePath())
	}
}

// ---------- seed ----------

func readSeed(name string, v any) error {
	b, err := seedFS.ReadFile("seed/" + name)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// Owner phones for the seeded merchants (log into Go Merchant with these).
var seedMerchantPhones = []string{"+639193334444", "+639193334445", "+639193334446", "+639193334447", "+639193334448"}
var seedStaffNames = []string{"Mering", "Pantay staff", "Sitti", "Tiula staff", "Bud staff"}

func (s *Server) seed() error {
	st := s.st
	if err := readSeed("geo_places.json", &st.GeoPlaces); err != nil {
		return err
	}
	if err := readSeed("service_area.json", &st.ServiceArea); err != nil {
		return err
	}
	if s.cfg.AnyLocation {
		st.ServiceArea = ServiceArea{Zones: []ServiceZone{{ID: "dev-anywhere", Name: "Anywhere (dev)", Polygon: []LatLng{{85, -179.9}, {85, 179.9}, {-85, 179.9}, {-85, -179.9}}}}}
	}
	if len(st.Merchants) == 0 {
		var ms []Merchant
		if err := readSeed("merchants.json", &ms); err != nil {
			return err
		}
		for i, m := range ms {
			m := m
			m.DistanceM = nil
			phone := seedMerchantPhones[i%len(seedMerchantPhones)]
			st.Merchants[m.ID] = &MerchantRow{Merchant: m, Phone: phone}
			st.MerchantIDs = append(st.MerchantIDs, m.ID)
			st.Staff[phone] = MerchantStaff{UserPhone: phone, MerchantID: m.ID, Role: "owner", StaffName: seedStaffNames[i%len(seedStaffNames)]}
		}
		var ps []*Payout
		if err := readSeed("payouts.json", &ps); err == nil && len(st.MerchantIDs) > 0 {
			for _, p := range ps {
				p.MerchantID = st.MerchantIDs[0]
			}
			st.Payouts = ps
		}
		s.touch()
	}
	return nil
}

// ---------- helpers ----------

func newID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b)
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

func randToken(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (s *Server) nextCode() string {
	s.st.CodeSeq++
	return fmt.Sprintf("GO-%d", s.st.CodeSeq)
}

func (s *Server) fileURL(key string) *string {
	if key == "" {
		return nil
	}
	u := strings.TrimRight(s.cfg.PublicURL, "/") + "/files/" + key
	return &u
}

func maskPhone(e164 string) string {
	if !strings.HasPrefix(e164, "+63") || len(e164) != 13 {
		return e164
	}
	l := e164[3:]
	return "+63 " + l[:3] + " ••• " + l[6:]
}

func strp(s string) *string { return &s }
func intp(i int) *int       { return &i }

func distanceM(a, b LatLng) int {
	const r = 6371000.0
	rad := func(d float64) float64 { return d * math.Pi / 180 }
	dLat, dLng := rad(b.Lat-a.Lat), rad(b.Lng-a.Lng)
	h := math.Pow(math.Sin(dLat/2), 2) + math.Cos(rad(a.Lat))*math.Cos(rad(b.Lat))*math.Pow(math.Sin(dLng/2), 2)
	return int(math.Round(2 * r * math.Asin(math.Sqrt(h))))
}

func (z ServiceZone) contains(p LatLng) bool {
	in := false
	poly := z.Polygon
	for i, j := 0, len(poly)-1; i < len(poly); j, i = i, i+1 {
		a, b := poly[i], poly[j]
		if (a.Lat > p.Lat) != (b.Lat > p.Lat) && p.Lng < (b.Lng-a.Lng)*(p.Lat-a.Lat)/(b.Lat-a.Lat)+a.Lng {
			in = !in
		}
	}
	return in
}

func (s *Server) inServiceArea(p LatLng) bool {
	if s.cfg.AnyLocation {
		return true
	}
	for _, z := range s.st.ServiceArea.Zones {
		if z.contains(p) {
			return true
		}
	}
	return false
}

// Manila is UTC+8, no DST.
var manila = time.FixedZone("Asia/Manila", 8*3600)

func manilaDate(t time.Time) string { return t.In(manila).Format("2006-01-02") }

func firstName(name string) string {
	f := strings.Fields(name)
	if len(f) == 0 {
		return "Customer"
	}
	return f[0]
}

func deepCopy[T any](v T) T {
	b, _ := json.Marshal(v)
	var out T
	_ = json.Unmarshal(b, &out)
	return out
}
