CREATE TABLE Students (student_id SERIAL PRIMARY KEY, student_number VARCHAR(20) UNIQUE, full_name VARCHAR(150));
CREATE TABLE Rooms (room_id SERIAL PRIMARY KEY, room_number VARCHAR(10) UNIQUE, capacity INT CHECK (capacity > 0));
CREATE TABLE Allocations (
    allocation_id SERIAL PRIMARY KEY, student_id INT REFERENCES Students(student_id), room_id INT REFERENCES Rooms(room_id),
    allocated_on DATE, released_on DATE NULL, status VARCHAR(10) CHECK (status IN ('ACTIVE', 'ENDED')),
    CHECK ((status = 'ACTIVE' AND released_on IS NULL) OR (status = 'ENDED' AND released_on IS NOT NULL))
);
CREATE TABLE occupancy_snapshot (snapshot_date DATE, room_id INT REFERENCES Rooms(room_id), occupied_beds INT, free_beds INT, PRIMARY KEY (snapshot_date, room_id));

INSERT INTO Students (student_number, full_name) VALUES ('S1', 'A'), ('S2', 'B'), ('S3', 'C');
INSERT INTO Rooms (room_number, capacity) VALUES ('R1', 2), ('R2', 3), ('R3', 1);
INSERT INTO Allocations (student_id, room_id, allocated_on, status) VALUES 
(1, 1, CURRENT_DATE, 'ACTIVE'), (2, 1, CURRENT_DATE, 'ACTIVE'), (3, 2, CURRENT_DATE, 'ACTIVE');

CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INT) RETURNS INT AS $$
DECLARE v_cap INT;
BEGIN
    SELECT capacity INTO v_cap FROM Rooms WHERE room_id = p_room_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Room not found'; END IF;
    RETURN v_cap - (SELECT COUNT(*) FROM Allocations WHERE room_id = p_room_id AND status = 'ACTIVE');
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INT, p_room_id INT, p_allocated_on DATE) LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM Allocations WHERE student_id = p_student_id AND status = 'ACTIVE') THEN RAISE EXCEPTION 'Student already has active allocation'; END IF;
    IF fn_free_beds(p_room_id) <= 0 THEN RAISE EXCEPTION 'Room full'; END IF;
    INSERT INTO Allocations (student_id, room_id, allocated_on, status) VALUES (p_student_id, p_room_id, p_allocated_on, 'ACTIVE');
END; $$;

CREATE OR REPLACE FUNCTION fn_check_allocation() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'ACTIVE' THEN
        IF EXISTS (SELECT 1 FROM Allocations WHERE student_id = NEW.student_id AND status = 'ACTIVE' AND allocation_id != COALESCE(NEW.allocation_id, -1)) THEN RAISE EXCEPTION 'Student already active'; END IF;
        IF (SELECT COUNT(*) FROM Allocations WHERE room_id = NEW.room_id AND status = 'ACTIVE' AND allocation_id != COALESCE(NEW.allocation_id, -1)) >= (SELECT capacity FROM Rooms WHERE room_id = NEW.room_id) THEN RAISE EXCEPTION 'Room full'; END IF;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_check_alloc BEFORE INSERT OR UPDATE ON Allocations FOR EACH ROW EXECUTE FUNCTION fn_check_allocation();

CREATE OR REPLACE VIEW v_room_occupancy AS
SELECT r.room_number, r.capacity, COUNT(a.allocation_id) FILTER (WHERE a.status = 'ACTIVE') AS occupied, r.capacity - COUNT(a.allocation_id) FILTER (WHERE a.status = 'ACTIVE') AS free
FROM Rooms r LEFT JOIN Allocations a ON r.room_id = a.room_id
GROUP BY r.room_id, r.room_number, r.capacity;

CREATE INDEX idx_alloc_room_active ON Allocations(room_id) WHERE status = 'ACTIVE';

CREATE OR REPLACE PROCEDURE pr_refresh_occupancy() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO occupancy_snapshot (snapshot_date, room_id, occupied_beds, free_beds)
    SELECT CURRENT_DATE, room_id, COUNT(*) FILTER (WHERE status = 'ACTIVE'), capacity - COUNT(*) FILTER (WHERE status = 'ACTIVE')
    FROM Rooms LEFT JOIN Allocations USING (room_id) GROUP BY room_id, capacity
    ON CONFLICT (snapshot_date, room_id) DO UPDATE SET occupied_beds = EXCLUDED.occupied_beds, free_beds = EXCLUDED.free_beds;
END; $$;