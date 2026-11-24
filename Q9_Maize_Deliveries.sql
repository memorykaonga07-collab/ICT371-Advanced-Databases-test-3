CREATE TABLE farmers (farmer_id SERIAL PRIMARY KEY, farmer_number VARCHAR(20) UNIQUE, full_name VARCHAR(150));
CREATE TABLE deliveries (
    delivery_id SERIAL PRIMARY KEY, farmer_id INT REFERENCES farmers(farmer_id), grade CHAR(1) CHECK (grade IN ('A', 'B', 'C')),
    weight_kg NUMERIC(10,2) CHECK (weight_kg > 0), unit_rate NUMERIC(10,2), total_value NUMERIC(12,2), delivered_on DATE, is_paid BOOLEAN DEFAULT FALSE
);
CREATE TABLE daily_purchases (purchase_date DATE PRIMARY KEY, total_weight NUMERIC(12,2), total_value NUMERIC(12,2));

INSERT INTO farmers (farmer_number, full_name) VALUES ('F1', 'F1'), ('F2', 'F2'), ('F3', 'F3');

CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade CHAR) RETURNS NUMERIC AS $$
BEGIN
    IF p_grade = 'A' THEN RETURN 5.00;
    ELSIF p_grade = 'B' THEN RETURN 4.00;
    ELSIF p_grade = 'C' THEN RETURN 3.00;
    ELSE RAISE EXCEPTION 'Invalid grade'; END IF;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INT, p_grade CHAR, p_weight NUMERIC, p_date DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on) VALUES (p_farmer_id, p_grade, p_weight, p_date);
END; $$;

CREATE OR REPLACE FUNCTION fn_delivery_trigger() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.weight_kg <= 0 THEN RAISE EXCEPTION 'Weight must be positive'; END IF;
    NEW.unit_rate := fn_maize_rate(NEW.grade);
    NEW.total_value := NEW.weight_kg * NEW.unit_rate;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_delivery BEFORE INSERT OR UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION fn_delivery_trigger();

CREATE OR REPLACE VIEW v_farmer_amount_due AS
SELECT f.farmer_number, f.full_name, COALESCE(SUM(d.total_value) FILTER (WHERE d.is_paid = FALSE), 0) AS unpaid_value
FROM farmers f LEFT JOIN deliveries d ON f.farmer_id = d.farmer_id GROUP BY