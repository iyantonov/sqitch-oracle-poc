-- Deploy seed_test_data
-- requires: seed_reference_data, customers, accounts, payments_pkg
-- ◆ DEEP CHAIN: 6 уровней глубины в DAG
-- seed_test_data → payments_pkg → transactions → accounts → customers → appschema
--
-- Этот скрипт демонстрирует что Sqitch корректно разрешает
-- ВСЮ цепочку зависимостей автоматически

set serveroutput on size 1000000
set arraysize 2

DECLARE
    v_cust1_id   NUMBER;
    v_cust2_id   NUMBER;
    v_cust3_id   NUMBER;
    v_acct1_id   NUMBER;
    v_acct2_id   NUMBER;
    v_acct3_id   NUMBER;
    v_acct4_id   NUMBER;
    v_result     payment_app.payments_pkg.t_payment_result;
    v_acct_type  NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Создание тестовых данных ===');

    -- ═══ Клиенты ═══
    INSERT INTO payment_app.customers (customer_type, first_name, last_name, tax_id, phone, email)
    VALUES ('P', 'Иван', 'Петров', '770101234567', '+79161234567', 'petrov@test.com')
    RETURNING customer_id INTO v_cust1_id;

    INSERT INTO payment_app.customers (customer_type, first_name, last_name, tax_id, phone, email)
    VALUES ('P', 'Мария', 'Сидорова', '770201234568', '+79169876543', 'sidorova@test.com')
    RETURNING customer_id INTO v_cust2_id;

    INSERT INTO payment_app.customers (customer_type, company_name, tax_id, phone, email)
    VALUES ('L', 'ООО "Технологии будущего"', '7701234567', '+74951234567', 'info@techfuture.ru')
    RETURNING customer_id INTO v_cust3_id;

    DBMS_OUTPUT.PUT_LINE('Клиенты: ' || v_cust1_id || ', ' || v_cust2_id || ', ' || v_cust3_id);

    -- ═══ Счета ═══
    -- Расчётный счёт Петрова (RUB)
    SELECT acct_type_id INTO v_acct_type FROM payment_app.account_types WHERE type_code = 'CURRENT';

    INSERT INTO payment_app.accounts (customer_id, acct_type_id, currency_code, balance, hold_amount)
    VALUES (v_cust1_id, v_acct_type, 'RUB', 0, 0)
    RETURNING account_id INTO v_acct1_id;

    -- Депозитный счёт Петрова (RUB)
    SELECT acct_type_id INTO v_acct_type FROM payment_app.account_types WHERE type_code = 'DEPOSIT';

    INSERT INTO payment_app.accounts (customer_id, acct_type_id, currency_code, balance, hold_amount)
    VALUES (v_cust1_id, v_acct_type, 'RUB', 0, 0)
    RETURNING account_id INTO v_acct2_id;

    -- Расчётный счёт Сидоровой (RUB)
    SELECT acct_type_id INTO v_acct_type FROM payment_app.account_types WHERE type_code = 'CURRENT';

    INSERT INTO payment_app.accounts (customer_id, acct_type_id, currency_code, balance, hold_amount)
    VALUES (v_cust2_id, v_acct_type, 'RUB', 0, 0)
    RETURNING account_id INTO v_acct3_id;

    -- Расчётный счёт ООО (USD)
    INSERT INTO payment_app.accounts (customer_id, acct_type_id, currency_code, balance, hold_amount)
    VALUES (v_cust3_id, v_acct_type, 'USD', 0, 0)
    RETURNING account_id INTO v_acct4_id;

    DBMS_OUTPUT.PUT_LINE('Счета: ' || v_acct1_id || ', ' || v_acct2_id
        || ', ' || v_acct3_id || ', ' || v_acct4_id);

    COMMIT;

    -- ═══ Операции через payments_pkg (доказывает что пакет работает!) ═══

    -- Пополнение счёта Петрова
    payment_app.payments_pkg.deposit(v_acct1_id, 500000, 'Зарплата за январь', v_result);
    DBMS_OUTPUT.PUT_LINE('Пополнение Петров: ' || v_result.status || ' TXN=' || v_result.txn_ref);

    -- Пополнение депозита Петрова
    payment_app.payments_pkg.deposit(v_acct2_id, 1000000, 'Открытие депозита', v_result);
    DBMS_OUTPUT.PUT_LINE('Депозит Петров: ' || v_result.status);

    -- Пополнение счёта Сидоровой
    payment_app.payments_pkg.deposit(v_acct3_id, 300000, 'Зарплата за январь', v_result);
    DBMS_OUTPUT.PUT_LINE('Пополнение Сидорова: ' || v_result.status);

    -- Пополнение валютного счёта
    payment_app.payments_pkg.deposit(v_acct4_id, 50000, 'Валютная выручка', v_result);
    DBMS_OUTPUT.PUT_LINE('Пополнение ООО (USD): ' || v_result.status);

    -- Перевод Петров → Сидорова
    payment_app.payments_pkg.transfer(v_acct1_id, v_acct3_id, 75000, 'Возврат долга', v_result);
    DBMS_OUTPUT.PUT_LINE('Перевод Петров→Сидорова: ' || v_result.status);

    -- Списание со счёта Сидоровой
    payment_app.payments_pkg.withdraw(v_acct3_id, 25000, 'Оплата ЖКХ', v_result);
    DBMS_OUTPUT.PUT_LINE('Списание Сидорова: ' || v_result.status);

    -- ═══ Курсы валют (для daily_processing) ═══
    INSERT INTO payment_app.exchange_rates (from_currency, to_currency, rate, rate_date)
    VALUES ('USD', 'RUB', 89.5000, TRUNC(SYSDATE));

    INSERT INTO payment_app.exchange_rates (from_currency, to_currency, rate, rate_date)
    VALUES ('EUR', 'RUB', 97.3500, TRUNC(SYSDATE));

    INSERT INTO payment_app.exchange_rates (from_currency, to_currency, rate, rate_date)
    VALUES ('CNY', 'RUB', 12.4200, TRUNC(SYSDATE));

    INSERT INTO payment_app.exchange_rates (from_currency, to_currency, rate, rate_date)
    VALUES ('GBP', 'RUB', 113.2000, TRUNC(SYSDATE));

    COMMIT;

    -- ═══ Итоги ═══
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('=== Тестовые данные созданы ===');
    FOR rec IN (
        SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM payment_app.customers
        UNION ALL SELECT 'accounts', COUNT(*) FROM payment_app.accounts
        UNION ALL SELECT 'transactions', COUNT(*) FROM payment_app.transactions
        UNION ALL SELECT 'exchange_rates', COUNT(*) FROM payment_app.exchange_rates
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || RPAD(rec.tbl, 20) || ': ' || rec.cnt);
    END LOOP;
END;
/
