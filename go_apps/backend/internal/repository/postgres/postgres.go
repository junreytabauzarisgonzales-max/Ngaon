package postgres

import (
	"database/sql"
	"embed"
	"encoding/json"
	"fmt"
	"log"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/lib/pq"
	"goapp/backend/internal/domain"
	"goapp/backend/internal/repository"
	"goapp/backend/internal/repository/seed"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// Connect opens a connection pool to PostgreSQL and runs pending migrations.
func Connect(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("open postgres: %w", err)
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping postgres: %w", err)
	}

	entries, err := migrationsFS.ReadDir("migrations")
	if err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("read migrations dir: %w", err)
	}
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Name() < entries[j].Name()
	})
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".up.sql") {
			sqlBytes, err := migrationsFS.ReadFile("migrations/" + entry.Name())
			if err != nil {
				_ = db.Close()
				return nil, fmt.Errorf("read migration %s: %w", entry.Name(), err)
			}
			if _, err := db.Exec(string(sqlBytes)); err != nil {
				_ = db.Close()
				return nil, fmt.Errorf("exec migration %s: %w", entry.Name(), err)
			}
		}
	}

	log.Printf("connected to PostgreSQL and verified schema")
	return db, nil
}

// ---------- Null Helpers ----------

func nullStr(s *string) sql.NullString {
	if s == nil {
		return sql.NullString{}
	}
	return sql.NullString{String: *s, Valid: true}
}

func strPtr(ns sql.NullString) *string {
	if !ns.Valid {
		return nil
	}
	return &ns.String
}

func nullInt(i *int) sql.NullInt64 {
	if i == nil {
		return sql.NullInt64{}
	}
	return sql.NullInt64{Int64: int64(*i), Valid: true}
}

func intPtr(ni sql.NullInt64) *int {
	if !ni.Valid {
		return nil
	}
	v := int(ni.Int64)
	return &v
}

func nullFloat(f *float64) sql.NullFloat64 {
	if f == nil {
		return sql.NullFloat64{}
	}
	return sql.NullFloat64{Float64: *f, Valid: true}
}

func floatPtr(nf sql.NullFloat64) *float64 {
	if !nf.Valid {
		return nil
	}
	return &nf.Float64
}

func nullUTC(u *domain.UTC) sql.NullTime {
	if u == nil || u.IsZero() {
		return sql.NullTime{}
	}
	return sql.NullTime{Time: u.Time.UTC(), Valid: true}
}

func utcPtr(nt sql.NullTime) *domain.UTC {
	if !nt.Valid {
		return nil
	}
	u := domain.UTC{Time: nt.Time.UTC()}
	return &u
}

// ---------- Load ----------

// Load reads all tables from PostgreSQL into the state cache.
func Load(db *sql.DB, st *repository.State, anyLocation bool) error {
	var merchantCount int
	if err := db.QueryRow("SELECT COUNT(*) FROM merchants").Scan(&merchantCount); err != nil {
		return fmt.Errorf("count merchants: %w", err)
	}
	if merchantCount == 0 {
		log.Printf("empty postgres database, seeding initial catalog and places")
		if err := seed.PopulateInitial(st, anyLocation); err != nil {
			return fmt.Errorf("seed initial data: %w", err)
		}
		if err := Save(db, st); err != nil {
			return fmt.Errorf("save initial seed to postgres: %w", err)
		}
		return nil
	}

	// Read static geo places and service areas
	if err := seed.ReadSeed("geo_places.json", &st.GeoPlaces); err != nil {
		return err
	}
	if err := seed.ReadSeed("service_area.json", &st.ServiceArea); err != nil {
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

	// 1. Users
	userRows, err := db.Query("SELECT id, COALESCE(phone_number, ''), email, full_name, language, roles, created_at, google_id, facebook_id, avatar_url FROM users")
	if err != nil {
		return fmt.Errorf("query users: %w", err)
	}
	defer userRows.Close()

	for userRows.Next() {
		var u domain.User
		var email, googleID, facebookID, avatarURL sql.NullString
		var roles []string
		var createdAt time.Time
		if err := userRows.Scan(&u.ID, &u.Phone, &email, &u.Name, &u.Language, pq.Array(&roles), &createdAt, &googleID, &facebookID, &avatarURL); err != nil {
			return fmt.Errorf("scan user: %w", err)
		}
		u.Email = strPtr(email)
		u.GoogleID = strPtr(googleID)
		u.FacebookID = strPtr(facebookID)
		u.AvatarURL = strPtr(avatarURL)
		u.Roles = roles
		u.CreatedAt = domain.UTC{Time: createdAt.UTC()}
		st.Users[u.ID] = &u
		if u.Phone != "" {
			st.UserByPhone[u.Phone] = u.ID
		}
		if u.GoogleID != nil && *u.GoogleID != "" {
			st.UserByGoogleID[*u.GoogleID] = u.ID
		}
		if u.FacebookID != nil && *u.FacebookID != "" {
			st.UserByFacebookID[*u.FacebookID] = u.ID
		}
		if u.Email != nil && *u.Email != "" {
			st.UserByEmail[*u.Email] = u.ID
		}
	}

	// 2. Saved Places
	placeRows, err := db.Query("SELECT id, user_id, label, address_line1, latitude, longitude FROM user_addresses")
	if err != nil {
		return fmt.Errorf("query places: %w", err)
	}
	defer placeRows.Close()

	for placeRows.Next() {
		var p domain.SavedPlace
		if err := placeRows.Scan(&p.ID, &p.UserID, &p.Label, &p.Address, &p.Location.Lat, &p.Location.Lng); err != nil {
			return fmt.Errorf("scan place: %w", err)
		}
		st.Places[p.ID] = &p
	}

	// 3. Merchants & Catalog
	mRows, err := db.Query("SELECT id, name, logo_url, cover_url, address_line1, latitude, longitude, is_accepting_orders, paused_until, avg_preparation_time_minutes, rating, min_order_centavos, rating_sum, rating_count, phone_number FROM merchants")
	if err != nil {
		return fmt.Errorf("query merchants: %w", err)
	}
	defer mRows.Close()

	for mRows.Next() {
		var m domain.Merchant
		var logo, cover sql.NullString
		var paused sql.NullTime
		var rating sql.NullFloat64
		var rSum, rCount int
		var phone string

		if err := mRows.Scan(&m.ID, &m.Name, &logo, &cover, &m.Address, &m.Location.Lat, &m.Location.Lng, &m.IsOpen, &paused, &m.PrepTimeMinutes, &rating, &m.MinOrderCentavos, &rSum, &rCount, &phone); err != nil {
			return fmt.Errorf("scan merchant: %w", err)
		}
		m.LogoURL = strPtr(logo)
		m.CoverURL = strPtr(cover)
		m.PausedUntil = utcPtr(paused)
		m.Rating = floatPtr(rating)

		st.Merchants[m.ID] = &domain.MerchantRow{
			Merchant:    m,
			RatingSum:   rSum,
			RatingCount: rCount,
			Phone:       phone,
		}
		st.MerchantIDs = append(st.MerchantIDs, m.ID)
	}

	// Hours
	hRows, err := db.Query("SELECT merchant_id, day_of_week, open_time, close_time FROM merchant_operating_hours WHERE is_closed = false ORDER BY day_of_week ASC")
	if err != nil {
		return fmt.Errorf("query hours: %w", err)
	}
	defer hRows.Close()

	for hRows.Next() {
		var mID string
		var h domain.OpeningHours
		var opens, closes string
		if err := hRows.Scan(&mID, &h.Weekday, &opens, &closes); err != nil {
			return fmt.Errorf("scan hours: %w", err)
		}
		if len(opens) >= 5 {
			h.Opens = opens[:5]
		}
		if len(closes) >= 5 {
			h.Closes = closes[:5]
		}
		if row, ok := st.Merchants[mID]; ok {
			row.Merchant.Hours = append(row.Merchant.Hours, h)
		}
	}

	// Categories
	catMap := map[string]*domain.MenuCategory{}
	cRows, err := db.Query("SELECT id, merchant_id, name, sort_order FROM menu_categories ORDER BY sort_order ASC")
	if err != nil {
		return fmt.Errorf("query categories: %w", err)
	}
	defer cRows.Close()

	for cRows.Next() {
		var cat domain.MenuCategory
		var mID string
		if err := cRows.Scan(&cat.ID, &mID, &cat.Name, &cat.SortOrder); err != nil {
			return fmt.Errorf("scan category: %w", err)
		}
		catMap[cat.ID] = &cat
		if row, ok := st.Merchants[mID]; ok {
			row.Merchant.Menu = append(row.Merchant.Menu, cat)
		}
	}

	// Items
	itemMap := map[string]*domain.MenuItem{}
	itemRows, err := db.Query("SELECT id, merchant_id, category_id, name, description, image_url, price_centavos, is_available FROM menu_items ORDER BY created_at ASC")
	if err != nil {
		return fmt.Errorf("query items: %w", err)
	}
	defer itemRows.Close()

	for itemRows.Next() {
		var item domain.MenuItem
		var mID, catID string
		var desc, img sql.NullString
		if err := itemRows.Scan(&item.ID, &mID, &catID, &item.Name, &desc, &img, &item.PriceCentavos, &item.IsAvailable); err != nil {
			return fmt.Errorf("scan item: %w", err)
		}
		item.CategoryID = catID
		item.Description = strPtr(desc)
		item.PhotoURL = strPtr(img)
		item.AddonGroups = []domain.AddonGroup{}
		itemMap[item.ID] = &item

		if row, ok := st.Merchants[mID]; ok {
			for i := range row.Merchant.Menu {
				if row.Merchant.Menu[i].ID == catID {
					row.Merchant.Menu[i].Items = append(row.Merchant.Menu[i].Items, item)
					break
				}
			}
		}
	}

	// Modifier Groups
	type groupEntry struct {
		grp    *domain.AddonGroup
		itemID string
	}
	var groupList []groupEntry
	groupMap := map[string]*domain.AddonGroup{}
	gRows, err := db.Query("SELECT id, menu_item_id, name, min_selections, max_selections FROM menu_modifier_groups")
	if err != nil {
		return fmt.Errorf("query groups: %w", err)
	}
	defer gRows.Close()

	for gRows.Next() {
		g := &domain.AddonGroup{Options: []domain.AddonOption{}}
		var itemID string
		if err := gRows.Scan(&g.ID, &itemID, &g.Name, &g.MinSelect, &g.MaxSelect); err != nil {
			return fmt.Errorf("scan group: %w", err)
		}
		groupMap[g.ID] = g
		groupList = append(groupList, groupEntry{grp: g, itemID: itemID})
	}

	// Modifier Options
	optRows, err := db.Query("SELECT id, modifier_group_id, name, price_centavos, is_available FROM menu_modifier_options")
	if err != nil {
		return fmt.Errorf("query options: %w", err)
	}
	defer optRows.Close()

	for optRows.Next() {
		var opt domain.AddonOption
		var groupID string
		if err := optRows.Scan(&opt.ID, &groupID, &opt.Name, &opt.PriceCentavos, &opt.IsAvailable); err != nil {
			return fmt.Errorf("scan option: %w", err)
		}
		if grp, ok := groupMap[groupID]; ok {
			grp.Options = append(grp.Options, opt)
		}
	}

	for _, ge := range groupList {
		if itm, ok := itemMap[ge.itemID]; ok {
			itm.AddonGroups = append(itm.AddonGroups, *ge.grp)
		}
	}

	for _, m := range st.Merchants {
		for i := range m.Merchant.Menu {
			for j := range m.Merchant.Menu[i].Items {
				if itm, ok := itemMap[m.Merchant.Menu[i].Items[j].ID]; ok {
					m.Merchant.Menu[i].Items[j].AddonGroups = itm.AddonGroups
				}
			}
		}
	}

	// Staff
	staffRows, err := db.Query("SELECT merchant_id, user_phone, staff_name, role FROM merchant_staff")
	if err != nil {
		return fmt.Errorf("query staff: %w", err)
	}
	defer staffRows.Close()

	for staffRows.Next() {
		var sf domain.MerchantStaff
		if err := staffRows.Scan(&sf.MerchantID, &sf.UserPhone, &sf.StaffName, &sf.Role); err != nil {
			return fmt.Errorf("scan staff: %w", err)
		}
		st.Staff[sf.UserPhone] = sf
	}

	// 4. Riders
	rRows, err := db.Query("SELECT id, user_id, status, is_online, vehicle_type, plate_number, vehicle_model, vehicle_color, rejection_reason, rating, rating_sum, rating_count, balance_centavos, min_balance_centavos, current_latitude, current_longitude, last_location_updated_at, active_job_id, submitted_at FROM riders")
	if err != nil {
		return fmt.Errorf("query riders: %w", err)
	}
	defer rRows.Close()

	for rRows.Next() {
		var rd domain.Rider
		var vType, plate, model, color, rej, actJob sql.NullString
		var rating, lat, lng sql.NullFloat64
		var locAt, subAt sql.NullTime

		if err := rRows.Scan(
			&rd.Profile.ID, &rd.Profile.UserID, &rd.Profile.Status, &rd.Profile.IsOnline,
			&vType, &plate, &model, &color, &rej, &rating, &rd.RatingSum, &rd.RatingCount,
			&rd.Profile.BalanceCentavos, &rd.Profile.MinBalanceCentavos,
			&lat, &lng, &locAt, &actJob, &subAt,
		); err != nil {
			return fmt.Errorf("scan rider: %w", err)
		}

		if plate.Valid && plate.String != "" {
			rd.Profile.Vehicle = &domain.Vehicle{
				Plate:     plate.String,
				MakeModel: model.String,
				Color:     color.String,
				Type:      vType.String,
			}
		}
		rd.Profile.RejectionReason = strPtr(rej)
		rd.Profile.Rating = floatPtr(rating)
		if lat.Valid && lng.Valid {
			rd.Location = &domain.LatLng{Lat: lat.Float64, Lng: lng.Float64}
		}
		if locAt.Valid {
			rd.LocationAt = locAt.Time.UTC()
		}
		if actJob.Valid {
			rd.ActiveJobID = actJob.String
		}
		if subAt.Valid {
			rd.SubmittedAt = subAt.Time.UTC()
		}
		rd.Documents = map[string]string{}
		st.Riders[rd.Profile.UserID] = &rd
	}

	docRows, err := db.Query("SELECT r.user_id, d.document_type, d.document_url FROM kyc_documents d JOIN riders r ON d.rider_id = r.id")
	if err == nil {
		defer docRows.Close()
		for docRows.Next() {
			var uid, docType, docURL string
			if err := docRows.Scan(&uid, &docType, &docURL); err == nil {
				if rd, ok := st.Riders[uid]; ok {
					rd.Documents[docType] = docURL
				}
			}
		}
	}

	// 5. Orders (Jobs)
	oRows, err := db.Query(`
		SELECT
			id, order_number, service, customer_id, merchant_id, rider_user_id, status,
			pickup_address, pickup_latitude, pickup_longitude, pickup_contact_name, pickup_contact_phone, pickup_notes,
			dropoff_address, dropoff_latitude, dropoff_longitude, dropoff_contact_name, dropoff_contact_phone, dropoff_notes,
			distance_meters, duration_seconds, share_token,
			pabili_store_name, pabili_items_json, pabili_estimated_item_total_centavos, pabili_receipt_url, pabili_item_total_centavos,
			padala_size, padala_description, padala_recipient_name, padala_recipient_phone, padala_photo_url,
			food_subtotal_centavos, food_prep_time_minutes, food_ready_at, food_is_ready, merchant_accept_deadline, merchant_order_status, merchant_reject_reason,
			subtotal_centavos, total_centavos, fare_breakdown_json, fees_centavos, earnings_centavos, commission_centavos,
			payment_method, payment_status, payment_checkout_url, proof_of_delivery_url, cancellation_reason, cancelled_by,
			rated, searching_since, completed_at, created_at, updated_at
		FROM orders ORDER BY created_at ASC
	`)
	if err != nil {
		return fmt.Errorf("query orders: %w", err)
	}
	defer oRows.Close()

	for oRows.Next() {
		var js domain.JobState
		var mID, rUID, pContactName, pContactPhone, pNotes, dContactName, dContactPhone, dNotes sql.NullString
		var shareToken, pStore, pReceipt, padalaSize, padalaDesc, padalaRecipName, padalaRecipPhone, padalaPhoto sql.NullString
		var foodPrepTime sql.NullInt64
		var foodReadyAt, merchDeadline, searchSince, compAt sql.NullTime
		var merchOrderStatus, merchRejectReason, checkoutURL, proofURL, cancelReason, cancelledBy sql.NullString
		var pItemTotal sql.NullInt64
		var pItemsJSON, fareBreakdownJSON []byte
		var createdAt, updatedAt time.Time
		var distM, durS, pEstTotal, foodSubtotal int
		var foodIsReady bool
		var subtotalCentavos, totalCentavos int

		if err := oRows.Scan(
			&js.Job.ID, &js.Job.Code, &js.Job.Service, &js.CustomerID, &mID, &rUID, &js.Job.Status,
			&js.Job.Pickup.Address, &js.Job.Pickup.Location.Lat, &js.Job.Pickup.Location.Lng, &pContactName, &pContactPhone, &pNotes,
			&js.Job.Dropoff.Address, &js.Job.Dropoff.Location.Lat, &js.Job.Dropoff.Location.Lng, &dContactName, &dContactPhone, &dNotes,
			&distM, &durS, &shareToken,
			&pStore, &pItemsJSON, &pEstTotal, &pReceipt, &pItemTotal,
			&padalaSize, &padalaDesc, &padalaRecipName, &padalaRecipPhone, &padalaPhoto,
			&foodSubtotal, &foodPrepTime, &foodReadyAt, &foodIsReady, &merchDeadline, &merchOrderStatus, &merchRejectReason,
			&subtotalCentavos, &totalCentavos, &fareBreakdownJSON, &js.FeesCentavos, &js.EarningsCentavos, &js.CommissionCentavos,
			&js.Job.Payment.Method, &js.Job.Payment.Status, &checkoutURL, &proofURL, &cancelReason, &cancelledBy,
			&js.Rated, &searchSince, &compAt, &createdAt, &updatedAt,
		); err != nil {
			return fmt.Errorf("scan order: %w", err)
		}

		js.Job.Fare.TotalCentavos = totalCentavos
		js.MerchantID = mID.String
		js.RiderUserID = rUID.String
		js.Job.Pickup.ContactName = strPtr(pContactName)
		js.Job.Pickup.ContactPhone = strPtr(pContactPhone)
		js.Job.Pickup.Notes = strPtr(pNotes)
		js.Job.Dropoff.ContactName = strPtr(dContactName)
		js.Job.Dropoff.ContactPhone = strPtr(dContactPhone)
		js.Job.Dropoff.Notes = strPtr(dNotes)
		js.ShareToken = shareToken.String
		js.Job.ProofURL = strPtr(proofURL)
		js.Job.CancelReason = strPtr(cancelReason)
		js.Job.CancelledBy = strPtr(cancelledBy)
		js.Job.Payment.CheckoutURL = strPtr(checkoutURL)
		js.Job.CreatedAt = domain.UTC{Time: createdAt.UTC()}
		js.Job.UpdatedAt = domain.UTC{Time: updatedAt.UTC()}
		if searchSince.Valid {
			js.SearchingSince = searchSince.Time.UTC()
		}
		if compAt.Valid {
			js.CompletedAt = compAt.Time.UTC()
		}
		if merchDeadline.Valid {
			js.MerchantDeadline = merchDeadline.Time.UTC()
		}

		_ = json.Unmarshal(fareBreakdownJSON, &js.Job.Fare.Breakdown)

		switch js.Job.Service {
		case "food":
			var ready *domain.UTC
			if foodReadyAt.Valid {
				ready = &domain.UTC{Time: foodReadyAt.Time.UTC()}
			}
			js.Job.Food = &domain.JobFood{
				SubtotalCentavos: foodSubtotal,
				PrepTimeMinutes:  intPtr(foodPrepTime),
				ReadyAt:          ready,
				IsReady:          foodIsReady,
			}
			if js.MerchantID != "" {
				if m, ok := st.Merchants[js.MerchantID]; ok {
					js.Job.Merchant = &domain.JobMerchant{
						ID:          m.Merchant.ID,
						Name:        m.Merchant.Name,
						PhoneMasked: domain.MaskPhone(m.Phone),
					}
				}
			}
			if merchOrderStatus.Valid {
				js.Order = &domain.MerchantOrderState{
					ID:           domain.NewID(),
					Status:       merchOrderStatus.String,
					RejectReason: strPtr(merchRejectReason),
					Commission:   js.CommissionCentavos,
				}
			}
		case "pabili":
			var items []domain.PabiliItem
			_ = json.Unmarshal(pItemsJSON, &items)
			js.Job.Pabili = &domain.JobPabili{
				StoreName:         pStore.String,
				Items:             items,
				ReceiptURL:        strPtr(pReceipt),
				ItemTotalCentavos: intPtr(pItemTotal),
			}
		case "padala":
			js.Job.Padala = &domain.JobPadala{
				Size:           padalaSize.String,
				Description:    padalaDesc.String,
				RecipientName:  padalaRecipName.String,
				RecipientPhone: padalaRecipPhone.String,
				PhotoURL:       strPtr(padalaPhoto),
			}
		}

		if js.RiderUserID != "" {
			if r, ok := st.Riders[js.RiderUserID]; ok {
				u := st.Users[js.RiderUserID]
				name := "Rider"
				if u != nil {
					name = u.Name
				}
				plate, model, color := "", "", ""
				if r.Profile.Vehicle != nil {
					plate = r.Profile.Vehicle.Plate
					model = r.Profile.Vehicle.MakeModel
					color = r.Profile.Vehicle.Color
				}
				js.Job.Rider = &domain.JobRider{
					ID:          r.Profile.ID,
					Name:        name,
					PhoneMasked: domain.MaskPhone(u.Phone),
					Plate:       plate,
					MakeModel:   model,
					Color:       color,
					Rating:      r.Profile.Rating,
				}
			}
		}

		st.Jobs[js.Job.ID] = &js
		st.JobIDs = append(st.JobIDs, js.Job.ID)
		if js.ShareToken != "" {
			st.Shares[js.ShareToken] = js.Job.ID
		}

		if strings.HasPrefix(js.Job.Code, "GO-") {
			if n, err := strconv.Atoi(js.Job.Code[3:]); err == nil && n > st.CodeSeq {
				st.CodeSeq = n
			}
		}
	}

	// Timeline
	tlRows, err := db.Query("SELECT order_id, to_status, created_at FROM order_status_history ORDER BY created_at ASC")
	if err == nil {
		defer tlRows.Close()
		for tlRows.Next() {
			var oid, status string
			var at time.Time
			if err := tlRows.Scan(&oid, &status, &at); err == nil {
				if js, ok := st.Jobs[oid]; ok {
					js.Job.Timeline = append(js.Job.Timeline, domain.TimelineEntry{Status: status, At: domain.UTC{Time: at.UTC()}})
				}
			}
		}
	}

	// Order Items
	oiRows, err := db.Query("SELECT order_id, item_name, quantity, subtotal_centavos, selected_options_json, special_instructions FROM order_items")
	if err == nil {
		defer oiRows.Close()
		for oiRows.Next() {
			var oid, name string
			var qty, sub int
			var optJSON []byte
			var note sql.NullString
			if err := oiRows.Scan(&oid, &name, &qty, &sub, &optJSON, &note); err == nil {
				if js, ok := st.Jobs[oid]; ok && js.Job.Food != nil {
					var addons []string
					_ = json.Unmarshal(optJSON, &addons)
					js.Job.Food.Items = append(js.Job.Food.Items, domain.OrderLine{
						Name:              name,
						Quantity:          qty,
						Addons:            addons,
						Note:              strPtr(note),
						LineTotalCentavos: sub,
					})
				}
			}
		}
	}

	// 6. Wallet Transactions
	txRows, err := db.Query("SELECT id, user_id, transaction_type, amount_centavos, balance_after_centavos, order_id, description, created_at FROM wallet_transactions ORDER BY created_at DESC")
	if err == nil {
		defer txRows.Close()
		for txRows.Next() {
			var tx domain.WalletTransaction
			var uID, oID, desc sql.NullString
			var createdAt time.Time
			if err := txRows.Scan(&tx.ID, &uID, &tx.Type, &tx.AmountCentavos, &tx.BalanceAfterCentavos, &oID, &desc, &createdAt); err == nil {
				tx.UserID = uID.String
				tx.JobID = strPtr(oID)
				tx.Note = strPtr(desc)
				tx.CreatedAt = domain.UTC{Time: createdAt.UTC()}
				st.Txs = append(st.Txs, &tx)
			}
		}
	}

	// 7. Chats
	chatRows, err := db.Query("SELECT id, order_id, sender, text, image_url, created_at FROM chat_messages ORDER BY created_at ASC")
	if err == nil {
		defer chatRows.Close()
		for chatRows.Next() {
			var cm domain.ChatMessage
			var txt, img sql.NullString
			var createdAt time.Time
			if err := chatRows.Scan(&cm.ID, &cm.JobID, &cm.Sender, &txt, &img, &createdAt); err == nil {
				cm.Text = strPtr(txt)
				cm.ImageURL = strPtr(img)
				cm.CreatedAt = domain.UTC{Time: createdAt.UTC()}
				st.Chats[cm.JobID] = append(st.Chats[cm.JobID], &cm)
			}
		}
	}

	// 8. Payouts
	payoutRows, err := db.Query("SELECT id, merchant_id, period_from, period_to, amount_centavos, type, status, paid_at FROM merchant_payouts")
	if err == nil {
		defer payoutRows.Close()
		for payoutRows.Next() {
			var p domain.Payout
			var from, to time.Time
			var paidAt sql.NullTime
			if err := payoutRows.Scan(&p.ID, &p.MerchantID, &from, &to, &p.AmountCentavos, &p.Type, &p.Status, &paidAt); err == nil {
				p.PeriodFrom = from.Format("2006-01-02")
				p.PeriodTo = to.Format("2006-01-02")
				p.PaidAt = utcPtr(paidAt)
				st.Payouts = append(st.Payouts, &p)
			}
		}
	}

	// 9. Topups
	topupRows, err := db.Query("SELECT id, user_id, amount_centavos, method, status FROM topups")
	if err == nil {
		defer topupRows.Close()
		for topupRows.Next() {
			var tp domain.Topup
			if err := topupRows.Scan(&tp.ID, &tp.UserID, &tp.AmountCentavos, &tp.Method, &tp.Status); err == nil {
				st.Topups[tp.ID] = &tp
			}
		}
	}

	// 10. Reviews
	revRows, err := db.Query("SELECT order_id, rider_rating, rider_tags, rider_comment, merchant_rating FROM reviews")
	if err == nil {
		defer revRows.Close()
		for revRows.Next() {
			var r domain.Rating
			var tags []string
			var comment sql.NullString
			var mRating sql.NullInt64
			if err := revRows.Scan(&r.JobID, &r.RiderRating, pq.Array(&tags), &comment, &mRating); err == nil {
				r.RiderTags = tags
				r.Comment = strPtr(comment)
				r.MerchantRating = intPtr(mRating)
				st.Ratings = append(st.Ratings, r)
			}
		}
	}

	// 11. SOS Alerts
	sosRows, err := db.Query("SELECT order_id, user_id, latitude, longitude, created_at FROM sos_alerts")
	if err == nil {
		defer sosRows.Close()
		for sosRows.Next() {
			var a domain.SOSAlert
			var at time.Time
			if err := sosRows.Scan(&a.JobID, &a.UserID, &a.Location.Lat, &a.Location.Lng, &at); err == nil {
				a.At = domain.UTC{Time: at.UTC()}
				st.SOS = append(st.SOS, a)
			}
		}
	}

	// 12. Sessions & Tokens
	refRows, err := db.Query("SELECT token_hash, user_id, app, expires_at FROM refresh_tokens")
	if err == nil {
		defer refRows.Close()
		for refRows.Next() {
			var token, uid, app string
			var exp time.Time
			if err := refRows.Scan(&token, &uid, &app, &exp); err == nil {
				st.Refresh[token] = domain.RefreshToken{UserID: uid, App: app, Expires: exp}
			}
		}
	}

	devRows, err := db.Query("SELECT user_id, token, platform, app FROM device_tokens")
	if err == nil {
		defer devRows.Close()
		for devRows.Next() {
			var d domain.Device
			if err := devRows.Scan(&d.UserID, &d.Token, &d.Platform, &d.App); err == nil {
				st.Devices[d.UserID] = d
			}
		}
	}

	upRows, err := db.Query("SELECT key, purpose FROM upload_records")
	if err == nil {
		defer upRows.Close()
		for upRows.Next() {
			var k, p string
			if err := upRows.Scan(&k, &p); err == nil {
				st.Uploads[k] = p
			}
		}
	}

	idemRows, err := db.Query("SELECT key, response_payload FROM idempotency_keys")
	if err == nil {
		defer idemRows.Close()
		for idemRows.Next() {
			var k, v string
			if err := idemRows.Scan(&k, &v); err == nil {
				st.Idempotency[k] = v
			}
		}
	}

	log.Printf("loaded postgres state: %d users, %d jobs, %d riders, %d merchants", len(st.Users), len(st.Jobs), len(st.Riders), len(st.Merchants))
	return nil
}

// ---------- Save ----------

// Save transactionally persists all dirty entities to PostgreSQL tables.
func Save(db *sql.DB, st *repository.State) error {
	if db == nil || st == nil {
		return nil
	}

	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback() }()

	// 1. Users
	for _, u := range st.Users {
		var phoneVal sql.NullString
		if u.Phone != "" {
			phoneVal = sql.NullString{String: u.Phone, Valid: true}
		}
		var dbID string
		if err := tx.QueryRow(`
			INSERT INTO users (id, phone_number, email, full_name, language, roles, google_id, facebook_id, avatar_url, is_active, created_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true, $10, NOW())
			ON CONFLICT (id) DO UPDATE SET
				phone_number = COALESCE(EXCLUDED.phone_number, users.phone_number),
				email = COALESCE(EXCLUDED.email, users.email),
				google_id = COALESCE(EXCLUDED.google_id, users.google_id),
				facebook_id = COALESCE(EXCLUDED.facebook_id, users.facebook_id),
				avatar_url = COALESCE(EXCLUDED.avatar_url, users.avatar_url),
				full_name = EXCLUDED.full_name,
				language = EXCLUDED.language,
				roles = EXCLUDED.roles,
				updated_at = NOW()
			RETURNING id;
		`, u.ID, phoneVal, nullStr(u.Email), u.Name, u.Language, pq.Array(u.Roles), nullStr(u.GoogleID), nullStr(u.FacebookID), nullStr(u.AvatarURL), u.CreatedAt.Time).Scan(&dbID); err != nil {
			return fmt.Errorf("save user %s: %w", u.ID, err)
		}
		if dbID != "" && dbID != u.ID {
			delete(st.Users, u.ID)
			u.ID = dbID
			st.Users[dbID] = u
			if u.Phone != "" {
				st.UserByPhone[u.Phone] = dbID
			}
			if u.GoogleID != nil {
				st.UserByGoogleID[*u.GoogleID] = dbID
			}
			if u.FacebookID != nil {
				st.UserByFacebookID[*u.FacebookID] = dbID
			}
			if u.Email != nil {
				st.UserByEmail[*u.Email] = dbID
			}
		}
	}

	// 2. Saved Places
	for _, p := range st.Places {
		if _, err := tx.Exec(`
			INSERT INTO user_addresses (id, user_id, label, address_line1, latitude, longitude, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, NOW())
			ON CONFLICT (id) DO UPDATE SET
				label = EXCLUDED.label,
				address_line1 = EXCLUDED.address_line1,
				latitude = EXCLUDED.latitude,
				longitude = EXCLUDED.longitude,
				updated_at = NOW();
		`, p.ID, p.UserID, p.Label, p.Address, p.Location.Lat, p.Location.Lng); err != nil {
			return fmt.Errorf("save place %s: %w", p.ID, err)
		}
	}

	// 3. Merchants & Catalog
	for _, m := range st.Merchants {
		merch := m.Merchant
		if _, err := tx.Exec(`
			INSERT INTO merchants (id, name, logo_url, cover_url, address_line1, latitude, longitude, is_accepting_orders, paused_until, avg_preparation_time_minutes, rating, min_order_centavos, rating_sum, rating_count, phone_number, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW())
			ON CONFLICT (id) DO UPDATE SET
				name = EXCLUDED.name,
				logo_url = EXCLUDED.logo_url,
				cover_url = EXCLUDED.cover_url,
				address_line1 = EXCLUDED.address_line1,
				latitude = EXCLUDED.latitude,
				longitude = EXCLUDED.longitude,
				is_accepting_orders = EXCLUDED.is_accepting_orders,
				paused_until = EXCLUDED.paused_until,
				avg_preparation_time_minutes = EXCLUDED.avg_preparation_time_minutes,
				rating = EXCLUDED.rating,
				min_order_centavos = EXCLUDED.min_order_centavos,
				rating_sum = EXCLUDED.rating_sum,
				rating_count = EXCLUDED.rating_count,
				phone_number = EXCLUDED.phone_number,
				updated_at = NOW();
		`, merch.ID, merch.Name, nullStr(merch.LogoURL), nullStr(merch.CoverURL), merch.Address, merch.Location.Lat, merch.Location.Lng, merch.IsOpen, nullUTC(merch.PausedUntil), merch.PrepTimeMinutes, nullFloat(merch.Rating), merch.MinOrderCentavos, m.RatingSum, m.RatingCount, m.Phone); err != nil {
			return fmt.Errorf("save merchant %s: %w", merch.ID, err)
		}

		for _, h := range merch.Hours {
			if _, err := tx.Exec(`
				INSERT INTO merchant_operating_hours (merchant_id, day_of_week, open_time, close_time, is_closed)
				VALUES ($1, $2, $3::TIME, $4::TIME, false)
				ON CONFLICT (merchant_id, day_of_week) DO UPDATE SET
					open_time = EXCLUDED.open_time,
					close_time = EXCLUDED.close_time;
			`, merch.ID, h.Weekday, h.Opens, h.Closes); err != nil {
				return fmt.Errorf("save merchant hours %s: %w", merch.ID, err)
			}
		}

		for _, cat := range merch.Menu {
			if _, err := tx.Exec(`
				INSERT INTO menu_categories (id, merchant_id, name, sort_order)
				VALUES ($1, $2, $3, $4)
				ON CONFLICT (id) DO UPDATE SET
					name = EXCLUDED.name,
					sort_order = EXCLUDED.sort_order;
			`, cat.ID, merch.ID, cat.Name, cat.SortOrder); err != nil {
				return fmt.Errorf("save category %s: %w", cat.ID, err)
			}

			for _, itm := range cat.Items {
				basePrice := float64(itm.PriceCentavos) / 100.0
				if _, err := tx.Exec(`
					INSERT INTO menu_items (id, merchant_id, category_id, name, description, image_url, price_centavos, base_price, is_available, updated_at)
					VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
					ON CONFLICT (id) DO UPDATE SET
						name = EXCLUDED.name,
						description = EXCLUDED.description,
						image_url = EXCLUDED.image_url,
						price_centavos = EXCLUDED.price_centavos,
						base_price = EXCLUDED.base_price,
						is_available = EXCLUDED.is_available,
						updated_at = NOW();
				`, itm.ID, merch.ID, cat.ID, itm.Name, nullStr(itm.Description), nullStr(itm.PhotoURL), itm.PriceCentavos, basePrice, itm.IsAvailable); err != nil {
					return fmt.Errorf("save item %s: %w", itm.ID, err)
				}

				for _, grp := range itm.AddonGroups {
					if _, err := tx.Exec(`
						INSERT INTO menu_modifier_groups (id, menu_item_id, name, min_selections, max_selections)
						VALUES ($1, $2, $3, $4, $5)
						ON CONFLICT (id) DO UPDATE SET
							name = EXCLUDED.name,
							min_selections = EXCLUDED.min_selections,
							max_selections = EXCLUDED.max_selections;
					`, grp.ID, itm.ID, grp.Name, grp.MinSelect, grp.MaxSelect); err != nil {
						return fmt.Errorf("save addon group %s: %w", grp.ID, err)
					}

					for _, opt := range grp.Options {
						priceDelta := float64(opt.PriceCentavos) / 100.0
						if _, err := tx.Exec(`
							INSERT INTO menu_modifier_options (id, modifier_group_id, name, price_centavos, price_delta, is_available)
							VALUES ($1, $2, $3, $4, $5, $6)
							ON CONFLICT (id) DO UPDATE SET
								name = EXCLUDED.name,
								price_centavos = EXCLUDED.price_centavos,
								price_delta = EXCLUDED.price_delta,
								is_available = EXCLUDED.is_available;
						`, opt.ID, grp.ID, opt.Name, opt.PriceCentavos, priceDelta, opt.IsAvailable); err != nil {
							return fmt.Errorf("save addon option %s: %w", opt.ID, err)
						}
					}
				}
			}
		}
	}

	// 4. Staff
	for _, sf := range st.Staff {
		if _, err := tx.Exec(`
			INSERT INTO merchant_staff (merchant_id, user_phone, staff_name, role)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (merchant_id, user_phone) DO UPDATE SET
				staff_name = EXCLUDED.staff_name,
				role = EXCLUDED.role;
		`, sf.MerchantID, sf.UserPhone, sf.StaffName, sf.Role); err != nil {
			return fmt.Errorf("save staff %s: %w", sf.UserPhone, err)
		}
	}

	// 5. Riders
	for _, rd := range st.Riders {
		plate, model, color := "", "", ""
		if rd.Profile.Vehicle != nil {
			plate = rd.Profile.Vehicle.Plate
			model = rd.Profile.Vehicle.MakeModel
			color = rd.Profile.Vehicle.Color
		}
		var lat, lng *float64
		if rd.Location != nil {
			lat = &rd.Location.Lat
			lng = &rd.Location.Lng
		}
		var actJob *string
		if rd.ActiveJobID != "" {
			actJob = &rd.ActiveJobID
		}

		vType := rd.VehicleType()
		if _, err := tx.Exec(`
			INSERT INTO riders (id, user_id, vehicle_type, plate_number, vehicle_model, vehicle_color, status, is_online, rejection_reason, rating, rating_sum, rating_count, balance_centavos, min_balance_centavos, current_latitude, current_longitude, last_location_updated_at, active_job_id, submitted_at, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, NOW())
			ON CONFLICT (user_id) DO UPDATE SET
				vehicle_type = EXCLUDED.vehicle_type,
				plate_number = EXCLUDED.plate_number,
				vehicle_model = EXCLUDED.vehicle_model,
				vehicle_color = EXCLUDED.vehicle_color,
				status = EXCLUDED.status,
				is_online = EXCLUDED.is_online,
				rejection_reason = EXCLUDED.rejection_reason,
				rating = EXCLUDED.rating,
				rating_sum = EXCLUDED.rating_sum,
				rating_count = EXCLUDED.rating_count,
				balance_centavos = EXCLUDED.balance_centavos,
				min_balance_centavos = EXCLUDED.min_balance_centavos,
				current_latitude = EXCLUDED.current_latitude,
				current_longitude = EXCLUDED.current_longitude,
				last_location_updated_at = EXCLUDED.last_location_updated_at,
				active_job_id = EXCLUDED.active_job_id,
				submitted_at = EXCLUDED.submitted_at,
				updated_at = NOW();
		`, rd.Profile.ID, rd.Profile.UserID, vType, plate, model, color, rd.Profile.Status, rd.Profile.IsOnline, nullStr(rd.Profile.RejectionReason), nullFloat(rd.Profile.Rating), rd.RatingSum, rd.RatingCount, rd.Profile.BalanceCentavos, rd.Profile.MinBalanceCentavos, nullFloat(lat), nullFloat(lng), rd.LocationAt, nullStr(actJob), rd.SubmittedAt); err != nil {
			return fmt.Errorf("save rider %s: %w", rd.Profile.UserID, err)
		}

		_, _ = tx.Exec("DELETE FROM kyc_documents WHERE rider_id = $1;", rd.Profile.ID)
		for docType, docURL := range rd.Documents {
			if _, err := tx.Exec(`
				INSERT INTO kyc_documents (rider_id, document_type, document_url)
				VALUES ($1, $2, $3);
			`, rd.Profile.ID, docType, docURL); err != nil {
				return fmt.Errorf("save rider doc %s: %w", docType, err)
			}
		}
	}

	// 6. Orders (Jobs)
	for _, js := range st.Jobs {
		j := &js.Job
		var mID *string
		if js.MerchantID != "" {
			mID = &js.MerchantID
		}
		var rUID *string
		var rID *string
		if js.RiderUserID != "" {
			rUID = &js.RiderUserID
			if r, ok := st.Riders[js.RiderUserID]; ok {
				rID = &r.Profile.ID
			}
		}

		fbJSON, _ := json.Marshal(j.Fare.Breakdown)
		subtotalCentavos := j.Fare.TotalCentavos
		totalAmount := float64(j.Fare.TotalCentavos) / 100.0

		var pStore *string
		var pReceipt *string
		var pItemTotal *int
		var pItemsJSON []byte = []byte("[]")
		if j.Pabili != nil {
			pStore = &j.Pabili.StoreName
			pReceipt = j.Pabili.ReceiptURL
			pItemTotal = j.Pabili.ItemTotalCentavos
			pItemsJSON, _ = json.Marshal(j.Pabili.Items)
		}

		var padalaSize, padalaDesc, padalaRecipName, padalaRecipPhone, padalaPhoto *string
		if j.Padala != nil {
			padalaSize = &j.Padala.Size
			padalaDesc = &j.Padala.Description
			padalaRecipName = &j.Padala.RecipientName
			padalaRecipPhone = &j.Padala.RecipientPhone
			padalaPhoto = j.Padala.PhotoURL
		}

		var foodSubtotal int
		var foodPrepTime *int
		var foodReadyAt *domain.UTC
		var foodIsReady bool
		var merchOrderStatus *string
		var merchRejectReason *string
		if j.Food != nil {
			foodSubtotal = j.Food.SubtotalCentavos
			foodPrepTime = j.Food.PrepTimeMinutes
			foodReadyAt = j.Food.ReadyAt
			foodIsReady = j.Food.IsReady
		}
		if js.Order != nil {
			merchOrderStatus = &js.Order.Status
			merchRejectReason = js.Order.RejectReason
		}

		var searchSince *time.Time
		if !js.SearchingSince.IsZero() {
			t := js.SearchingSince.UTC()
			searchSince = &t
		}
		var compAt *time.Time
		if !js.CompletedAt.IsZero() {
			t := js.CompletedAt.UTC()
			compAt = &t
		}
		var merchDeadline *time.Time
		if !js.MerchantDeadline.IsZero() {
			t := js.MerchantDeadline.UTC()
			merchDeadline = &t
		}
		var shareToken *string
		if js.ShareToken != "" {
			shareToken = &js.ShareToken
		}

		if _, err := tx.Exec(`
			INSERT INTO orders (
				id, order_number, service, customer_id, merchant_id, rider_id, rider_user_id, status,
				pickup_address, pickup_latitude, pickup_longitude, pickup_contact_name, pickup_contact_phone, pickup_notes,
				dropoff_address, dropoff_latitude, dropoff_longitude, dropoff_contact_name, dropoff_contact_phone, dropoff_notes,
				distance_meters, duration_seconds, share_token,
				pabili_store_name, pabili_items_json, pabili_estimated_item_total_centavos, pabili_receipt_url, pabili_item_total_centavos,
				padala_size, padala_description, padala_recipient_name, padala_recipient_phone, padala_photo_url,
				food_subtotal_centavos, food_prep_time_minutes, food_ready_at, food_is_ready, merchant_accept_deadline, merchant_order_status, merchant_reject_reason,
				subtotal_centavos, total_centavos, subtotal, total_amount, fare_breakdown_json, fees_centavos, earnings_centavos, commission_centavos,
				payment_method, payment_status, payment_checkout_url, proof_of_delivery_url, cancellation_reason, cancelled_by,
				rated, searching_since, completed_at, created_at, updated_at
			) VALUES (
				$1, $2, $3, $4, $5, $6, $7, $8,
				$9, $10, $11, $12, $13, $14,
				$15, $16, $17, $18, $19, $20,
				0, 0, $21,
				$22, $23, 0, $24, $25,
				$26, $27, $28, $29, $30,
				$31, $32, $33, $34, $35, $36, $37,
				$38, $39, $40, $41, $42, $43, $44, $45,
				$46, $47, $48, $49, $50, $51,
				$52, $53, $54, $55, NOW()
			)
			ON CONFLICT (id) DO UPDATE SET
				rider_id = EXCLUDED.rider_id,
				rider_user_id = EXCLUDED.rider_user_id,
				status = EXCLUDED.status,
				share_token = EXCLUDED.share_token,
				pabili_receipt_url = EXCLUDED.pabili_receipt_url,
				pabili_item_total_centavos = EXCLUDED.pabili_item_total_centavos,
				food_ready_at = EXCLUDED.food_ready_at,
				food_is_ready = EXCLUDED.food_is_ready,
				merchant_accept_deadline = EXCLUDED.merchant_accept_deadline,
				merchant_order_status = EXCLUDED.merchant_order_status,
				merchant_reject_reason = EXCLUDED.merchant_reject_reason,
				total_centavos = EXCLUDED.total_centavos,
				total_amount = EXCLUDED.total_amount,
				fare_breakdown_json = EXCLUDED.fare_breakdown_json,
				payment_status = EXCLUDED.payment_status,
				payment_checkout_url = EXCLUDED.payment_checkout_url,
				proof_of_delivery_url = EXCLUDED.proof_of_delivery_url,
				cancellation_reason = EXCLUDED.cancellation_reason,
				cancelled_by = EXCLUDED.cancelled_by,
				rated = EXCLUDED.rated,
				searching_since = EXCLUDED.searching_since,
				completed_at = EXCLUDED.completed_at,
				updated_at = NOW();
		`,
			j.ID, j.Code, j.Service, js.CustomerID, nullStr(mID), nullStr(rID), nullStr(rUID), j.Status,
			j.Pickup.Address, j.Pickup.Location.Lat, j.Pickup.Location.Lng, nullStr(j.Pickup.ContactName), nullStr(j.Pickup.ContactPhone), nullStr(j.Pickup.Notes),
			j.Dropoff.Address, j.Dropoff.Location.Lat, j.Dropoff.Location.Lng, nullStr(j.Dropoff.ContactName), nullStr(j.Dropoff.ContactPhone), nullStr(j.Dropoff.Notes),
			nullStr(shareToken),
			nullStr(pStore), pItemsJSON, nullStr(pReceipt), nullInt(pItemTotal),
			nullStr(padalaSize), nullStr(padalaDesc), nullStr(padalaRecipName), nullStr(padalaRecipPhone), nullStr(padalaPhoto),
			foodSubtotal, nullInt(foodPrepTime), nullUTC(foodReadyAt), foodIsReady, merchDeadline, nullStr(merchOrderStatus), nullStr(merchRejectReason),
			subtotalCentavos, j.Fare.TotalCentavos, totalAmount, totalAmount, fbJSON, js.FeesCentavos, js.EarningsCentavos, js.CommissionCentavos,
			j.Payment.Method, j.Payment.Status, nullStr(j.Payment.CheckoutURL), nullStr(j.ProofURL), nullStr(j.CancelReason), nullStr(j.CancelledBy),
			js.Rated, searchSince, compAt, j.CreatedAt.Time,
		); err != nil {
			return fmt.Errorf("save order %s: %w", j.ID, err)
		}

		if j.Food != nil {
			_, _ = tx.Exec("DELETE FROM order_items WHERE order_id = $1;", j.ID)
			for _, itm := range j.Food.Items {
				addonJSON, _ := json.Marshal(itm.Addons)
				unitPrice := float64(itm.LineTotalCentavos) / float64(itm.Quantity) / 100.0
				sub := float64(itm.LineTotalCentavos) / 100.0
				_, _ = tx.Exec(`
					INSERT INTO order_items (order_id, item_name, unit_price_centavos, unit_price, quantity, subtotal_centavos, subtotal, selected_options_json, special_instructions)
					VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9);
				`, j.ID, itm.Name, itm.LineTotalCentavos/itm.Quantity, unitPrice, itm.Quantity, itm.LineTotalCentavos, sub, addonJSON, nullStr(itm.Note))
			}
		}

		_, _ = tx.Exec("DELETE FROM order_status_history WHERE order_id = $1;", j.ID)
		for _, tl := range j.Timeline {
			_, _ = tx.Exec(`
				INSERT INTO order_status_history (order_id, to_status, created_at)
				VALUES ($1, $2, $3);
			`, j.ID, tl.Status, tl.At.Time)
		}
	}

	// 7. Wallet Transactions
	for _, txItem := range st.Txs {
		amt := float64(txItem.AmountCentavos) / 100.0
		balAfter := float64(txItem.BalanceAfterCentavos) / 100.0
		if _, err := tx.Exec(`
			INSERT INTO wallets (owner_type, owner_id, balance_centavos, balance, currency, updated_at)
			VALUES ('rider', $1, $2, $3, 'PHP', NOW())
			ON CONFLICT (owner_type, owner_id) DO UPDATE SET
				balance_centavos = EXCLUDED.balance_centavos,
				balance = EXCLUDED.balance,
				updated_at = NOW();
		`, txItem.UserID, txItem.BalanceAfterCentavos, balAfter); err == nil {
			var wID string
			_ = tx.QueryRow("SELECT id FROM wallets WHERE owner_type = 'rider' AND owner_id = $1", txItem.UserID).Scan(&wID)
			if wID != "" {
				_, _ = tx.Exec(`
					INSERT INTO wallet_transactions (id, wallet_id, user_id, order_id, transaction_type, amount_centavos, amount, balance_after_centavos, balance_after, description, created_at)
					VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
					ON CONFLICT (id) DO NOTHING;
				`, txItem.ID, wID, txItem.UserID, nullStr(txItem.JobID), txItem.Type, txItem.AmountCentavos, amt, txItem.BalanceAfterCentavos, balAfter, nullStr(txItem.Note), txItem.CreatedAt.Time)
			}
		}
	}

	// 8. Chat Messages
	for _, msgs := range st.Chats {
		for _, cm := range msgs {
			_, _ = tx.Exec(`
				INSERT INTO chat_messages (id, order_id, sender, text, image_url, created_at)
				VALUES ($1, $2, $3, $4, $5, $6)
				ON CONFLICT (id) DO NOTHING;
			`, cm.ID, cm.JobID, cm.Sender, nullStr(cm.Text), nullStr(cm.ImageURL), cm.CreatedAt.Time)
		}
	}

	// 9. Payouts
	for _, p := range st.Payouts {
		from, _ := time.Parse("2006-01-02", p.PeriodFrom)
		to, _ := time.Parse("2006-01-02", p.PeriodTo)
		_, _ = tx.Exec(`
			INSERT INTO merchant_payouts (id, merchant_id, period_from, period_to, amount_centavos, type, status, paid_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, paid_at = EXCLUDED.paid_at;
		`, p.ID, p.MerchantID, from, to, p.AmountCentavos, p.Type, p.Status, nullUTC(p.PaidAt))
	}

	// 10. Topups
	for _, tp := range st.Topups {
		_, _ = tx.Exec(`
			INSERT INTO topups (id, user_id, amount_centavos, method, status)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status;
		`, tp.ID, tp.UserID, tp.AmountCentavos, tp.Method, tp.Status)
	}

	// 11. Ratings
	for _, r := range st.Ratings {
		var cID, mID, rID sql.NullString
		_ = tx.QueryRow("SELECT customer_id, merchant_id, rider_id FROM orders WHERE id = $1", r.JobID).Scan(&cID, &mID, &rID)
		if cID.Valid {
			_, _ = tx.Exec(`
				INSERT INTO reviews (order_id, customer_id, merchant_id, rider_id, rider_rating, rider_tags, rider_comment, merchant_rating)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
				ON CONFLICT (order_id) DO NOTHING;
			`, r.JobID, cID.String, mID, rID, r.RiderRating, pq.Array(r.RiderTags), nullStr(r.Comment), nullInt(r.MerchantRating))
		}
	}

	// 12. SOS Alerts
	_, _ = tx.Exec("DELETE FROM sos_alerts;")
	for _, a := range st.SOS {
		_, _ = tx.Exec(`
			INSERT INTO sos_alerts (order_id, user_id, latitude, longitude, created_at)
			VALUES ($1, $2, $3, $4, $5);
		`, a.JobID, a.UserID, a.Location.Lat, a.Location.Lng, a.At.Time)
	}

	// 13. System Records
	_, _ = tx.Exec("DELETE FROM refresh_tokens;")
	for tHash, r := range st.Refresh {
		if time.Now().After(r.Expires) {
			continue
		}
		_, _ = tx.Exec(`
			INSERT INTO refresh_tokens (token_hash, user_id, app, expires_at)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (token_hash) DO NOTHING;
		`, tHash, r.UserID, r.App, r.Expires)
	}

	for _, d := range st.Devices {
		_, _ = tx.Exec(`
			INSERT INTO device_tokens (user_id, token, platform, app)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (user_id, token, app) DO NOTHING;
		`, d.UserID, d.Token, d.Platform, d.App)
	}

	for k, purp := range st.Uploads {
		_, _ = tx.Exec(`
			INSERT INTO upload_records (key, purpose)
			VALUES ($1, $2)
			ON CONFLICT (key) DO NOTHING;
		`, k, purp)
	}

	for k, val := range st.Idempotency {
		_, _ = tx.Exec(`
			INSERT INTO idempotency_keys (key, response_payload)
			VALUES ($1, $2)
			ON CONFLICT (key) DO NOTHING;
		`, k, val)
	}

	return tx.Commit()
}
