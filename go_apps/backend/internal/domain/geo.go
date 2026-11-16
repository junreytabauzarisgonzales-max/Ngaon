package domain

import "math"

type LatLng struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

type Stop struct {
	Address      string  `json:"address"`
	Location     LatLng  `json:"location"`
	ContactName  *string `json:"contact_name,omitempty"`
	ContactPhone *string `json:"contact_phone,omitempty"`
	Notes        *string `json:"notes,omitempty"`
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

// DistanceM calculates great-circle distance between two coordinates in meters.
func DistanceM(a, b LatLng) int {
	const r = 6371000.0
	rad := func(d float64) float64 { return d * math.Pi / 180 }
	dLat, dLng := rad(b.Lat-a.Lat), rad(b.Lng-a.Lng)
	h := math.Pow(math.Sin(dLat/2), 2) + math.Cos(rad(a.Lat))*math.Cos(rad(b.Lat))*math.Pow(math.Sin(dLng/2), 2)
	return int(math.Round(2 * r * math.Asin(math.Sqrt(h))))
}

// Contains checks if a point is inside the polygonal zone using ray-casting.
func (z ServiceZone) Contains(p LatLng) bool {
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

// InServiceArea checks if a point is contained within any active service zone.
func (sa ServiceArea) InServiceArea(p LatLng, anyLocation bool) bool {
	if anyLocation {
		return true
	}
	for _, z := range sa.Zones {
		if z.Contains(p) {
			return true
		}
	}
	return false
}
