-- ICT371 PostgreSQL Scenario 3: Student Hostel Room Allocation

DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;

-- STEP 1
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_name        VARCHAR(20) NOT NULL,
    available_spaces INTEGER NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INTEGER NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(15) NOT NULL DEFAULT 'ALLOCATED'  -- ALLOCATED or COMPLETE
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0);

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_name, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % : FULL', rec.room_name;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % : ONE space left', rec.room_name;
        ELSE
            RAISE NOTICE 'Room % : several spaces (%)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    d INTEGER := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', d;
        d := d + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Room check %', n;
    END LOOP;
END $$;

-- STEP 4: allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_student VARCHAR, p_room_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_spaces INTEGER;
BEGIN
    IF p_student IS NULL OR TRIM(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE NOTICE 'Allocation REFUSED for %: room % is full', p_student, p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1 WHERE room_id = p_room_id;
    INSERT INTO allocations (student_number, room_id) VALUES (p_student, p_room_id);
    RAISE NOTICE 'Student % allocated to room %', p_student, p_room_id;
END $$;

-- STEP 5
CALL allocate_room('2024001', 1);   -- valid
CALL allocate_room('2024002', 2);   -- valid (takes the last space)
CALL allocate_room('2024003', 3);   -- room B201 is full

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- STEP 6: check_out procedure
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_room   INTEGER;
    v_status VARCHAR(15);
BEGIN
    SELECT room_id, status INTO v_room, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already checked out - no space freed', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETE' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room;
    RAISE NOTICE 'Allocation % checked out, 1 space freed', p_allocation_id;
END $$;

CALL check_out(1);   -- frees one space
CALL check_out(1);   -- does nothing

-- STEP 7: explicit cursor - full or nearly full rooms
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_name, available_spaces FROM hostel_rooms
        WHERE available_spaces <= 1 ORDER BY available_spaces;
    v_name   hostel_rooms.room_name%TYPE;
    v_spaces hostel_rooms.available_spaces%TYPE;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_name, v_spaces;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full/nearly full: room % (% spaces)', v_name, v_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- STEP 8: blank student number -> EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
