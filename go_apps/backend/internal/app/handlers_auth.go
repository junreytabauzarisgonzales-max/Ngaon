package app

import (
	"crypto/rand"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

var phoneRe = regexp.MustCompile(`^\+639\d{9}$`)
var appRe = regexp.MustCompile(`^(customer|rider|merchant)$`)

func randomOTP() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	return fmt.Sprintf("%06d", n.Int64())
}

func (s *Server) otpRequest(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Phone string `json:"phone"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if !phoneRe.MatchString(b.Phone) {
		return fieldErr("phone", "invalid", "Invalid PH mobile number")
	}
	s.lock()
	defer s.unlock()
	o := s.st.OTPs[b.Phone]
	if o == nil {
		o = &OTP{}
		s.st.OTPs[b.Phone] = o
	}
	recent := o.Sent[:0]
	for _, t := range o.Sent {
		if time.Since(t) < 10*time.Minute {
			recent = append(recent, t)
		}
	}
	o.Sent = recent
	if len(o.Sent) >= 5 {
		return apiErr(429, "rate_limited", "Too many codes requested")
	}
	o.Code = randomOTP()
	o.Expires = time.Now().Add(5 * time.Minute)
	o.Attempts = 0
	o.Sent = append(o.Sent, time.Now())
	// No SMS provider yet: the code is logged (and DEV_OTP_CODE also works).
	log.Printf("OTP for %s: %s (dev code %q also accepted)", b.Phone, o.Code, s.cfg.DevOTPCode)
	ok(w, map[string]int{"expires_in_seconds": 300, "resend_after_seconds": 60})
	return nil
}

func (s *Server) otpVerify(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
		App   string `json:"app"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if !phoneRe.MatchString(b.Phone) {
		return fieldErr("phone", "invalid", "Invalid phone")
	}
	if !appRe.MatchString(b.App) {
		return fieldErr("app", "invalid", "Invalid app")
	}
	s.lock()
	defer s.unlock()
	o := s.st.OTPs[b.Phone]
	devOK := s.cfg.DevOTPCode != "" && b.Code == s.cfg.DevOTPCode
	if !devOK {
		if o == nil || o.Code == "" {
			return apiErr(400, "otp_expired", "Request a new code")
		}
		if time.Now().After(o.Expires) {
			return apiErr(400, "otp_expired", "Code expired")
		}
		o.Attempts++
		if o.Attempts > 5 {
			return apiErr(429, "rate_limited", "Too many attempts")
		}
		if b.Code != o.Code {
			return apiErr(400, "otp_invalid", "Wrong code")
		}
	}
	delete(s.st.OTPs, b.Phone)

	isNew := false
	uid, exists := s.st.UserByPhone[b.Phone]
	if !exists {
		uid = newID()
		s.st.Users[uid] = &User{ID: uid, Phone: b.Phone, Language: "en", Roles: []string{"customer"}, CreatedAt: Now()}
		s.st.UserByPhone[b.Phone] = uid
		isNew = true
	}
	u := s.st.Users[uid]
	addRole := func(role string) {
		for _, r := range u.Roles {
			if r == role {
				return
			}
		}
		u.Roles = append(u.Roles, role)
	}
	if b.App == "rider" {
		addRole("rider")
		if s.st.Riders[uid] == nil {
			s.st.Riders[uid] = &Rider{Profile: RiderProfile{
				ID: newID(), UserID: uid, Status: "incomplete", BalanceCentavos: s.cfg.RiderStartBalance, MinBalanceCentavos: 10000,
			}}
			if s.cfg.RiderStartBalance > 0 {
				s.addTx(uid, "adjustment", s.cfg.RiderStartBalance, "", "Welcome credit (dev)")
			}
		}
	}
	if _, staff := s.st.Staff[b.Phone]; staff && b.App == "merchant" {
		addRole("merchant")
	}
	access, refresh := s.issueTokens(uid, b.App)
	s.touch()
	ok(w, map[string]any{"access_token": access, "refresh_token": refresh, "user": u, "is_new_user": isNew || strings.TrimSpace(u.Name) == ""})
	return nil
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	rt, found := s.st.Refresh[b.RefreshToken]
	if !found || time.Now().After(rt.Expires) || s.st.Users[rt.UserID] == nil {
		return errUnauthorized
	}
	delete(s.st.Refresh, b.RefreshToken) // rotation
	access, refresh := s.issueTokens(rt.UserID, rt.App)
	ok(w, map[string]string{"access_token": access, "refresh_token": refresh})
	return nil
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		RefreshToken string `json:"refresh_token"`
	}
	_ = decode(r, &b)
	s.lock()
	defer s.unlock()
	delete(s.st.Refresh, b.RefreshToken)
	s.touch()
	okEmpty(w)
	return nil
}

func (s *Server) getMe(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	ok(w, s.st.Users[claimsOf(r).Sub])
	return nil
}

func (s *Server) patchMe(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Name     *string `json:"name"`
		Email    *string `json:"email"`
		Language *string `json:"language"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.Name != nil && len(strings.TrimSpace(*b.Name)) < 2 {
		return fieldErr("name", "too_short", "Name is too short")
	}
	if b.Language != nil && *b.Language != "en" && *b.Language != "fil" {
		return fieldErr("language", "invalid", "Language must be en or fil")
	}
	s.lock()
	defer s.unlock()
	u := s.st.Users[claimsOf(r).Sub]
	if b.Name != nil {
		u.Name = strings.TrimSpace(*b.Name)
	}
	if b.Email != nil {
		u.Email = b.Email
	}
	if b.Language != nil {
		u.Language = *b.Language
	}
	s.touch()
	ok(w, u)
	return nil
}

func (s *Server) deleteMe(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	uid := claimsOf(r).Sub
	u := s.st.Users[uid]
	for _, js := range s.st.Jobs {
		if (js.CustomerID == uid || js.RiderUserID == uid) && isLive(js.Job.Status) {
			return apiErr(409, "validation_failed", "Finish or cancel your active booking first")
		}
	}
	delete(s.st.UserByPhone, u.Phone)
	delete(s.st.Users, uid)
	delete(s.st.Riders, uid)
	for k, p := range s.st.Places {
		if p.UserID == uid {
			delete(s.st.Places, k)
		}
	}
	for k, t := range s.st.Refresh {
		if t.UserID == uid {
			delete(s.st.Refresh, k)
		}
	}
	s.touch()
	okEmpty(w)
	return nil
}

func (s *Server) registerDevice(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		FCMToken string `json:"fcm_token"`
		Platform string `json:"platform"`
		App      string `json:"app"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if b.FCMToken == "" {
		return fieldErr("fcm_token", "required", "Token required")
	}
	s.lock()
	defer s.unlock()
	s.st.Devices[b.FCMToken] = Device{UserID: claimsOf(r).Sub, Token: b.FCMToken, Platform: b.Platform, App: b.App}
	s.touch()
	okEmpty(w)
	return nil
}

// ---------- places & geo ----------

func (s *Server) listPlaces(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	uid := claimsOf(r).Sub
	out := []*SavedPlace{}
	for _, p := range s.st.Places {
		if p.UserID == uid {
			out = append(out, p)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Label < out[j].Label })
	ok(w, out)
	return nil
}

func (s *Server) addPlace(w http.ResponseWriter, r *http.Request) error {
	var b SavedPlace
	if err := decode(r, &b); err != nil {
		return err
	}
	if strings.TrimSpace(b.Label) == "" {
		return fieldErr("label", "required", "Label required")
	}
	s.lock()
	defer s.unlock()
	p := &SavedPlace{ID: newID(), UserID: claimsOf(r).Sub, Label: strings.TrimSpace(b.Label), Address: b.Address, Location: b.Location}
	s.st.Places[p.ID] = p
	s.touch()
	ok(w, p)
	return nil
}

func (s *Server) deletePlace(w http.ResponseWriter, r *http.Request) error {
	s.lock()
	defer s.unlock()
	p := s.st.Places[r.PathValue("id")]
	if p == nil || p.UserID != claimsOf(r).Sub {
		return errNotFound
	}
	delete(s.st.Places, p.ID)
	s.touch()
	okEmpty(w)
	return nil
}

func parseLatLng(r *http.Request) (LatLng, error) {
	lat, e1 := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lng, e2 := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	if e1 != nil || e2 != nil {
		return LatLng{}, fieldErr("lat", "invalid", "lat/lng required")
	}
	return LatLng{lat, lng}, nil
}

// gazetteer = landmarks + merchants (no external geocoder configured yet).
func (s *Server) gazetteer() []GeoPlace {
	out := append([]GeoPlace{}, s.st.GeoPlaces...)
	for _, id := range s.st.MerchantIDs {
		m := s.st.Merchants[id].Merchant
		out = append(out, GeoPlace{Name: m.Name, Address: m.Address, Location: m.Location})
	}
	return out
}

func (s *Server) geoReverse(w http.ResponseWriter, r *http.Request) error {
	p, err := parseLatLng(r)
	if err != nil {
		return err
	}
	s.lock()
	defer s.unlock()
	best, bestD := GeoPlace{}, 1<<30
	for _, g := range s.gazetteer() {
		if d := distanceM(p, g.Location); d < bestD {
			best, bestD = g, d
		}
	}
	addr := "Bongao, Tawi-Tawi"
	switch {
	case best.Name == "":
	case bestD < 80:
		addr = best.Name + ", Bongao"
	case bestD < 3000:
		addr = "Near " + best.Name + ", Bongao"
	}
	ok(w, map[string]string{"address": addr})
	return nil
}

func (s *Server) geoSearch(w http.ResponseWriter, r *http.Request) error {
	near, err := parseLatLng(r)
	if err != nil {
		return err
	}
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	s.lock()
	defer s.unlock()
	out := []GeoPlace{}
	for _, g := range s.gazetteer() {
		if q == "" || strings.Contains(strings.ToLower(g.Name+" "+g.Address), q) {
			out = append(out, g)
		}
	}
	sort.Slice(out, func(i, j int) bool { return distanceM(near, out[i].Location) < distanceM(near, out[j].Location) })
	if len(out) > 10 {
		out = out[:10]
	}
	ok(w, out)
	return nil
}

func (s *Server) serviceArea(w http.ResponseWriter, _ *http.Request) error {
	ok(w, s.st.ServiceArea)
	return nil
}
