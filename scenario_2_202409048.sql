-- ICT371 PostgreSQL Scenario 2: Computer Laboratory Reservations

DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

-- STEP 1
CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(60) NOT NULL,
    available_workstations INTEGER NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id SERIAL PRIMARY KEY,
    session_id     INTEGER NOT NULL REFERENCES lab_sessions(session_id),
    lecturer       VARCHAR(60) NOT NULL,
    workstations   INTEGER NOT NULL,
    status         VARCHAR(15) NOT NULL DEFAULT 'RESERVED'  -- RESERVED or CANCELLED
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Databases Practical', 30),
    ('Tuesday 10:00 - Networking Practical', 4),
    ('Wednesday 14:00 - Programming Practical', 0);

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT session_name, available_workstations FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            RAISE NOTICE '% : FULL', rec.session_name;
        ELSIF rec.available_workstations <= 5 THEN
            RAISE NOTICE '% : NEARLY FULL (%)', rec.session_name, rec.available_workstations;
        ELSE
            RAISE NOTICE '% : enough workstations (%)', rec.session_name, rec.available_workstations;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', i;
        i := i + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check %', n;
    END LOOP;
END $$;

-- STEP 4: reserve_workstations procedure
CREATE OR REPLACE PROCEDURE reserve_workstations(p_session_id INTEGER, p_lecturer VARCHAR, p_qty INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: % (must be greater than zero)', p_qty;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist', p_session_id;
    END IF;

    IF v_available < p_qty THEN
        RAISE NOTICE 'Reservation REFUSED for %: requested %, only % free', p_lecturer, p_qty, v_available;
        RETURN;
    END IF;

    UPDATE lab_sessions SET available_workstations = available_workstations - p_qty
    WHERE session_id = p_session_id;
    INSERT INTO reservations (session_id, lecturer, workstations) VALUES (p_session_id, p_lecturer, p_qty);
    RAISE NOTICE 'Reservation recorded for % (% workstations)', p_lecturer, p_qty;
END $$;

-- STEP 5
CALL reserve_workstations(1, 'Dr Banda', 10);    -- valid
CALL reserve_workstations(2, 'Mr Phiri', 3);     -- valid
CALL reserve_workstations(1, 'Ms Mwila', 50);    -- exceeds capacity

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- STEP 6: cancel_reservation procedure
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_session INTEGER;
    v_qty     INTEGER;
    v_status  VARCHAR(15);
BEGIN
    SELECT session_id, workstations, status INTO v_session, v_qty, v_status
    FROM reservations WHERE reservation_id = p_reservation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled - nothing released', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session;
    RAISE NOTICE 'Reservation % cancelled, % workstations released', p_reservation_id, v_qty;
END $$;

CALL cancel_reservation(1);   -- releases workstations
CALL cancel_reservation(1);   -- does nothing

-- STEP 7: explicit cursor - sessions with few workstations left
DO $$
DECLARE
    cur_low CURSOR FOR
        SELECT session_name, available_workstations FROM lab_sessions
        WHERE available_workstations <= 5 ORDER BY available_workstations;
    v_name  lab_sessions.session_name%TYPE;
    v_free  lab_sessions.available_workstations%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_free;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left: % (%)', v_name, v_free;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: zero workstations -> EXCEPTION block
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr Banda', 0);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
