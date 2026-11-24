CREATE TABLE customers (customer_id SERIAL PRIMARY KEY, full_name VARCHAR(150));
CREATE TABLE readings (
    reading_id SERIAL PRIMARY KEY, customer_id INT REFERENCES customers(customer_id), reading_month DATE,
    previous_reading NUMERIC(10,2) CHECK (previous_reading >= 0), current_reading NUMERIC(10,2) CHECK (current_reading >= 0),
    UNIQUE(customer_id, reading_month)
);
CREATE TABLE bills (
    bill_id SERIAL PRIMARY KEY, reading_id INT UNIQUE REFERENCES readings(reading_id), charge NUMERIC(12,2), amount_paid NUMERIC(12,2) CHECK (amount_paid >= 0), due_on DATE,
    CHECK (amount_paid <= charge)
);
CREATE TABLE receivable_snapshot (snapshot_date DATE PRIMARY KEY, total_due NUMERIC(12,2));

INSERT INTO customers (full_name) VALUES ('C1'), ('C2'), ('C3');
INSERT INTO readings (customer_id, reading_month, previous_reading, current_reading) VALUES 
(1, '2024-01-01', 0, 10), (2, '2024-01-01', 10, 25), (3, '2024-01-01', 0, 0);

CREATE OR REPLACE FUNCTION fn_water_charge(p_units NUMERIC) RETURNS NUMERIC AS $$
BEGIN
    IF p_units IS NULL OR p_units < 0 THEN RAISE EXCEPTION 'Invalid units'; END IF;
    IF p_units <= 10 THEN RETURN p_units * 5.00;
    ELSE RETURN (10 * 5.00) + ((p_units - 10) * 8.00); END IF;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id INT, p_due_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_prev NUMERIC; v_curr NUMERIC; v_charge NUMERIC;
BEGIN
    SELECT previous_reading, current_reading INTO v_prev, v_curr FROM readings WHERE reading_id = p_reading_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reading not found'; END IF;
    IF EXISTS (SELECT 1 FROM bills WHERE reading_id = p_reading_id) THEN RAISE EXCEPTION 'Bill already exists'; END IF;
    v_charge := fn_water_charge(v_curr - v_prev);
    INSERT INTO bills (reading_id, charge, amount_paid, due_on) VALUES (p_reading_id, v_charge, 0, p_due_on);
END; $$;

CREATE OR REPLACE FUNCTION fn_check_reading() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.current_reading < NEW.previous_reading THEN RAISE EXCEPTION 'Current < previous'; END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_check_reading BEFORE INSERT OR UPDATE ON readings FOR EACH ROW EXECUTE FUNCTION fn_check_reading();

CREATE OR REPLACE VIEW v_overdue_bills AS
SELECT c.full_name, b.due_on, (b.charge - b.amount_paid) AS outstanding
FROM bills b JOIN readings r ON b.reading_id = r.reading_id JOIN customers c ON r.customer_id = c.customer_id
WHERE b.due_on < CURRENT_DATE AND b.amount_paid < b.charge;

CREATE INDEX idx_bills_due_unpaid ON bills(due_on) WHERE amount_paid < charge;

CREATE OR REPLACE PROCEDURE pr_refresh_receivables() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO receivable_snapshot (snapshot_date, total_due)
    SELECT CURRENT_DATE, COALESCE(SUM(charge - amount_paid), 0) FROM bills WHERE amount_paid < charge
    ON CONFLICT (snapshot_date) DO UPDATE SET total_due = EXCLUDED.total_due;
END; $$;