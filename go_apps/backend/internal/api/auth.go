package api

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"goapp/backend/internal/domain"
	"goapp/backend/internal/integrations"
	"goapp/backend/internal/service"
)

var phoneRe = regexp.MustCompile(`^\+639\d{9}$`)
var appRe = regexp.MustCompile(`^(customer|rider|merchant)$`)

func randomOTP() string {
	n, _ := rand.Int(rand.Reader, big.NewInt(1000000))
	return fmt.Sprintf("%06d", n.Int64())
}

func (a *API) otpRequest(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Phone string `json:"phone"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	if !phoneRe.MatchString(b.Phone) {
		return fieldErr("phone", "invalid", "Invalid PH mobile number")
	}
	a.svc.Lock()
	defer a.svc.Unlock()

	checkedRedis := false
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		allowed, err := a.svc.Redis.CheckAndRecordOTPRequest(ctx, b.Phone, 10*time.Minute, 5)
		cancel()
		if err == nil {
			checkedRedis = true
			if !allowed {
				return apiErr(429, "rate_limited", "Too many codes requested")
			}
		}
	}

	o := a.svc.St.OTPs[b.Phone]
	if o == nil {
		o = &domain.OTP{}
		a.svc.St.OTPs[b.Phone] = o
	}
	recent := o.Sent[:0]
	for _, t := range o.Sent {
		if time.Since(t) < 10*time.Minute {
			recent = append(recent, t)
		}
	}
	o.Sent = recent
	if !checkedRedis && len(o.Sent) >= 5 {
		return apiErr(429, "rate_limited", "Too many codes requested")
	}

	rawCode := randomOTP()
	codeHash := a.svc.HashOTP(b.Phone, rawCode)
	o.Code = codeHash
	o.Expires = time.Now().Add(5 * time.Minute)
	o.Attempts = 0
	o.Sent = append(o.Sent, time.Now())

	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.SaveOTP(ctx, b.Phone, codeHash, 5*time.Minute)
		cancel()
	}

	if a.svc.Cfg.DevOTPCode != "" {
		log.Printf("OTP for %s: %s (dev code %q also accepted)", b.Phone, rawCode, a.svc.Cfg.DevOTPCode)
	} else {
		log.Printf("OTP issued for %s", domain.MaskPhone(b.Phone))
	}
	ok(w, map[string]int{"expires_in_seconds": 300, "resend_after_seconds": 60})
	return nil
}

func (a *API) otpVerify(w http.ResponseWriter, r *http.Request) error {
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
	a.svc.Lock()
	defer a.svc.Unlock()

	o := a.svc.St.OTPs[b.Phone]
	if o != nil && o.Attempts >= 5 && time.Now().Before(o.Expires) {
		return apiErr(429, "rate_limited", "Too many attempts")
	}

	devOK := a.svc.Cfg.DevOTPCode != "" && subtle.ConstantTimeCompare([]byte(b.Code), []byte(a.svc.Cfg.DevOTPCode)) == 1
	verifiedViaRedis := false
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		codeHash, curAttempts, exists, err := a.svc.Redis.GetOTP(ctx, b.Phone)
		if err == nil {
			verifiedViaRedis = true
			if exists && curAttempts >= 5 {
				cancel()
				return apiErr(429, "rate_limited", "Too many attempts")
			}
			if !devOK {
				if !exists || codeHash == "" {
					cancel()
					return apiErr(400, "otp_expired", "Request a new code")
				}
				attempts, _ := a.svc.Redis.IncrementOTPAttempts(ctx, b.Phone, 5*time.Minute)
				cancel()
				if o != nil {
					o.Attempts = attempts
				}
				if attempts > 5 {
					return apiErr(429, "rate_limited", "Too many attempts")
				}
				if !a.svc.VerifyOTPCode(b.Phone, b.Code, codeHash) {
					return apiErr(400, "otp_invalid", "Wrong code")
				}
			} else {
				cancel()
			}
		} else {
			cancel()
		}
	}

	if !devOK && !verifiedViaRedis {
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
		if !a.svc.VerifyOTPCode(b.Phone, b.Code, o.Code) {
			return apiErr(400, "otp_invalid", "Wrong code")
		}
	}
	delete(a.svc.St.OTPs, b.Phone)
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.DeleteOTP(ctx, b.Phone)
		cancel()
	}

	isNew := false
	uid, exists := a.svc.St.UserByPhone[b.Phone]
	if !exists {
		uid = domain.NewID()
		a.svc.St.Users[uid] = &domain.User{ID: uid, Phone: b.Phone, Language: "en", Roles: []string{"customer"}, CreatedAt: domain.Now()}
		a.svc.St.UserByPhone[b.Phone] = uid
		isNew = true
	}
	u := a.svc.St.Users[uid]
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
		if a.svc.St.Riders[uid] == nil {
			a.svc.St.Riders[uid] = &domain.Rider{Profile: domain.RiderProfile{
				ID: domain.NewID(), UserID: uid, Status: "incomplete", BalanceCentavos: a.svc.Cfg.RiderStartBalance, MinBalanceCentavos: 10000,
			}}
			if a.svc.Cfg.RiderStartBalance > 0 {
				a.svc.AddTx(uid, "adjustment", a.svc.Cfg.RiderStartBalance, "", "Welcome credit (dev)")
			}
		}
	}
	if _, staff := a.svc.St.Staff[b.Phone]; staff && b.App == "merchant" {
		addRole("merchant")
	}
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.SaveUser(ctx, u)
		cancel()
	}
	access, refresh := a.svc.IssueTokens(uid, b.App)
	a.svc.Touch()
	ok(w, map[string]any{"access_token": access, "refresh_token": refresh, "user": u, "is_new_user": isNew || strings.TrimSpace(u.Name) == ""})
	return nil
}

func (a *API) refresh(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	access, refresh, valid := a.svc.RotateRefreshToken(b.RefreshToken)
	if !valid {
		return errUnauthorized
	}
	ok(w, map[string]string{"access_token": access, "refresh_token": refresh})
	return nil
}

func (a *API) logout(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		RefreshToken string `json:"refresh_token"`
	}
	_ = decode(r, &b)
	a.svc.Lock()
	defer a.svc.Unlock()
	a.svc.RevokeRefreshToken(b.RefreshToken)
	a.svc.RevokeAccessToken(r.Header.Get("Authorization"))
	a.svc.Touch()
	okEmpty(w)
	return nil
}

func (a *API) getMe(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	u := a.svc.St.Users[claimsOf(r).Sub]
	if u == nil {
		return errUnauthorized
	}
	ok(w, u)
	return nil
}

func (a *API) patchMe(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		Name     *string `json:"name"`
		Email    *string `json:"email"`
		Language *string `json:"language"`
		Phone    *string `json:"phone"`
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
	a.svc.Lock()
	defer a.svc.Unlock()
	u := a.svc.St.Users[claimsOf(r).Sub]
	if u == nil {
		return errUnauthorized
	}
	if b.Phone != nil {
		cleanPhone := strings.TrimSpace(*b.Phone)
		if !phoneRe.MatchString(cleanPhone) {
			return fieldErr("phone", "invalid", "Invalid phone format")
		}
		if otherUID, taken := a.svc.St.UserByPhone[cleanPhone]; taken && otherUID != u.ID {
			return fieldErr("phone", "taken", "Phone number already in use by another account")
		}
		if u.Phone != "" {
			delete(a.svc.St.UserByPhone, u.Phone)
		}
		u.Phone = cleanPhone
		a.svc.St.UserByPhone[cleanPhone] = u.ID
	}
	if b.Name != nil {
		u.Name = strings.TrimSpace(*b.Name)
	}
	if b.Email != nil {
		u.Email = b.Email
		if *b.Email != "" {
			a.svc.St.UserByEmail[strings.ToLower(*b.Email)] = u.ID
		}
	}
	if b.Language != nil {
		u.Language = *b.Language
	}
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.SaveUser(ctx, u)
		cancel()
	}
	a.svc.Touch()
	ok(w, u)
	return nil
}

func (a *API) deleteMe(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	uid := claimsOf(r).Sub
	u := a.svc.St.Users[uid]
	if u == nil {
		return errUnauthorized
	}
	for _, js := range a.svc.St.Jobs {
		if (js.CustomerID == uid || js.RiderUserID == uid) && service.IsLive(js.Job.Status) {
			return apiErr(409, "validation_failed", "Finish or cancel your active booking first")
		}
	}
	phone := u.Phone
	delete(a.svc.St.UserByPhone, phone)
	delete(a.svc.St.Users, uid)
	delete(a.svc.St.Riders, uid)
	for k, p := range a.svc.St.Places {
		if p.UserID == uid {
			delete(a.svc.St.Places, k)
		}
	}
	a.svc.RevokeUserSessions(uid)
	a.svc.RevokeAccessToken(r.Header.Get("Authorization"))
	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		_ = a.svc.Redis.DeleteUser(ctx, uid, phone)
		_ = a.svc.Redis.RemoveRiderLocation(ctx, uid)
		cancel()
	}
	a.svc.Touch()
	okEmpty(w)
	return nil
}

func (a *API) registerDevice(w http.ResponseWriter, r *http.Request) error {
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
	a.svc.Lock()
	defer a.svc.Unlock()
	a.svc.St.Devices[b.FCMToken] = domain.Device{UserID: claimsOf(r).Sub, Token: b.FCMToken, Platform: b.Platform, App: b.App}
	a.svc.Touch()
	okEmpty(w)
	return nil
}

// ---------- places & geo ----------

func (a *API) listPlaces(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	uid := claimsOf(r).Sub
	out := []*domain.SavedPlace{}
	for _, p := range a.svc.St.Places {
		if p.UserID == uid {
			out = append(out, p)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Label < out[j].Label })
	ok(w, out)
	return nil
}

func (a *API) addPlace(w http.ResponseWriter, r *http.Request) error {
	var b domain.SavedPlace
	if err := decode(r, &b); err != nil {
		return err
	}
	if strings.TrimSpace(b.Label) == "" {
		return fieldErr("label", "required", "Label required")
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	p := &domain.SavedPlace{ID: domain.NewID(), UserID: claimsOf(r).Sub, Label: strings.TrimSpace(b.Label), Address: b.Address, Location: b.Location}
	a.svc.St.Places[p.ID] = p
	a.svc.Touch()
	ok(w, p)
	return nil
}

func (a *API) deletePlace(w http.ResponseWriter, r *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	p := a.svc.St.Places[r.PathValue("id")]
	if p == nil || p.UserID != claimsOf(r).Sub {
		return errNotFound
	}
	delete(a.svc.St.Places, p.ID)
	a.svc.Touch()
	okEmpty(w)
	return nil
}

func parseLatLng(r *http.Request) (domain.LatLng, error) {
	lat, e1 := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lng, e2 := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	if e1 != nil || e2 != nil || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return domain.LatLng{}, fieldErr("lat", "invalid", "lat/lng required")
	}
	return domain.LatLng{Lat: lat, Lng: lng}, nil
}

// gazetteer = landmarks + merchants (no external geocoder configured yet).
func (a *API) gazetteer() []domain.GeoPlace {
	out := append([]domain.GeoPlace{}, a.svc.St.GeoPlaces...)
	for _, id := range a.svc.St.MerchantIDs {
		m := a.svc.St.Merchants[id].Merchant
		out = append(out, domain.GeoPlace{Name: m.Name, Address: m.Address, Location: m.Location})
	}
	return out
}

func (a *API) geoReverse(w http.ResponseWriter, r *http.Request) error {
	p, err := parseLatLng(r)
	if err != nil {
		return err
	}
	if a.svc.Maps != nil && a.svc.Maps.Enabled() {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		addr, err := a.svc.Maps.Reverse(ctx, p)
		cancel()
		if err == nil && addr != "" {
			ok(w, map[string]string{"address": addr})
			return nil
		}
		integrations.LogIntegration("google reverse geocode", err)
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	best, bestD := domain.GeoPlace{}, 1<<30
	for _, g := range a.gazetteer() {
		if d := domain.DistanceM(p, g.Location); d < bestD {
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

func (a *API) geoSearch(w http.ResponseWriter, r *http.Request) error {
	near, err := parseLatLng(r)
	if err != nil {
		return err
	}
	q := strings.ToLower(strings.TrimSpace(r.URL.Query().Get("q")))
	var google []domain.GeoPlace
	if a.svc.Maps != nil && a.svc.Maps.Enabled() && len([]rune(q)) >= 2 {
		ctx, cancel := context.WithTimeout(r.Context(), 12*time.Second)
		var err error
		google, err = a.svc.Maps.Search(ctx, q, near)
		cancel()
		if err != nil {
			integrations.LogIntegration("google places search", err)
		}
	}
	a.svc.Lock()
	defer a.svc.Unlock()
	out := append([]domain.GeoPlace{}, google...)
	for _, g := range a.gazetteer() {
		if q == "" || strings.Contains(strings.ToLower(g.Name+" "+g.Address), q) {
			out = append(out, g)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		return domain.DistanceM(near, out[i].Location) < domain.DistanceM(near, out[j].Location)
	})
	if len(out) > 10 {
		out = out[:10]
	}
	ok(w, out)
	return nil
}

func (a *API) serviceArea(w http.ResponseWriter, _ *http.Request) error {
	a.svc.Lock()
	defer a.svc.Unlock()
	ok(w, a.svc.St.ServiceArea)
	return nil
}

// ---------- Social Authentication (Google & Facebook) ----------

func (a *API) googleAuth(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		IDToken string `json:"id_token"`
		Token   string `json:"token"`
		App     string `json:"app"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	tok := strings.TrimSpace(b.IDToken)
	if tok == "" {
		tok = strings.TrimSpace(b.Token)
	}
	if tok == "" {
		return fieldErr("id_token", "required", "Google ID token required")
	}
	if b.App == "" {
		b.App = "customer"
	}
	if !appRe.MatchString(b.App) {
		return fieldErr("app", "invalid", "Invalid app")
	}

	if a.svc.Social == nil {
		return apiErr(500, "social_auth_disabled", "Social auth not configured")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	prof, err := a.svc.Social.VerifyGoogle(ctx, tok)
	if err != nil {
		return apiErr(401, "invalid_google_token", err.Error())
	}

	a.svc.Lock()
	defer a.svc.Unlock()

	return a.loginOrCreateSocialUser(w, b.App, "google", prof.ID, prof.Email, prof.Name, prof.Picture)
}

func (a *API) facebookAuth(w http.ResponseWriter, r *http.Request) error {
	var b struct {
		AccessToken string `json:"access_token"`
		Token       string `json:"token"`
		App         string `json:"app"`
	}
	if err := decode(r, &b); err != nil {
		return err
	}
	tok := strings.TrimSpace(b.AccessToken)
	if tok == "" {
		tok = strings.TrimSpace(b.Token)
	}
	if tok == "" {
		return fieldErr("access_token", "required", "Facebook access token required")
	}
	if b.App == "" {
		b.App = "customer"
	}
	if !appRe.MatchString(b.App) {
		return fieldErr("app", "invalid", "Invalid app")
	}

	if a.svc.Social == nil {
		return apiErr(500, "social_auth_disabled", "Social auth not configured")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	prof, err := a.svc.Social.VerifyFacebook(ctx, tok)
	if err != nil {
		return apiErr(401, "invalid_facebook_token", err.Error())
	}

	a.svc.Lock()
	defer a.svc.Unlock()

	return a.loginOrCreateSocialUser(w, b.App, "facebook", prof.ID, prof.Email, prof.Name, prof.Picture.Data.URL)
}

func (a *API) loginOrCreateSocialUser(w http.ResponseWriter, app, provider, socialID, email, name, avatar string) error {
	var uid string
	var exists bool

	if provider == "google" {
		uid, exists = a.svc.St.UserByGoogleID[socialID]
	} else if provider == "facebook" {
		uid, exists = a.svc.St.UserByFacebookID[socialID]
	}

	if !exists && email != "" {
		if emailUID, emailFound := a.svc.St.UserByEmail[strings.ToLower(email)]; emailFound {
			uid = emailUID
			exists = true
		}
	}

	isNew := false
	if !exists {
		uid = domain.NewID()
		u := &domain.User{
			ID:        uid,
			Name:      strings.TrimSpace(name),
			Language:  "en",
			Roles:     []string{"customer"},
			CreatedAt: domain.Now(),
		}
		if email != "" {
			em := strings.ToLower(email)
			u.Email = &em
		}
		if avatar != "" {
			u.AvatarURL = &avatar
		}
		if provider == "google" {
			u.GoogleID = &socialID
		} else if provider == "facebook" {
			u.FacebookID = &socialID
		}
		a.svc.St.Users[uid] = u
		isNew = true
	}

	u := a.svc.St.Users[uid]
	if provider == "google" {
		u.GoogleID = &socialID
		a.svc.St.UserByGoogleID[socialID] = uid
	} else if provider == "facebook" {
		u.FacebookID = &socialID
		a.svc.St.UserByFacebookID[socialID] = uid
	}
	if email != "" {
		em := strings.ToLower(email)
		if u.Email == nil || *u.Email == "" {
			u.Email = &em
		}
		a.svc.St.UserByEmail[em] = uid
	}
	if name != "" && u.Name == "" {
		u.Name = strings.TrimSpace(name)
	}
	if avatar != "" && (u.AvatarURL == nil || *u.AvatarURL == "") {
		u.AvatarURL = &avatar
	}

	addRole := func(role string) {
		for _, r := range u.Roles {
			if r == role {
				return
			}
		}
		u.Roles = append(u.Roles, role)
	}
	if app == "rider" {
		addRole("rider")
		if a.svc.St.Riders[uid] == nil {
			a.svc.St.Riders[uid] = &domain.Rider{Profile: domain.RiderProfile{
				ID: domain.NewID(), UserID: uid, Status: "incomplete", BalanceCentavos: a.svc.Cfg.RiderStartBalance, MinBalanceCentavos: 10000,
			}}
			if a.svc.Cfg.RiderStartBalance > 0 {
				a.svc.AddTx(uid, "adjustment", a.svc.Cfg.RiderStartBalance, "", "Welcome credit (dev)")
			}
		}
	}
	if u.Phone != "" {
		if _, staff := a.svc.St.Staff[u.Phone]; staff && app == "merchant" {
			addRole("merchant")
		}
	}

	if a.svc.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_ = a.svc.Redis.SaveUser(ctx, u)
		cancel()
	}

	access, refresh := a.svc.IssueTokens(uid, app)
	a.svc.Touch()

	ok(w, map[string]any{
		"access_token":  access,
		"refresh_token": refresh,
		"user":          u,
		"is_new_user":   isNew || strings.TrimSpace(u.Name) == "",
		"needs_phone":   u.Phone == "",
	})
	return nil
}
