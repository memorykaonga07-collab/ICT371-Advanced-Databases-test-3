CREATE TABLE medicines (
    medicine_id SERIAL PRIMARY KEY,
    medicine_name VARCHAR(150) NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
    stock_qty INTEGER NOT NULL CHECK (stock_qty >= 0)
);
CREATE TABLE sales (
    sale_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL REFERENCES medicines(medicine_id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
    sold_on DATE NOT NULL
);
CREATE TABLE stock_audit (
    audit_id SERIAL PRIMARY KEY,
    medicine_id INTEGER NOT NULL REFERENCES medicines(medicine_id),
    old_qty INTEGER NOT NULL,
    new_qty INTEGER NOT NULL,
    changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE daily_sales (
    sales_date DATE PRIMARY KEY,
    total_qty INTEGER NOT NULL DEFAULT 0,
    total_amount NUMERIC(12,2) NOT NULL DEFAULT 0
);

INSERT INTO medicines (medicine_name, unit_price, stock_qty) VALUES
('Paracetamol', 2.50, 100), ('Amoxicillin', 5.00, 50), ('Ibuprofen', 3.75, 80);

CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INTEGER, p_quantity INTEGER)
RETURNS NUMERIC AS $$
DECLARE v_price NUMERIC(12,2);
BEGIN
    IF p_quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
    SELECT unit_price INTO v_price FROM medicines WHERE medicine_id = p_medicine_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine id: %', p_medicine_id; END IF;
    RETURN v_price * p_quantity;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INTEGER, p_quantity INTEGER, p_sold_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_current_price NUMERIC(12,2); v_current_stock INTEGER;
BEGIN
    IF p_quantity <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
    SELECT unit_price, stock_qty INTO v_current_price, v_current_stock FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine id: %', p_medicine_id; END IF;
    IF v_current_stock < p_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
    INSERT INTO sales (medicine_id, quantity, unit_price, sold_on) VALUES (p_medicine_id, p_quantity, v_current_price, p_sold_on);
    UPDATE medicines SET stock_qty = v_current_stock - p_quantity WHERE medicine_id = p_medicine_id;
    INSERT INTO daily_sales (sales_date, total_qty, total_amount) VALUES (p_sold_on, p_quantity, v_current_price * p_quantity)
    ON CONFLICT (sales_date) DO UPDATE SET total_qty = daily_sales.total_qty + EXCLUDED.total_qty, total_amount = daily_sales.total_amount + EXCLUDED.total_amount;
END; $$;

CREATE OR REPLACE FUNCTION fn_audit_stock_change() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stock_qty IS DISTINCT FROM NEW.stock_qty THEN
        INSERT INTO stock_audit (medicine_id, old_qty, new_qty) VALUES (OLD.medicine_id, OLD.stock_qty, NEW.stock_qty);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_after_update_medicines AFTER UPDATE OF stock_qty ON medicines FOR EACH ROW EXECUTE FUNCTION fn_audit_stock_change();

CREATE OR REPLACE VIEW v_low_stock AS SELECT medicine_name, unit_price, stock_qty FROM medicines WHERE stock_qty < 10;
CREATE INDEX idx_sales_medicine_date ON sales (medicine_id, sold_on);

CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    WITH daily_agg AS (SELECT p_day AS sales_date, COALESCE(SUM(quantity), 0)::INTEGER AS total_qty, COALESCE(SUM(quantity * unit_price), 0)::NUMERIC(12,2) AS total_amount FROM sales WHERE sold_on = p_day)
    INSERT INTO daily_sales (sales_date, total_qty, total_amount) SELECT sales_date, total_qty, total_amount FROM daily_agg
    ON CONFLICT (sales_date) DO UPDATE SET total_qty = EXCLUDED.total_qty, total_amount = EXCLUDED.total_amount;
END; $$;