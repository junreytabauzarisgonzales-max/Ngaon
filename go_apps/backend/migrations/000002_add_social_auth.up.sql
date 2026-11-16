-- Migration: 000002_add_social_auth.up.sql
-- Description: Add Google and Facebook OAuth identifiers to users table

ALTER TABLE users ALTER COLUMN phone_number DROP NOT NULL;

ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255) UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS facebook_id VARCHAR(255) UNIQUE;

CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_facebook_id ON users(facebook_id);
