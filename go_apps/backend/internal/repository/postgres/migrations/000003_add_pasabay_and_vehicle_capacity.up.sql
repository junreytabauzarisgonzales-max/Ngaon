-- Add pasabay vehicle types and capacity to riders
ALTER TABLE riders DROP CONSTRAINT IF EXISTS riders_vehicle_type_check;
ALTER TABLE riders ADD CONSTRAINT riders_vehicle_type_check CHECK (vehicle_type IN ('motorcycle', 'bicycle', 'tricycle', '4wheels', 'car'));
ALTER TABLE riders ADD COLUMN IF NOT EXISTS vehicle_capacity INT NOT NULL DEFAULT 1;

-- Add ride tier and seat tracking to orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS ride_tier VARCHAR(30) DEFAULT 'solo';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS ride_seats INT DEFAULT 1;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS ride_total_shared_seats INT DEFAULT 1;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS ride_base_fare_centavos INT DEFAULT 0;
