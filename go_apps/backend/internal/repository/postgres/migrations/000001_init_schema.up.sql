-- Migration: 000001_init_schema.up.sql
-- Description: Core Schema for Tawi-Tawi Super-App (Rides, Food, Pabili & Padala Delivery Platform)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- 1. USERS & ROLES
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_number VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255) DEFAULT '',
    role VARCHAR(30) NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'merchant_owner', 'merchant_staff', 'rider', 'admin')),
    roles TEXT[] NOT NULL DEFAULT ARRAY['customer']::TEXT[],
    full_name VARCHAR(150) NOT NULL DEFAULT '',
    language VARCHAR(10) NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'fil')),
    avatar_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- ============================================================================
-- 2. USER ADDRESSES & SAVED PLACES
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label VARCHAR(50) NOT NULL DEFAULT 'Home',
    recipient_name VARCHAR(150) DEFAULT '',
    recipient_phone VARCHAR(20) DEFAULT '',
    address_line1 TEXT NOT NULL,
    address_line2 TEXT,
    barangay VARCHAR(100),
    municipality VARCHAR(100) NOT NULL DEFAULT 'Bongao',
    province VARCHAR(100) NOT NULL DEFAULT 'Tawi-Tawi',
    latitude NUMERIC(10, 8) NOT NULL,
    longitude NUMERIC(11, 8) NOT NULL,
    delivery_notes TEXT,
    is_default BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_addresses_user_id ON user_addresses(user_id);

-- ============================================================================
-- 3. MERCHANTS & CATALOG
-- ============================================================================
CREATE TABLE IF NOT EXISTS merchants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
    name VARCHAR(150) NOT NULL,
    slug VARCHAR(180) UNIQUE,
    description TEXT,
    phone_number VARCHAR(20) NOT NULL,
    email VARCHAR(255),
    logo_url TEXT,
    banner_url TEXT,
    cover_url TEXT,
    address_line1 TEXT NOT NULL,
    barangay VARCHAR(100),
    municipality VARCHAR(100) NOT NULL DEFAULT 'Bongao',
    province VARCHAR(100) NOT NULL DEFAULT 'Tawi-Tawi',
    latitude NUMERIC(10, 8) NOT NULL,
    longitude NUMERIC(11, 8) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    is_accepting_orders BOOLEAN NOT NULL DEFAULT true,
    paused_until TIMESTAMPTZ,
    commission_rate NUMERIC(5, 4) NOT NULL DEFAULT 0.1500, -- 15% platform take rate
    avg_preparation_time_minutes INT NOT NULL DEFAULT 20,
    min_order_centavos INT NOT NULL DEFAULT 0,
    rating NUMERIC(3, 2) DEFAULT 5.00,
    rating_sum INT NOT NULL DEFAULT 0,
    rating_count INT NOT NULL DEFAULT 0,
    total_reviews INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_merchants_owner ON merchants(owner_id);
CREATE INDEX IF NOT EXISTS idx_merchants_active ON merchants(is_active, is_accepting_orders);
CREATE INDEX IF NOT EXISTS idx_merchants_location ON merchants(latitude, longitude);

CREATE TABLE IF NOT EXISTS merchant_staff (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    user_phone VARCHAR(20) NOT NULL,
    staff_name VARCHAR(150) NOT NULL DEFAULT '',
    role VARCHAR(30) NOT NULL DEFAULT 'owner',
    can_manage_menu BOOLEAN NOT NULL DEFAULT false,
    can_manage_orders BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_merchant_staff UNIQUE (merchant_id, user_phone)
);

CREATE INDEX IF NOT EXISTS idx_merchant_staff_phone ON merchant_staff(user_phone);

CREATE TABLE IF NOT EXISTS merchant_operating_hours (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    open_time TIME NOT NULL,
    close_time TIME NOT NULL,
    is_closed BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT uq_merchant_operating_day UNIQUE (merchant_id, day_of_week)
);

CREATE TABLE IF NOT EXISTS menu_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_menu_categories_merchant ON menu_categories(merchant_id);

CREATE TABLE IF NOT EXISTS menu_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES menu_categories(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    image_url TEXT,
    base_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    price_centavos INT NOT NULL DEFAULT 0,
    is_available BOOLEAN NOT NULL DEFAULT true,
    preparation_time_minutes INT DEFAULT 15,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_menu_items_merchant ON menu_items(merchant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_category ON menu_items(category_id);

CREATE TABLE IF NOT EXISTS menu_modifier_groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    menu_item_id UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    is_required BOOLEAN NOT NULL DEFAULT false,
    min_selections INT NOT NULL DEFAULT 0,
    max_selections INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS menu_modifier_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    modifier_group_id UUID NOT NULL REFERENCES menu_modifier_groups(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    price_delta NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    price_centavos INT NOT NULL DEFAULT 0,
    is_available BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 4. RIDERS & FLEET
-- ============================================================================
CREATE TABLE IF NOT EXISTS riders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    vehicle_type VARCHAR(30) NOT NULL DEFAULT 'motorcycle' CHECK (vehicle_type IN ('motorcycle', 'bicycle', 'tricycle')),
    plate_number VARCHAR(30) NOT NULL DEFAULT '',
    vehicle_model VARCHAR(100) NOT NULL DEFAULT '',
    vehicle_color VARCHAR(50) NOT NULL DEFAULT '',
    status VARCHAR(30) NOT NULL DEFAULT 'incomplete' CHECK (status IN ('incomplete', 'pending_review', 'approved', 'rejected', 'suspended', 'offline', 'online', 'busy')),
    is_online BOOLEAN NOT NULL DEFAULT false,
    rejection_reason TEXT,
    rating NUMERIC(3, 2) DEFAULT 5.00,
    rating_sum INT NOT NULL DEFAULT 0,
    rating_count INT NOT NULL DEFAULT 0,
    total_deliveries INT NOT NULL DEFAULT 0,
    balance_centavos INT NOT NULL DEFAULT 0,
    min_balance_centavos INT NOT NULL DEFAULT 5000,
    cod_credit_limit NUMERIC(12, 2) NOT NULL DEFAULT 3000.00,
    current_latitude NUMERIC(10, 8),
    current_longitude NUMERIC(11, 8),
    last_location_updated_at TIMESTAMPTZ,
    active_job_id UUID,
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_riders_status ON riders(status);
CREATE INDEX IF NOT EXISTS idx_riders_user_id ON riders(user_id);

-- ============================================================================
-- 5. KYC VERIFICATIONS & DOCUMENTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS kyc_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type VARCHAR(20) NOT NULL CHECK (target_type IN ('merchant', 'rider')),
    target_id UUID NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'under_review', 'approved', 'rejected')),
    rejection_reason TEXT,
    reviewed_by UUID REFERENCES users(id),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kyc_target ON kyc_verifications(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_kyc_status ON kyc_verifications(status);

CREATE TABLE IF NOT EXISTS kyc_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    verification_id UUID REFERENCES kyc_verifications(id) ON DELETE CASCADE,
    rider_id UUID REFERENCES riders(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    document_url TEXT NOT NULL,
    id_number VARCHAR(100),
    expiry_date DATE,
    status VARCHAR(30) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kyc_docs_verification ON kyc_documents(verification_id);
CREATE INDEX IF NOT EXISTS idx_kyc_docs_rider ON kyc_documents(rider_id);

-- ============================================================================
-- 6. ORDERS & JOBS (SUPER-APP: RIDES, FOOD, PABILI, PADALA)
-- ============================================================================
-- Altered from food-only to support Ride transportation, Food delivery, Pabili buying, and Padala logistics.
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_number VARCHAR(30) UNIQUE NOT NULL, -- Go Job Code e.g. GO-4901
    service VARCHAR(30) NOT NULL CHECK (service IN ('ride', 'food', 'pabili', 'padala')),
    customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    merchant_id UUID REFERENCES merchants(id) ON DELETE SET NULL, -- NULL for ride, pabili, padala
    rider_id UUID REFERENCES riders(id) ON DELETE SET NULL,
    rider_user_id UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Core Order / Job Status
    status VARCHAR(30) NOT NULL DEFAULT 'searching' CHECK (status IN (
        'pending_payment', 'merchant_pending', 'merchant_preparing', 'searching',
        'rider_assigned', 'arrived_pickup', 'items_purchased', 'picked_up',
        'arrived_dropoff', 'completed', 'cancelled'
    )),

    -- Pickup Stop (Passenger origin for ride, restaurant for food, store for pabili, sender for padala)
    pickup_address TEXT NOT NULL,
    pickup_latitude NUMERIC(10, 8) NOT NULL,
    pickup_longitude NUMERIC(11, 8) NOT NULL,
    pickup_contact_name VARCHAR(150),
    pickup_contact_phone VARCHAR(20),
    pickup_notes TEXT,

    -- Dropoff Stop (Passenger destination for ride, delivery location for food/pabili/padala)
    dropoff_address TEXT NOT NULL,
    dropoff_latitude NUMERIC(10, 8) NOT NULL,
    dropoff_longitude NUMERIC(11, 8) NOT NULL,
    dropoff_contact_name VARCHAR(150),
    dropoff_contact_phone VARCHAR(20),
    dropoff_notes TEXT,

    -- Transportation (Ride) Specific
    distance_meters INT NOT NULL DEFAULT 0,
    duration_seconds INT NOT NULL DEFAULT 0,
    share_token VARCHAR(100) UNIQUE,

    -- Buying (Pabili) Specific
    pabili_store_name VARCHAR(150),
    pabili_items_json JSONB NOT NULL DEFAULT '[]',
    pabili_estimated_item_total_centavos INT NOT NULL DEFAULT 0,
    pabili_receipt_url TEXT,
    pabili_item_total_centavos INT,
    pabili_items_confirmed_at TIMESTAMPTZ,

    -- Logistics (Padala) Specific
    padala_size VARCHAR(20) CHECK (padala_size IN ('small', 'medium', 'large')),
    padala_description TEXT,
    padala_recipient_name VARCHAR(150),
    padala_recipient_phone VARCHAR(20),
    padala_photo_url TEXT,

    -- Food Delivery Specific
    food_subtotal_centavos INT NOT NULL DEFAULT 0,
    food_prep_time_minutes INT,
    food_ready_at TIMESTAMPTZ,
    food_is_ready BOOLEAN NOT NULL DEFAULT false,
    merchant_accept_deadline TIMESTAMPTZ,
    merchant_order_status VARCHAR(30), -- 'new', 'preparing', 'ready', 'picked_up', 'completed', 'rejected', 'cancelled'
    merchant_reject_reason TEXT,

    -- Financial Ledger & Fare Breakdown (Centavos integer & Numeric PHP)
    subtotal_centavos INT NOT NULL DEFAULT 0,
    delivery_fee_centavos INT NOT NULL DEFAULT 0,
    service_fee_centavos INT NOT NULL DEFAULT 0,
    discount_centavos INT NOT NULL DEFAULT 0,
    total_centavos INT NOT NULL DEFAULT 0,
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    delivery_fee NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    service_fee NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    discount_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    total_amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    fare_breakdown_json JSONB NOT NULL DEFAULT '[]',
    fees_centavos INT NOT NULL DEFAULT 0,
    earnings_centavos INT NOT NULL DEFAULT 0,
    commission_centavos INT NOT NULL DEFAULT 0,

    -- Payment Details
    payment_method VARCHAR(30) NOT NULL CHECK (payment_method IN ('cash', 'cash_on_delivery', 'gcash', 'maya', 'wallet')),
    payment_status VARCHAR(30) NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
    payment_checkout_url TEXT,

    -- Proof & Cancellation
    proof_of_delivery_url TEXT,
    cancellation_reason TEXT,
    cancelled_by VARCHAR(50),
    rated BOOLEAN NOT NULL DEFAULT false,
    searching_since TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_merchant ON orders(merchant_id);
CREATE INDEX IF NOT EXISTS idx_orders_rider ON orders(rider_id);
CREATE INDEX IF NOT EXISTS idx_orders_service ON orders(service);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at DESC);

CREATE TABLE IF NOT EXISTS order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id UUID REFERENCES menu_items(id) ON DELETE SET NULL,
    item_name VARCHAR(150) NOT NULL,
    unit_price_centavos INT NOT NULL DEFAULT 0,
    unit_price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    quantity INT NOT NULL CHECK (quantity > 0),
    subtotal_centavos INT NOT NULL DEFAULT 0,
    subtotal NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    selected_options_json JSONB NOT NULL DEFAULT '[]',
    special_instructions TEXT
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

CREATE TABLE IF NOT EXISTS order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    from_status VARCHAR(30),
    to_status VARCHAR(30) NOT NULL,
    changed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON order_status_history(order_id);

-- ============================================================================
-- 7. PAYMENTS & FINANCIAL LEDGER
-- ============================================================================
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    payment_method VARCHAR(30) NOT NULL,
    provider VARCHAR(50) NOT NULL CHECK (provider IN ('manual_cod', 'paymongo', 'xendit', 'gcash', 'maya', 'wallet', 'dev_sim')),
    transaction_reference VARCHAR(100) UNIQUE,
    amount_centavos INT NOT NULL DEFAULT 0,
    amount NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(5) NOT NULL DEFAULT 'PHP',
    status VARCHAR(30) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'successful', 'failed', 'refunded')),
    raw_webhook_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_reference ON payments(transaction_reference);

CREATE TABLE IF NOT EXISTS wallets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_type VARCHAR(20) NOT NULL CHECK (owner_type IN ('rider', 'merchant', 'platform', 'user')),
    owner_id UUID NOT NULL,
    balance_centavos INT NOT NULL DEFAULT 0,
    balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(5) NOT NULL DEFAULT 'PHP',
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_wallet_owner UNIQUE (owner_type, owner_id)
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id UUID NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    transaction_type VARCHAR(50) NOT NULL,
    amount_centavos INT NOT NULL,
    amount NUMERIC(12, 2) NOT NULL,
    balance_after_centavos INT NOT NULL,
    balance_after NUMERIC(12, 2) NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_wallet ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON wallet_transactions(user_id);

CREATE TABLE IF NOT EXISTS topups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    amount_centavos INT NOT NULL,
    method VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    checkout_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS merchant_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    period_from DATE NOT NULL,
    period_to DATE NOT NULL,
    amount_centavos INT NOT NULL,
    type VARCHAR(30) NOT NULL DEFAULT 'weekly',
    status VARCHAR(30) NOT NULL DEFAULT 'pending',
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 8. REVIEWS & RATINGS
-- ============================================================================
CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID UNIQUE NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    merchant_id UUID REFERENCES merchants(id) ON DELETE SET NULL,
    rider_id UUID REFERENCES riders(id) ON DELETE SET NULL,
    rider_rating SMALLINT CHECK (rider_rating BETWEEN 1 AND 5),
    rider_tags TEXT[] DEFAULT ARRAY[]::TEXT[],
    rider_comment TEXT,
    merchant_rating SMALLINT CHECK (merchant_rating BETWEEN 1 AND 5),
    merchant_comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_reviews_merchant ON reviews(merchant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rider ON reviews(rider_id);

-- ============================================================================
-- 9. CHAT & SAFETY (JOB CHAT, SOS ALERTS)
-- ============================================================================
CREATE TABLE IF NOT EXISTS chat_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    sender VARCHAR(30) NOT NULL CHECK (sender IN ('customer', 'rider', 'system')),
    text TEXT,
    image_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_order ON chat_messages(order_id);

CREATE TABLE IF NOT EXISTS sos_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    latitude NUMERIC(10, 8) NOT NULL,
    longitude NUMERIC(11, 8) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 10. SYSTEM, SESSIONS, TOKENS & IDEMPOTENCY
-- ============================================================================
CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform VARCHAR(20) NOT NULL DEFAULT 'android',
    app VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_device_token UNIQUE (user_id, token, app)
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    token_hash VARCHAR(128) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    app VARCHAR(30) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS idempotency_keys (
    key VARCHAR(128) PRIMARY KEY,
    response_payload TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS upload_records (
    key VARCHAR(128) PRIMARY KEY,
    purpose VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
