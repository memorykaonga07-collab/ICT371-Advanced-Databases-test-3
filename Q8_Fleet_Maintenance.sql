CREATE TABLE vehicles (
    vehicle_id SERIAL PRIMARY KEY, registration VARCHAR(20) UNIQUE, current_odometer NUMERIC(10,2) CHECK (current_odometer >= 0), last_service_odometer NUMERIC(10,2) CHECK (last_service_odometer >= 0),
    CHECK (last_service_odometer <= current_odometer)
);
CREATE TABLE trips (trip_id SERIAL PRIMARY KEY, vehicle_id INT REFERENCES vehicles(vehicle_id), trip_on DATE, start_odometer NUMERIC(10,2), end_odometer NUMERIC(10,2));
CREATE TABLE service_alerts (vehicle_id INT PRIMARY KEY REFERENCES vehicles(vehicle_id), km_since_service NUMERIC(10,2), flagged_on DATE);

INSERT INTO vehicles (registration, current_odometer, last_service_odometer) VALUES 
('ABC', 10000, 4000), ('DEF', 5000, 4000), ('GHI', 2000, 1000);

CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INT) RETURNS BOOLEAN AS $$
DECLARE v_diff NUMERIC;
BEGIN
    SELECT current_odometer - last_service_odometer INTO v_diff FROM vehicles WHERE vehicle_id = p_vehicle_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vehicle not found'; END IF;
    RETURN v_diff >= 5000;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INT, p_trip_on DATE, p_start NUMERIC, p_end NUMERIC) LANGUAGE plpgsql AS $$
BEGIN
    IF p_end <= p_start THEN RAISE EXCEPTION 'End <= start'; END IF;
    INSERT INTO trips (vehicle_id, trip_on, start_odometer, end_odometer) VALUES (p_vehicle_id, p_trip_on, p_start, p_end);
END; $$;

CREATE OR REPLACE FUNCTION fn_trip_trigger() RETURNS TRIGGER AS $$
DECLARE v_current NUMERIC;
BEGIN
    SELECT current_odometer INTO v_current FROM vehicles WHERE vehicle_id = NEW.vehicle_id FOR UPDATE;
    IF NEW.start_odometer != v_current THEN RAISE EXCEPTION 'Start odometer mismatch'; END IF;
    IF NEW.end_odometer <= NEW.start_odometer THEN RAISE EXCEPTION 'End <= start'; END IF;
    UPDATE vehicles SET current_odometer = NEW.end_odometer WHERE vehicle_id = NEW.vehicle_id;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_trip BEFORE INSERT ON trips FOR EACH ROW EXECUTE FUNCTION fn_trip_trigger();

CREATE OR REPLACE VIEW v_service_due AS
SELECT registration, current_odometer - last_service_odometer AS km_since_service FROM vehicles WHERE current_odometer - last_service_odometer >= 5000;

CREATE INDEX idx_trips_vehicle_date ON trips(vehicle_id, trip_on);

CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts() LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM service_alerts WHERE vehicle_id NOT IN (SELECT vehicle_id FROM vehicles WHERE current_odometer - last_service_odometer >= 5000);
    INSERT INTO service_alerts (vehicle_id, km_since_service, flagged_on)
    SELECT vehicle_id, current_odometer - last_service_odometer, CURRENT_DATE FROM vehicles WHERE current_odometer - last_service_odometer >= 5000
    ON CONFLICT (vehicle_id) DO UPDATE SET km_since_service = EXCLUDED.km_since_service, flagged_on = EXCLUDED.flagged_on;
END; $$;