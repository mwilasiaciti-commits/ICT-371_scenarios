-- ICT371 PostgreSQL Scenario 4: Campus Clinic Medicine Dispensing

DROP TABLE IF EXISTS dispensing_records CASCADE;
DROP TABLE IF EXISTS medicines CASCADE;

-- STEP 1
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(60) NOT NULL,
    stock_quantity INTEGER NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INTEGER NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INTEGER NOT NULL,
    status         VARCHAR(15) NOT NULL DEFAULT 'DISPENSED'  -- DISPENSED or REVERSED
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg',   8),
    ('Cough Syrup',         0);

-- STEP 2: IF / ELSIF / ELSE
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 10 THEN
            RAISE NOTICE '% : LOW stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : sufficiently stocked (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- STEP 3: WHILE and numeric FOR
DO $$
DECLARE
    d INTEGER := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Stock review day %', d;
        d := d + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection %', n;
    END LOOP;
END $$;

-- STEP 4: dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INTEGER, p_student VARCHAR, p_qty INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE NOTICE 'Dispensing REFUSED for %: requested %, only % in stock', p_student, p_qty, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty WHERE medicine_id = p_medicine_id;
    INSERT INTO dispensing_records (medicine_id, student_number, quantity)
    VALUES (p_medicine_id, p_student, p_qty);
    RAISE NOTICE 'Dispensed % units to %', p_qty, p_student;
END $$;

-- STEP 5
CALL dispense_medicine(1, '2024001', 20);   -- valid
CALL dispense_medicine(2, '2024002', 3);    -- valid
CALL dispense_medicine(2, '2024003', 50);   -- exceeds stock

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- STEP 6: reverse_dispensing procedure
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_medicine INTEGER;
    v_qty      INTEGER;
    v_status   VARCHAR(15);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed - stock not restored again', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine;
    RAISE NOTICE 'Record % reversed, % units restored', p_record_id, v_qty;
END $$;

CALL reverse_dispensing(1);   -- restores stock
CALL reverse_dispensing(1);   -- does nothing

-- STEP 7: explicit cursor - medicines below a low-stock threshold
DO $$
DECLARE
    v_threshold INTEGER := 10;
    cur_low CURSOR FOR
        SELECT medicine_name, stock_quantity FROM medicines
        WHERE stock_quantity < v_threshold ORDER BY stock_quantity;
    v_name  medicines.medicine_name%TYPE;
    v_stock medicines.stock_quantity%TYPE;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold (%): % has % left', v_threshold, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- STEP 8: negative quantity -> EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, '2024004', -5);
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- STEP 9
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
