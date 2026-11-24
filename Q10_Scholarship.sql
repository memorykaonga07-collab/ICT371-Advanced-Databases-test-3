CREATE TABLE students (student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(150));
CREATE TABLE applications (
    application_id SERIAL PRIMARY KEY, student_id INT REFERENCES students(student_id), age_at_application INT CHECK (age_at_application > 0),
    monthly_income NUMERIC(10,2) CHECK (monthly_income >= 0), average_mark NUMERIC(5,2) CHECK (average_mark >= 0 AND average_mark <= 100),
    submitted_on DATE, status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED'))
);
CREATE TABLE decision_audit (audit_id SERIAL PRIMARY KEY, application_id INT REFERENCES applications(application_id), old_status VARCHAR(20), new_status VARCHAR(20), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

INSERT INTO students (student_number, full_name) VALUES ('S1', 'S1'), ('S2', 'S2'), ('S3', 'S3');
INSERT INTO applications (student_id, age_at_application, monthly_income, average_mark, submitted_on, status) VALUES 
(1, 20, 2500, 80, CURRENT_DATE, 'PENDING'), (2, 30, 2500, 80, CURRENT_DATE, 'PENDING'), (3, 22, 3500, 85, CURRENT_DATE, 'PENDING');

CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INT, p_income NUMERIC, p_mark NUMERIC) RETURNS BOOLEAN AS $$
BEGIN
    IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN RAISE EXCEPTION 'Null input'; END IF;
    IF p_age < 0 OR p_income < 0 OR p_mark < 0 OR p_mark > 100 THEN RAISE EXCEPTION 'Invalid input values'; END IF;
    RETURN (p_age BETWEEN 18 AND 25) AND (p_income <= 3000) AND (p_mark >= 70);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INT) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR; v_age INT; v_income NUMERIC; v_mark NUMERIC; v_eligible BOOLEAN;
BEGIN
    SELECT status, age_at_application, monthly_income, average_mark INTO v_status, v_age, v_income, v_mark FROM applications WHERE application_id = p_application_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Application not found'; END IF;
    IF v_status != 'PENDING' THEN RAISE EXCEPTION 'Application already assessed'; END IF;
    v_eligible := fn_scholarship_eligible(v_age, v_income, v_mark);
    UPDATE applications SET status = CASE WHEN v_eligible THEN 'APPROVED' ELSE 'REJECTED' END WHERE application_id = p_application_id;
END; $$;

CREATE OR REPLACE FUNCTION fn_audit_decision() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO decision_audit (application_id, old_status, new_status) VALUES (OLD.application_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_decision AFTER UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION fn_audit_decision();

CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number, s.full_name, a.average_mark, a.status
FROM applications a JOIN students s ON a.student_id = s.student_id
WHERE a.status = 'APPROVED';

CREATE INDEX idx_app_status_date ON applications(status, submitted_on);

CREATE OR REPLACE PROCEDURE pr_assess_pending() LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT application_id FROM applications WHERE status = 'PENDING' LOOP
        CALL pr_assess_application(r.application_id);
    END LOOP;
END; $$;