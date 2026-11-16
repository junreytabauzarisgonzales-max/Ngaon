package service

import (
	"context"
	"log"
	"math"
	"sort"
	"time"

	"goapp/backend/internal/domain"
)

const offerTTL = 15 * time.Second
const searchTimeout = 5 * time.Minute

func contains(arr []string, s string) bool {
	for _, v := range arr {
		if v == s {
			return true
		}
	}
	return false
}

func (s *Service) OfferJSON(o *domain.JobOffer) map[string]any {
	js := s.St.Jobs[o.JobID]
	if js == nil {
		return map[string]any{}
	}
	return map[string]any{
		"id":                o.ID,
		"job":               s.JobView(js, "rider"),
		"earnings_centavos": o.EarningsCentavos,
		"pickup_distance_m": o.PickupDistanceM,
		"expires_at":        o.ExpiresAt,
	}
}

func (s *Service) Dispatch(js *domain.JobState) {
	if js.Job.Status != "searching" {
		return
	}
	for _, o := range s.St.Offers {
		if o.JobID == js.Job.ID {
			return // already offered to a rider, waiting for response
		}
	}
	type cand struct {
		r *domain.Rider
		d int
	}
	busy := map[string]bool{}
	for _, o := range s.St.Offers {
		busy[o.RiderUserID] = true
	}

	// Synchronize nearby rider positions from Redis geospatial index when available.
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
		if nearby, err := s.Redis.NearbyRiders(ctx, js.Job.Pickup.Location, float64(s.Cfg.MaxDispatchM)); err == nil {
			for _, nr := range nearby {
				if rd := s.St.Riders[nr.UserID]; rd != nil {
					if rec, ok, lErr := s.Redis.GetRiderLocation(ctx, nr.UserID); lErr == nil && ok && rec != nil {
						loc := rec.Location
						rd.Location = &loc
						rd.LocationAt = rec.UpdatedAt
					} else if rd.Location == nil {
						loc := nr.Location
						rd.Location = &loc
						rd.LocationAt = time.Now()
					}
				}
			}
		}
		cancel()
	}

	var cs []cand
	for _, rd := range s.St.Riders {
		p := rd.Profile
		if p.Status != "approved" || !p.IsOnline || rd.ActiveJobID != "" || busy[p.UserID] || rd.Location == nil ||
			p.BalanceCentavos < p.MinBalanceCentavos || time.Since(rd.LocationAt) > 15*time.Minute ||
			contains(js.DeclinedBy, p.UserID) || p.UserID == js.CustomerID {
			continue
		}
		d := domain.DistanceM(*rd.Location, js.Job.Pickup.Location)
		if s.Cfg.MaxDispatchM == 0 || d <= s.Cfg.MaxDispatchM {
			cs = append(cs, cand{rd, d})
		}
	}
	if len(cs) == 0 {
		return
	}
	sort.Slice(cs, func(i, j int) bool { return cs[i].d < cs[j].d })
	c := cs[0]
	earn := js.FeesCentavos * 80 / 100
	if js.Job.Pabili != nil {
		earn = int(math.Max(float64(earn), 4000))
	}
	o := &domain.JobOffer{
		ID:               domain.NewID(),
		JobID:            js.Job.ID,
		RiderUserID:      c.r.Profile.UserID,
		EarningsCentavos: earn,
		PickupDistanceM:  c.d,
		ExpiresAt:        *domain.At(time.Now().Add(offerTTL)),
	}
	s.St.Offers[o.ID] = o
	if s.Redis != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		_ = s.Redis.SaveOffer(ctx, o)
		cancel()
	}
	log.Printf("offer %s for %s -> rider %s (%dm)", o.ID[:8], js.Job.Code, s.UserName(c.r.Profile.UserID), c.d)
	s.Emit(o.RiderUserID, "rider", "offer.new", map[string]any{"offer": s.OfferJSON(o)})
}

// Tick runs periodic state updates: expiring offers, searching timeouts, deadline timeouts, auto-approvals.
func (s *Service) Tick() {
	s.Lock()
	defer s.Unlock()
	now := time.Now()

	for id, o := range s.St.Offers {
		if now.After(o.ExpiresAt.Time) {
			delete(s.St.Offers, id)
			if s.Redis != nil {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				_ = s.Redis.DeleteOffer(ctx, id, o.RiderUserID)
				cancel()
			}
			s.Emit(o.RiderUserID, "rider", "offer.expired", map[string]any{"offer_id": id})
			if js := s.St.Jobs[o.JobID]; js != nil {
				js.DeclinedBy = append(js.DeclinedBy, o.RiderUserID)
			}
		}
	}

	for _, js := range s.St.Jobs {
		switch js.Job.Status {
		case "searching":
			if now.Sub(js.SearchingSince) > searchTimeout {
				s.Cancel(js, "system", "No rider was available nearby. Please try again.")
				continue
			}
			// Give riders who declined or timed out another chance every 45s
			if len(js.DeclinedBy) > 0 && int(now.Sub(js.SearchingSince).Seconds())%45 == 0 {
				js.DeclinedBy = nil
			}
			s.Dispatch(js)
		case "merchant_pending":
			if !js.MerchantDeadline.IsZero() && now.After(js.MerchantDeadline) {
				s.Cancel(js, "system", "The store did not accept the order in time.")
			}
		case "pending_payment":
			if now.Sub(js.Job.CreatedAt.Time) > 30*time.Minute {
				s.Cancel(js, "system", "Payment was not completed.")
			}
		}
	}

	if s.Cfg.AutoApproveSeconds > 0 {
		for _, rd := range s.St.Riders {
			if rd.Profile.Status == "pending_review" && now.Sub(rd.SubmittedAt) > time.Duration(s.Cfg.AutoApproveSeconds)*time.Second {
				s.SetRiderReview(rd, true, "")
			}
		}
	}

	// Prune expired in-memory revoked tokens and rate buckets
	s.revokedMu.Lock()
	for k, exp := range s.revokedTokens {
		if now.After(exp) {
			delete(s.revokedTokens, k)
		}
	}
	s.revokedMu.Unlock()

	s.rateMu.Lock()
	for k, b := range s.rateBuckets {
		if now.After(b.resetAt) {
			delete(s.rateBuckets, k)
		}
	}
	s.rateMu.Unlock()
}
