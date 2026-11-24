CREATE TABLE Students (
    student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE NOT NULL, full_name VARCHAR(150) NOT NULL, fee_due NUMERIC(12,2) NOT NULL CHECK (fee_due >= 0)
);
CREATE TABLE Payments (
    payment_id SERIAL PRIMARY KEY, student_id INTEGER NOT NULL REFERENCES Students(student_id), amount NUMERIC(12,2) NOT NULL CHECK (amount > 0), paid_on DATE NOT NULL
);
CREATE TABLE payment_audit (
    audit_id SERIAL PRIMARY KEY, payment_id INTEGER NOT NULL REFERENCES Payments(payment_id), student_id INTEGER NOT NULL REFERENCES Students(student_id), amount NUMERIC(12,2) NOT NULL, logged_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE daily_collections (
    collection_date DATE PRIMARY KEY, payment_count INTEGER NOT NULL DEFAULT 0, total_amount NUMERIC(12,2) NOT NULL DEFAULT 0
);

INSERT INTO Students (student_number, full_name, fee_due) VALUES ('S001', 'Alice', 5000.00), ('S002', 'Bob', 7500.00), ('S003', 'Charlie', 6000.00);
INSERT INTO Payments (student_id, amount, paid_on) VALUES (1, 1000.00, CURRENT_DATE), (1, 1500.00, CURRENT_DATE), (2, 2000.00, CURRENT_DATE), (2, 2500.00, CURRENT_DATE), (2, 1000.00, CURRENT_DATE - 1), (1, 500.00, CURRENT_DATE - 1);

CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INTEGER) RETURNS NUMERIC AS $$
DECLARE v_fee_due NUMERIC(12,2); v_total_paid NUMERIC(12,2);
BEGIN
    SELECT fee_due INTO v_fee_due FROM Students WHERE student_id = p_student_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student id: %', p_student_id; END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_total_paid FROM Payments WHERE student_id = p_student_id;
    RETURN v_fee_due - v_total_paid;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INTEGER, p_amount NUMERIC, p_paid_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_outstanding NUMERIC(12,2);
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Payment amount must be positive'; END IF;
    SELECT fn_fee_balance(p_student_id) INTO v_outstanding;
    IF p_amount > v_outstanding THEN RAISE EXCEPTION 'Payment exceeds balance'; END IF;
    INSERT INTO Payments (student_id, amount, paid_on) VALUES (p_student_id, p_amount, p_paid_on);
END; $$;

CREATE OR REPLACE FUNCTION fn_audit_payment() RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO payment_audit (payment_id, student_id, amount) VALUES (NEW.payment_id, NEW.student_id, NEW.amount);
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_after_insert_payments AFTER INSERT ON Payments FOR EACH ROW EXECUTE FUNCTION fn_audit_payment();

CREATE OR REPLACE VIEW v_fee_balances AS
SELECT s.student_number, s.full_name, fn_fee_balance(s.student_id) AS outstanding_balance
FROM Students s WHERE fn_fee_balance(s.student_id) > 0;

CREATE INDEX idx_payments_student_date ON payments (student_id, paid_on);

CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    WITH daily_agg AS (SELECT p_day AS collection_date, COUNT(payment_id)::INTEGER AS payment_count, COALESCE(SUM(amount), 0)::NUMERIC(12,2) AS total_amount FROM payments WHERE paid_on = p_day)
    INSERT INTO daily_collections (collection_date, payment_count, total_amount) SELECT collection_date, payment_count, total_amount FROM daily_agg
    ON CONFLICT (collection_date) DO UPDATE SET payment_count = EXCLUDED.payment_count, total_amount = EXCLUDED.total_amount;
END; $$;