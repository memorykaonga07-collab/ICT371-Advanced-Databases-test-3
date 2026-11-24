CREATE TABLE Books (book_id SERIAL PRIMARY KEY, title VARCHAR(200) NOT NULL);
CREATE TABLE Loans (
    loan_id SERIAL PRIMARY KEY, book_id INTEGER REFERENCES Books(book_id), borrower_name VARCHAR(150),
    borrowed_on DATE NOT NULL, due_on DATE NOT NULL, returned_on DATE NULL, fine_amount NUMERIC(10,2) DEFAULT 0,
    CHECK (due_on >= borrowed_on)
);
CREATE TABLE loan_audit (audit_id SERIAL PRIMARY KEY, loan_id INTEGER REFERENCES Loans(loan_id), old_returned_on DATE, new_returned_on DATE, changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE overdue_summary (snapshot_date DATE PRIMARY KEY, overdue_count INTEGER, total_fine NUMERIC(12,2));

INSERT INTO Books (title) VALUES ('Book A'), ('Book B'), ('Book C');
INSERT INTO Loans (book_id, borrower_name, borrowed_on, due_on, returned_on) VALUES 
(1, 'John', CURRENT_DATE - 10, CURRENT_DATE - 5, NULL),
(2, 'Jane', CURRENT_DATE - 5, CURRENT_DATE - 2, CURRENT_DATE - 2),
(3, 'Bob', CURRENT_DATE - 20, CURRENT_DATE - 15, CURRENT_DATE - 10);

CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id INTEGER, p_as_of DATE) RETURNS NUMERIC AS $$
DECLARE v_due DATE; v_returned DATE; v_days INT;
BEGIN
    SELECT due_on, returned_on INTO v_due, v_returned FROM Loans WHERE loan_id = p_loan_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found'; END IF;
    IF v_returned IS NOT NULL AND v_returned < p_as_of THEN p_as_of := v_returned; END IF;
    v_days := GREATEST(0, p_as_of - v_due);
    RETURN v_days * 2.00;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id INTEGER, p_returned_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_borrowed DATE; v_returned DATE; v_fine NUMERIC;
BEGIN
    SELECT borrowed_on, returned_on INTO v_borrowed, v_returned FROM Loans WHERE loan_id = p_loan_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found'; END IF;
    IF v_returned IS NOT NULL THEN RAISE EXCEPTION 'Already returned'; END IF;
    IF p_returned_on < v_borrowed THEN RAISE EXCEPTION 'Return date before borrow date'; END IF;
    v_fine := fn_loan_fine(p_loan_id, p_returned_on);
    UPDATE Loans SET returned_on = p_returned_on, fine_amount = v_fine WHERE loan_id = p_loan_id;
END; $$;

CREATE OR REPLACE FUNCTION fn_audit_loan() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN
        INSERT INTO loan_audit (loan_id, old_returned_on, new_returned_on) VALUES (OLD.loan_id, OLD.returned_on, NEW.returned_on);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_loan AFTER UPDATE ON Loans FOR EACH ROW EXECUTE FUNCTION fn_audit_loan();

CREATE OR REPLACE VIEW v_overdue_loans AS
SELECT b.title, l.borrower_name, l.due_on, fn_loan_fine(l.loan_id, CURRENT_DATE) AS current_fine
FROM Loans l JOIN Books b ON l.book_id = b.book_id
WHERE l.returned_on IS NULL AND l.due_on < CURRENT_DATE;

CREATE INDEX idx_loans_book_return ON Loans(book_id, returned_on);

CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO overdue_summary (snapshot_date, overdue_count, total_fine)
    SELECT p_as_of, COUNT(*), COALESCE(SUM(fn_loan_fine(loan_id, p_as_of)), 0)
    FROM Loans WHERE returned_on IS NULL AND due_on < p_as_of
    ON CONFLICT (snapshot_date) DO UPDATE SET overdue_count = EXCLUDED.overdue_count, total_fine = EXCLUDED.total_fine;
END; $$;