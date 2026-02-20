-- Deploy payments_pkg
-- requires: transactions, accounts, customers
-- PL/SQL пакет обработки платежей
-- Демонстрирует возможности Oracle 11g PL/SQL:
--   - Package spec + body
--   - Custom TYPE (record, table)
--   - SYS_REFCURSOR
--   - PRAGMA AUTONOMOUS_TRANSACTION
--   - BULK COLLECT / FORALL
--   - Exception handling с custom exceptions
--   - DBMS_OUTPUT
--   - Sequence в PL/SQL (11g: нельзя в DEFAULT, но можно в триггере)

set serveroutput on size 1000000

-- =========================================================================
-- СПЕЦИФИКАЦИЯ ПАКЕТА
-- =========================================================================
CREATE OR REPLACE PACKAGE payment_app.payments_pkg AS
    /*
    || Пакет обработки платежей
    || Версия: 1.0
    || Особенности Oracle 11g:
    ||   - Нет IDENTITY столбцов (используем sequences)
    ||   - Нет FETCH FIRST N ROWS (используем ROWNUM)
    ||   - Нет PL/SQL in WITH clause
    ||   - RESULT_CACHE доступен
    */

    -- Пользовательские типы (Oracle 11g)
    TYPE t_payment_result IS RECORD (
        txn_id        NUMBER(18),
        txn_ref       VARCHAR2(36),
        status        VARCHAR2(20),
        error_code    VARCHAR2(50),
        error_message VARCHAR2(1000)
    );

    TYPE t_account_balance IS RECORD (
        account_id     NUMBER(20),
        account_number VARCHAR2(20),
        balance        NUMBER(18,2),
        available      NUMBER(18,2),
        currency_code  CHAR(3)
    );

    -- Табличный тип для BULK операций
    TYPE t_txn_id_tab IS TABLE OF NUMBER(18) INDEX BY PLS_INTEGER;

    -- Пользовательские исключения
    e_insufficient_funds  EXCEPTION;
    e_account_frozen      EXCEPTION;
    e_account_not_found   EXCEPTION;
    e_same_account        EXCEPTION;
    e_invalid_amount      EXCEPTION;

    PRAGMA EXCEPTION_INIT(e_insufficient_funds, -20001);
    PRAGMA EXCEPTION_INIT(e_account_frozen,     -20002);
    PRAGMA EXCEPTION_INIT(e_account_not_found,  -20003);
    PRAGMA EXCEPTION_INIT(e_same_account,       -20004);
    PRAGMA EXCEPTION_INIT(e_invalid_amount,     -20005);

    -- ─── Основные процедуры ─────────────────────────────────────────────

    -- Перевод между счетами
    PROCEDURE transfer(
        p_from_account  IN  NUMBER,
        p_to_account    IN  NUMBER,
        p_amount        IN  NUMBER,
        p_description   IN  VARCHAR2 DEFAULT NULL,
        p_result        OUT t_payment_result
    );

    -- Пополнение счёта
    PROCEDURE deposit(
        p_account_id    IN  NUMBER,
        p_amount        IN  NUMBER,
        p_description   IN  VARCHAR2 DEFAULT NULL,
        p_result        OUT t_payment_result
    );

    -- Списание со счёта
    PROCEDURE withdraw(
        p_account_id    IN  NUMBER,
        p_amount        IN  NUMBER,
        p_description   IN  VARCHAR2 DEFAULT NULL,
        p_result        OUT t_payment_result
    );

    -- ─── Вспомогательные функции ────────────────────────────────────────

    -- Получить баланс счёта
    FUNCTION get_balance(
        p_account_id IN NUMBER
    ) RETURN t_account_balance;

    -- Получить историю транзакций (SYS_REFCURSOR)
    FUNCTION get_account_history(
        p_account_id IN NUMBER,
        p_from_date  IN DATE DEFAULT SYSDATE - 30,
        p_to_date    IN DATE DEFAULT SYSDATE,
        p_max_rows   IN NUMBER DEFAULT 100
    ) RETURN SYS_REFCURSOR;

    -- Пакетная обработка PENDING транзакций (BULK COLLECT + FORALL)
    PROCEDURE process_pending_transactions(
        p_batch_size  IN  NUMBER DEFAULT 1000,
        p_processed   OUT NUMBER,
        p_errors      OUT NUMBER
    );

END payments_pkg;
/

show errors package payment_app.payments_pkg

-- =========================================================================
-- ТЕЛО ПАКЕТА
-- =========================================================================
CREATE OR REPLACE PACKAGE BODY payment_app.payments_pkg AS

    -- Внутренняя процедура логирования (AUTONOMOUS_TRANSACTION)
    PROCEDURE log_event(
        p_txn_id   IN NUMBER,
        p_event    IN VARCHAR2,
        p_details  IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        -- В production: INSERT в таблицу логов
        -- Для PoC: DBMS_OUTPUT
        DBMS_OUTPUT.PUT_LINE(
            TO_CHAR(SYSDATE, 'HH24:MI:SS') || ' [TXN=' || p_txn_id || '] '
            || p_event || ': ' || p_details
        );
        COMMIT; -- autonomous transaction требует явного commit
    END log_event;

    -- Внутренняя: проверка статуса счёта
    PROCEDURE check_account(
        p_account_id IN NUMBER,
        p_balance    OUT t_account_balance
    ) IS
    BEGIN
        SELECT account_id, account_number, balance, available, currency_code
          INTO p_balance.account_id,
               p_balance.account_number,
               p_balance.balance,
               p_balance.available,
               p_balance.currency_code
          FROM payment_app.accounts
         WHERE account_id = p_account_id
           FOR UPDATE NOWAIT;  -- Блокировка строки для предотвращения race condition

        -- Проверка что счёт найден (если не найден — NO_DATA_FOUND ниже)
        NULL;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003,
                'Счёт ' || p_account_id || ' не найден');
    END check_account;

    -- ─── TRANSFER ────────────────────────────────────────────────────────
    PROCEDURE transfer(
        p_from_account  IN  NUMBER,
        p_to_account    IN  NUMBER,
        p_amount        IN  NUMBER,
        p_description   IN  VARCHAR2 DEFAULT NULL,
        p_result        OUT t_payment_result
    ) IS
        v_from_bal   t_account_balance;
        v_to_bal     t_account_balance;
        v_txn_type   NUMBER(10);
    BEGIN
        -- Валидация
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005,
                'Сумма должна быть положительной: ' || p_amount);
        END IF;

        IF p_from_account = p_to_account THEN
            RAISE_APPLICATION_ERROR(-20004,
                'Нельзя перевести на тот же счёт');
        END IF;

        -- Блокировка счетов в порядке ID (предотвращение deadlock)
        IF p_from_account < p_to_account THEN
            check_account(p_from_account, v_from_bal);
            check_account(p_to_account, v_to_bal);
        ELSE
            check_account(p_to_account, v_to_bal);
            check_account(p_from_account, v_from_bal);
        END IF;

        -- Проверка достаточности средств
        IF v_from_bal.available < p_amount THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Недостаточно средств. Доступно: ' || v_from_bal.available
                || ', запрошено: ' || p_amount);
        END IF;

        -- Получить тип транзакции "перевод"
        SELECT txn_type_id INTO v_txn_type
          FROM payment_app.transaction_types
         WHERE type_code = 'TRANSFER';

        -- Создание транзакции
        INSERT INTO payment_app.transactions (
            txn_type_id, debit_account, debit_amount, debit_currency,
            credit_account, credit_amount, credit_currency,
            description, status, processed_at
        ) VALUES (
            v_txn_type, p_from_account, p_amount, v_from_bal.currency_code,
            p_to_account, p_amount, v_to_bal.currency_code,
            NVL(p_description, 'Перевод между счетами'),
            'COMPLETED', SYSDATE
        ) RETURNING txn_id, txn_ref, status
          INTO p_result.txn_id, p_result.txn_ref, p_result.status;

        -- Обновление балансов
        UPDATE payment_app.accounts
           SET balance = balance - p_amount
         WHERE account_id = p_from_account;

        UPDATE payment_app.accounts
           SET balance = balance + p_amount
         WHERE account_id = p_to_account;

        log_event(p_result.txn_id, 'TRANSFER',
            'От ' || p_from_account || ' к ' || p_to_account
            || ' сумма ' || p_amount || ' ' || v_from_bal.currency_code);

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_result.status := 'FAILED';
            p_result.error_code := SQLCODE;
            p_result.error_message := SQLERRM;
            log_event(p_result.txn_id, 'TRANSFER_ERROR', SQLERRM);
    END transfer;

    -- ─── DEPOSIT ─────────────────────────────────────────────────────────
    PROCEDURE deposit(
        p_account_id    IN  NUMBER,
        p_amount        IN  NUMBER,
        p_description   IN  VARCHAR2 DEFAULT NULL,
        p_result        OUT t_payment_result
    ) IS
        v_bal       t_account_balance;
        v_txn_type  NUMBER(10);
    BEGIN
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005,
                'Сумма пополнения должна быть положительной');
        END IF;

        check_account(p_account_id, v_bal);

        SELECT txn_type_id INTO v_txn_type
          FROM payment_app.transaction_types
         WHERE type_code = 'DEPOSIT';

        INSERT INTO payment_app.transactions (
            txn_type_id, credit_account, credit_amount, credit_currency,
            description, status, processed_at
        ) VALUES (
            v_txn_type, p_account_id, p_amount, v_bal.currency_code,
            NVL(p_description, 'Пополнение счёта'),
            'COMPLETED', SYSDATE
        ) RETURNING txn_id, txn_ref, status
          INTO p_result.txn_id, p_result.txn_ref, p_result.status;

        UPDATE payment_app.accounts
           SET balance = balance + p_amount
         WHERE account_id = p_account_id;

        log_event(p_result.txn_id, 'DEPOSIT',
            'Счёт ' || p_account_id || ' + ' || p_amount);

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_result.status := 'FAILED';
            p_result.error_code := SQLCODE;
            p_result.error_message := SQLERRM;
            log_event(p_result.txn_id, 'DEPOSIT_ERROR', SQLERRM);
    END deposit;

    -- ─── WITHDRAW ────────────────────────────────────────────────────────
    PROCEDURE withdraw(
        p_account_id    IN  NUMBER,
        p_amount        IN  NUMBER,
        p_description   IN  VARCHAR2 DEFAULT NULL,
        p_result        OUT t_payment_result
    ) IS
        v_bal       t_account_balance;
        v_txn_type  NUMBER(10);
    BEGIN
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20005,
                'Сумма списания должна быть положительной');
        END IF;

        check_account(p_account_id, v_bal);

        IF v_bal.available < p_amount THEN
            RAISE_APPLICATION_ERROR(-20001,
                'Недостаточно средств. Доступно: ' || v_bal.available);
        END IF;

        SELECT txn_type_id INTO v_txn_type
          FROM payment_app.transaction_types
         WHERE type_code = 'WITHDRAW';

        INSERT INTO payment_app.transactions (
            txn_type_id, debit_account, debit_amount, debit_currency,
            description, status, processed_at
        ) VALUES (
            v_txn_type, p_account_id, p_amount, v_bal.currency_code,
            NVL(p_description, 'Списание со счёта'),
            'COMPLETED', SYSDATE
        ) RETURNING txn_id, txn_ref, status
          INTO p_result.txn_id, p_result.txn_ref, p_result.status;

        UPDATE payment_app.accounts
           SET balance = balance - p_amount
         WHERE account_id = p_account_id;

        log_event(p_result.txn_id, 'WITHDRAW',
            'Счёт ' || p_account_id || ' - ' || p_amount);

        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_result.status := 'FAILED';
            p_result.error_code := SQLCODE;
            p_result.error_message := SQLERRM;
    END withdraw;

    -- ─── GET_BALANCE ─────────────────────────────────────────────────────
    FUNCTION get_balance(
        p_account_id IN NUMBER
    ) RETURN t_account_balance
    IS
        v_result t_account_balance;
    BEGIN
        SELECT account_id, account_number, balance, available, currency_code
          INTO v_result.account_id,
               v_result.account_number,
               v_result.balance,
               v_result.available,
               v_result.currency_code
          FROM payment_app.accounts
         WHERE account_id = p_account_id;

        RETURN v_result;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003,
                'Счёт ' || p_account_id || ' не найден');
    END get_balance;

    -- ─── GET_ACCOUNT_HISTORY (SYS_REFCURSOR) ────────────────────────────
    FUNCTION get_account_history(
        p_account_id IN NUMBER,
        p_from_date  IN DATE DEFAULT SYSDATE - 30,
        p_to_date    IN DATE DEFAULT SYSDATE,
        p_max_rows   IN NUMBER DEFAULT 100
    ) RETURN SYS_REFCURSOR
    IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        -- Oracle 11g: ROWNUM вместо FETCH FIRST
        OPEN v_cursor FOR
            SELECT * FROM (
                SELECT t.txn_id,
                       t.txn_ref,
                       tt.type_name,
                       t.debit_amount,
                       t.credit_amount,
                       t.description,
                       t.status,
                       t.created_at,
                       -- Oracle 11g: LISTAGG доступен с 11.2
                       CASE
                           WHEN t.debit_account = p_account_id
                           THEN -1 * NVL(t.debit_amount, 0)
                           ELSE NVL(t.credit_amount, 0)
                       END AS signed_amount
                  FROM payment_app.transactions t
                  JOIN payment_app.transaction_types tt
                    ON tt.txn_type_id = t.txn_type_id
                 WHERE (t.debit_account = p_account_id
                        OR t.credit_account = p_account_id)
                   AND t.created_at BETWEEN p_from_date AND p_to_date
                 ORDER BY t.created_at DESC
            )
            WHERE ROWNUM <= p_max_rows;  -- Oracle 11g row limiting

        RETURN v_cursor;
    END get_account_history;

    -- ─── PROCESS_PENDING (BULK COLLECT + FORALL) ────────────────────────
    PROCEDURE process_pending_transactions(
        p_batch_size  IN  NUMBER DEFAULT 1000,
        p_processed   OUT NUMBER,
        p_errors      OUT NUMBER
    ) IS
        v_txn_ids     t_txn_id_tab;
        v_error_count NUMBER := 0;
    BEGIN
        p_processed := 0;
        p_errors := 0;

        -- BULK COLLECT с LIMIT (Oracle 11g: хорошая практика для памяти)
        SELECT txn_id
          BULK COLLECT INTO v_txn_ids
          FROM payment_app.transactions
         WHERE status = 'PENDING'
           AND ROWNUM <= p_batch_size
           FOR UPDATE SKIP LOCKED;  -- Oracle 11g: пропуск заблокированных строк

        IF v_txn_ids.COUNT = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Нет PENDING транзакций для обработки');
            RETURN;
        END IF;

        -- FORALL: массовое обновление (намного быстрее поштучного)
        FORALL i IN 1..v_txn_ids.COUNT
            UPDATE payment_app.transactions
               SET status = 'COMPLETED',
                   processed_at = SYSDATE
             WHERE txn_id = v_txn_ids(i)
               AND status = 'PENDING';

        p_processed := SQL%ROWCOUNT;

        COMMIT;

        DBMS_OUTPUT.PUT_LINE('Обработано: ' || p_processed || ' транзакций');

    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            p_errors := v_txn_ids.COUNT;
            DBMS_OUTPUT.PUT_LINE('Ошибка пакетной обработки: ' || SQLERRM);
    END process_pending_transactions;

END payments_pkg;
/

show errors package body payment_app.payments_pkg
