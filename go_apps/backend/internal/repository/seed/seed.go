package seed

import (
	"embed"
	"encoding/json"

	"goapp/backend/internal/domain"
	"goapp/backend/internal/repository"
)

//go:embed *.json
var SeedFS embed.FS

// ReadSeed reads and unmarshals an embedded fixture.
func ReadSeed(name string, v any) error {
	b, err := SeedFS.ReadFile(name)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, v)
}

// Owner phones for the seeded merchants (log into Go Merchant with these).
var MerchantPhones = []string{
	"+639193334444",
	"+639193334445",
	"+639193334446",
	"+639193334447",
	"+639193334448",
}

var StaffNames = []string{"Mering", "Pantay staff", "Sitti", "Tiula staff", "Bud staff"}

// PopulateInitial seeds default places, zones, merchants, and staff into the State.
func PopulateInitial(st *repository.State, anyLocation bool) error {
	if err := ReadSeed("geo_places.json", &st.GeoPlaces); err != nil {
		return err
	}
	if err := ReadSeed("service_area.json", &st.ServiceArea); err != nil {
		return err
	}
	if anyLocation {
		st.ServiceArea = domain.ServiceArea{
			Zones: []domain.ServiceZone{
				{
					ID:      "dev-anywhere",
					Name:    "Anywhere (dev)",
					Polygon: []domain.LatLng{{Lat: 85, Lng: -179.9}, {Lat: 85, Lng: 179.9}, {Lat: -85, Lng: 179.9}, {Lat: -85, Lng: -179.9}},
				},
			},
		}
	}
	if len(st.Merchants) == 0 {
		var ms []domain.Merchant
		if err := ReadSeed("merchants.json", &ms); err != nil {
			return err
		}
		for i, m := range ms {
			m := m
			m.DistanceM = nil
			phone := MerchantPhones[i%len(MerchantPhones)]
			st.Merchants[m.ID] = &domain.MerchantRow{Merchant: m, Phone: phone}
			st.MerchantIDs = append(st.MerchantIDs, m.ID)
			st.Staff[phone] = domain.MerchantStaff{
				UserPhone:  phone,
				MerchantID: m.ID,
				Role:       "owner",
				StaffName:  StaffNames[i%len(StaffNames)],
			}
		}
		var ps []*domain.Payout
		if err := ReadSeed("payouts.json", &ps); err == nil && len(st.MerchantIDs) > 0 {
			for _, p := range ps {
				p.MerchantID = st.MerchantIDs[0]
			}
			st.Payouts = ps
		}
	}
	return nil
}
