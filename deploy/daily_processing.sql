-- Deploy daily_processing
-- requires: payments_pkg, exchange_rates
-- ◆ CROSS-BRANCH: объединяет ветку payments_pkg и ветку exchange_rates
-- Показывает как Sqitch DAG разрешает зависимости между несвязанными ветками

set serveroutput on size 1000000

CREATE OR REPLACE PACKAGE payment_app.daily_processing AS
    /*
    || Пакет ежедневной обработки
    ||
    || Зависимости в DAG:
    ||   daily_processing
    ||     ├── payments_pkg  (ветка: appschema → transactions → payments_pkg)
    ||     └── exchange_rates (ветка: appschema → currencies → exchange_rates)
    ||
    || Без DAG эти две ветки были бы независимы.
    || CROSS-BRANCH зависимость показывает, что daily_processing
    || не может работать без ОБЕИХ веток.
    */

    -- Пересчёт рублёвых эквивалентов валютных счетов
    PROCEDURE recalc_rub_equivalents(
        p_rate_date IN DATE DEFAULT TRUNC(SYSDATE),
        p_updated   OUT NUMBER
    );

    -- Начисление процентов на депозитные счета
    PROCEDURE accrue_interest(
        p_accrual_date IN DATE DEFAULT TRUNC(SYSDATE),
        p_processed    OUT NUMBER
    );

    -- Полный цикл ежедневной обработки
    PROCEDURE run_daily_batch(
        p_batch_date IN DATE DEFAULT TRUNC(SYSDATE)
    );

END daily_processing;
/

show errors package payment_app.daily_processing

CREATE OR REPLACE PACKAGE BODY payment_app.daily_processing AS

    -- ─── RECALC RUB EQUIVALENTS ─────────────────────────────────────────
    PROCEDURE recalc_rub_equivalents(
        p_rate_date IN DATE DEFAULT TRUNC(SYSDATE),
        p_updated   OUT NUMBER
    ) IS
        -- Oracle 11g: explicit cursor с параметром
        CURSOR c_foreign_accounts IS
            SELECT a.account_id,
                   a.currency_code,
                   a.balance,
                   (SELECT er.rate
                      FROM payment_app.exchange_rates er
                     WHERE er.from_currency = a.currency_code
                       AND er.to_currency = 'RUB'
                       AND er.rate_date = (
                           SELECT MAX(er2.rate_date)
                             FROM payment_app.exchange_rates er2
                            WHERE er2.from_currency = a.currency_code
                              AND er2.to_currency = 'RUB'
                              AND er2.rate_date <= p_rate_date
                       )
                       AND ROWNUM = 1
                   ) AS rub_rate
              FROM payment_app.accounts a
             WHERE a.currency_code != 'RUB'
               AND a.status = 'ACTIVE';

        v_count NUMBER := 0;
    BEGIN
        FOR rec IN c_foreign_accounts LOOP
            IF rec.rub_rate IS NOT NULL THEN
                -- Обновляем метаданные (в реальной системе — отдельная таблица)
                UPDATE payment_app.app_metadata
                   SET param_value = TO_CHAR(rec.balance * rec.rub_rate, '999999999999.99'),
                       updated_at = SYSDATE
                 WHERE param_name = 'RUB_EQUIV_' || rec.account_id;

                IF SQL%ROWCOUNT = 0 THEN
                    INSERT INTO payment_app.app_metadata (param_name, param_value)
                    VALUES ('RUB_EQUIV_' || rec.account_id,
                            TO_CHAR(rec.balance * rec.rub_rate, '999999999999.99'));
                END IF;

                v_count := v_count + 1;
            END IF;
        END LOOP;

        p_updated := v_count;
        COMMIT;

        DBMS_OUTPUT.PUT_LINE('Пересчитано рублёвых эквивалентов: ' || v_count);
    END recalc_rub_equivalents;

    -- ─── ACCRUE INTEREST ────────────────────────────────────────────────
    PROCEDURE accrue_interest(
        p_accrual_date IN DATE DEFAULT TRUNC(SYSDATE),
        p_processed    OUT NUMBER
    ) IS
        v_result payment_app.payments_pkg.t_payment_result;
        v_count  NUMBER := 0;
        v_rate   NUMBER(8,4) := 0.001; -- ~10% годовых / 365 дней
    BEGIN
        -- Начисление на депозитные счета
        FOR rec IN (
            SELECT a.account_id, a.balance
              FROM payment_app.accounts a
              JOIN payment_app.account_types at2
                ON at2.acct_type_id = a.acct_type_id
             WHERE at2.type_code = 'DEPOSIT'
               AND a.status = 'ACTIVE'
               AND a.balance > 0
        ) LOOP
            -- Используем payments_pkg.deposit для начисления процентов
            payment_app.payments_pkg.deposit(
                p_account_id  => rec.account_id,
                p_amount      => ROUND(rec.balance * v_rate, 2),
                p_description => 'Начисление % за ' || TO_CHAR(p_accrual_date, 'DD.MM.YYYY'),
                p_result      => v_result
            );

            IF v_result.status = 'COMPLETED' THEN
                v_count := v_count + 1;
            END IF;
        END LOOP;

        p_processed := v_count;
        DBMS_OUTPUT.PUT_LINE('Начислены проценты на ' || v_count || ' счетов');
    END accrue_interest;

    -- ─── FULL DAILY BATCH ───────────────────────────────────────────────
    PROCEDURE run_daily_batch(
        p_batch_date IN DATE DEFAULT TRUNC(SYSDATE)
    ) IS
        v_pending_processed NUMBER;
        v_pending_errors    NUMBER;
        v_equiv_updated     NUMBER;
        v_interest_count    NUMBER;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== Начало ежедневной обработки за '
            || TO_CHAR(p_batch_date, 'DD.MM.YYYY') || ' ===');

        -- Шаг 1: Обработка pending транзакций
        payment_app.payments_pkg.process_pending_transactions(
            p_batch_size => 5000,
            p_processed  => v_pending_processed,
            p_errors     => v_pending_errors
        );

        -- Шаг 2: Пересчёт рублёвых эквивалентов (нужны exchange_rates!)
        recalc_rub_equivalents(p_batch_date, v_equiv_updated);

        -- Шаг 3: Начисление процентов
        accrue_interest(p_batch_date, v_interest_count);

        DBMS_OUTPUT.PUT_LINE('=== Итого ===');
        DBMS_OUTPUT.PUT_LINE('Обработано pending: ' || v_pending_processed);
        DBMS_OUTPUT.PUT_LINE('Ошибок pending: ' || v_pending_errors);
        DBMS_OUTPUT.PUT_LINE('Рублёвых эквивалентов: ' || v_equiv_updated);
        DBMS_OUTPUT.PUT_LINE('Начислены %: ' || v_interest_count);
    END run_daily_batch;

END daily_processing;
/

show errors package body payment_app.daily_processing
