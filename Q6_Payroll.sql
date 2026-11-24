CREATE TABLE employees (employee_id SERIAL PRIMARY KEY, full_name VARCHAR(150), basic_salary NUMERIC(12,2) CHECK (basic_salary >= 0), allowance NUMERIC(12,2) CHECK (allowance >= 0), deduction NUMERIC(12,2) CHECK (deduction >= 0), active BOOLEAN DEFAULT TRUE);
CREATE TABLE payroll (payroll_id SERIAL PRIMARY KEY, employee_id INT REFERENCES employees(employee_id), pay_month DATE, gross_pay NUMERIC(12,2), net_pay NUMERIC(12,2), UNIQUE(employee_id, pay_month));
CREATE TABLE salary_audit (audit_id SERIAL PRIMARY KEY, employee_id INT REFERENCES employees(employee_id), old_salary NUMERIC(12,2), new_salary NUMERIC(12,2), changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

INSERT INTO employees (full_name, basic_salary, allowance, deduction, active) VALUES 
('Emp A', 5000, 500, 200, TRUE), ('Emp B', 6000, 600, 300, TRUE), ('Emp C', 4000, 400, 100, FALSE);

CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INT) RETURNS NUMERIC AS $$
DECLARE v_net NUMERIC;
BEGIN
    SELECT basic_salary + allowance - deduction INTO v_net FROM employees WHERE employee_id = p_employee_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Employee not found'; END IF;
    IF v_net < 0 THEN RAISE EXCEPTION 'Negative net pay'; END IF;
    RETURN v_net;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE) LANGUAGE plpgsql AS $$
DECLARE r RECORD; v_net NUMERIC;
BEGIN
    IF EXTRACT(DAY FROM p_month) != 1 THEN RAISE EXCEPTION 'Must be first of month'; END IF;
    FOR r IN SELECT * FROM employees WHERE active = TRUE LOOP
        v_net := fn_net_pay(r.employee_id);
        INSERT INTO payroll (employee_id, pay_month, gross_pay, net_pay) VALUES (r.employee_id, p_month, r.basic_salary + r.allowance, v_net)
        ON CONFLICT (employee_id, pay_month) DO NOTHING;
    END LOOP;
END; $$;

CREATE OR REPLACE FUNCTION fn_audit_salary() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN
        INSERT INTO salary_audit (employee_id, old_salary, new_salary) VALUES (OLD.employee_id, OLD.basic_salary, NEW.basic_salary);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_audit_salary AFTER UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION fn_audit_salary();

CREATE OR REPLACE VIEW v_payroll_report AS
SELECT e.full_name, p.pay_month, p.gross_pay, p.net_pay FROM payroll p JOIN employees e ON p.employee_id = e.employee_id;

CREATE INDEX idx_payroll_month ON payroll(pay_month);