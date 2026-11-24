CREATE TABLE Patients (patient_id SERIAL PRIMARY KEY, full_name VARCHAR(150));
CREATE TABLE Doctors (doctor_id SERIAL PRIMARY KEY, full_name VARCHAR(150));
CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY, patient_id INT REFERENCES Patients(patient_id), doctor_id INT REFERENCES Doctors(doctor_id),
    appointment_day DATE, slot_time TIME CHECK (slot_time IN ('09:00', '10:00', '11:00', '12:00')), status VARCHAR(20) DEFAULT 'BOOKED' CHECK (status IN ('BOOKED', 'ATTENDED', 'CANCELLED'))
);
CREATE TABLE clinic_summary (summary_date DATE PRIMARY KEY, booked_count INT DEFAULT 0, attended_count INT DEFAULT 0, cancelled_count INT DEFAULT 0);

INSERT INTO Patients (full_name) VALUES ('P1'), ('P2'), ('P3');
INSERT INTO Doctors (full_name) VALUES ('Dr. A'), ('Dr. B'), ('Dr. C');
INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES 
(1, 1, CURRENT_DATE, '09:00', 'BOOKED'), (2, 1, CURRENT_DATE, '10:00', 'BOOKED'),
(3, 2, CURRENT_DATE, '11:00', 'ATTENDED'), (1, 3, CURRENT_DATE, '12:00', 'CANCELLED');

CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id INT, p_day DATE) RETURNS INT AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Doctors WHERE doctor_id = p_doctor_id) THEN RAISE EXCEPTION 'Doctor not found'; END IF;
    RETURN (SELECT COUNT(*) FROM appointments WHERE doctor_id = p_doctor_id AND appointment_day = p_day AND status != 'CANCELLED');
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_book_appointment(p_patient_id INT, p_doctor_id INT, p_day DATE, p_slot TIME) LANGUAGE plpgsql AS $$
BEGIN
    IF p_day < CURRENT_DATE THEN RAISE EXCEPTION 'Cannot book past date'; END IF;
    IF p_slot NOT IN ('09:00', '10:00', '11:00', '12:00') THEN RAISE EXCEPTION 'Invalid slot'; END IF;
    INSERT INTO appointments (patient_id, doctor_id, appointment_day, slot_time, status) VALUES (p_patient_id, p_doctor_id, p_day, p_slot, 'BOOKED');
END; $$;

CREATE OR REPLACE FUNCTION fn_check_clash() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status != 'CANCELLED' AND EXISTS (
        SELECT 1 FROM appointments WHERE doctor_id = NEW.doctor_id AND appointment_day = NEW.appointment_day AND slot_time = NEW.slot_time AND status != 'CANCELLED' AND appointment_id != COALESCE(NEW.appointment_id, -1)
    ) THEN RAISE EXCEPTION 'Slot already booked'; END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_clash BEFORE INSERT OR UPDATE ON appointments FOR EACH ROW EXECUTE FUNCTION fn_check_clash();

CREATE OR REPLACE VIEW v_today_appointments AS
SELECT p.full_name AS patient, d.full_name AS doctor, a.slot_time
FROM appointments a JOIN Patients p ON a.patient_id = p.patient_id JOIN Doctors d ON a.doctor_id = d.doctor_id
WHERE a.appointment_day = CURRENT_DATE AND a.status = 'BOOKED';

CREATE INDEX idx_app_day_doctor ON appointments(appointment_day, doctor_id);

CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO clinic_summary (summary_date, booked_count, attended_count, cancelled_count)
    SELECT p_day, COUNT(*) FILTER (WHERE status = 'BOOKED'), COUNT(*) FILTER (WHERE status = 'ATTENDED'), COUNT(*) FILTER (WHERE status = 'CANCELLED')
    FROM appointments WHERE appointment_day = p_day
    ON CONFLICT (summary_date) DO UPDATE SET booked_count = EXCLUDED.booked_count, attended_count = EXCLUDED.attended_count, cancelled_count = EXCLUDED.cancelled_count;
END; $$;