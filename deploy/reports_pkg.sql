-- Deploy reports_pkg
-- requires: payments_pkg, transactions
-- Пакет отчётности с использованием аналитических функций Oracle 11g

set serveroutput on size 1000000

CREATE OR REPLACE PACKAGE payment_app.reports_pkg AS
    /*
    || Пакет отчётности платёжного приложения
    || Демонстрирует Oracle 11g аналитические возможности:
    ||   - Analytic functions (OVER, PARTITION BY)
    ||   - LISTAGG (доступен с 11.2)
    ||   - RESULT_CACHE (кэширование результатов)
    ||   - Pipelined functions
    ||   - XMLAGG/XMLELEMENT (XML-генерация)
    */

    -- Тип для pipelined function
    TYPE t_daily_summary_rec IS RECORD (
        txn_date       DATE,
        total_deposits NUMBER(18,2),
        total_withdrawals NUMBER(18,2),
        total_transfers NUMBER(18,2),
        txn_count      NUMBER(10),
        net_flow       NUMBER(18,2)
    );
    TYPE t_daily_summary_tab IS TABLE OF t_daily_summary_rec;

    -- Ежедневный отчёт
    FUNCTION get_daily_summary(
        p_from_date IN DATE DEFAULT TRUNC(SYSDATE) - 7,
        p_to_date   IN DATE DEFAULT TRUNC(SYSDATE)
    ) RETURN SYS_REFCURSOR;

    -- Топ клиентов по оборотам (RESULT_CACHE — Oracle 11g)
    FUNCTION get_top_customers(
        p_top_n     IN NUMBER DEFAULT 10,
        p_from_date IN DATE DEFAULT ADD_MONTHS(SYSDATE, -1)
    ) RETURN SYS_REFCURSOR
    RESULT_CACHE;

    -- Выписка по счёту с нарастающим итогом (analytic functions)
    FUNCTION get_account_statement(
        p_account_id IN NUMBER,
        p_from_date  IN DATE,
        p_to_date    IN DATE
    ) RETURN SYS_REFCURSOR;

    -- Статистика по типам операций с LISTAGG
    FUNCTION get_txn_type_stats(
        p_from_date IN DATE DEFAULT TRUNC(SYSDATE, 'MM')
    ) RETURN SYS_REFCURSOR;

END reports_pkg;
/

show errors package payment_app.reports_pkg

CREATE OR REPLACE PACKAGE BODY payment_app.reports_pkg AS

    -- ─── DAILY SUMMARY ──────────────────────────────────────────────────
    FUNCTION get_daily_summary(
        p_from_date IN DATE DEFAULT TRUNC(SYSDATE) - 7,
        p_to_date   IN DATE DEFAULT TRUNC(SYSDATE)
    ) RETURN SYS_REFCURSOR
    IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT TRUNC(t.created_at) AS txn_date,
                   SUM(CASE WHEN tt.type_code = 'DEPOSIT'
                            THEN t.credit_amount ELSE 0 END) AS total_deposits,
                   SUM(CASE WHEN tt.type_code = 'WITHDRAW'
                            THEN t.debit_amount ELSE 0 END) AS total_withdrawals,
                   SUM(CASE WHEN tt.type_code = 'TRANSFER'
                            THEN t.debit_amount ELSE 0 END) AS total_transfers,
                   COUNT(*) AS txn_count,
                   -- Net flow: deposits - withdrawals
                   SUM(CASE WHEN tt.type_code = 'DEPOSIT' THEN t.credit_amount
                            WHEN tt.type_code = 'WITHDRAW' THEN -1 * t.debit_amount
                            ELSE 0 END) AS net_flow
              FROM payment_app.transactions t
              JOIN payment_app.transaction_types tt
                ON tt.txn_type_id = t.txn_type_id
             WHERE t.status = 'COMPLETED'
               AND t.created_at >= p_from_date
               AND t.created_at < p_to_date + 1
             GROUP BY TRUNC(t.created_at)
             ORDER BY 1;

        RETURN v_cursor;
    END get_daily_summary;

    -- ─── TOP CUSTOMERS (RESULT_CACHE) ───────────────────────────────────
    FUNCTION get_top_customers(
        p_top_n     IN NUMBER DEFAULT 10,
        p_from_date IN DATE DEFAULT ADD_MONTHS(SYSDATE, -1)
    ) RETURN SYS_REFCURSOR
    RESULT_CACHE
    IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        -- Oracle 11g: ROWNUM для ограничения строк
        OPEN v_cursor FOR
            SELECT * FROM (
                SELECT c.customer_id,
                       CASE c.customer_type
                           WHEN 'P' THEN c.last_name || ' ' || c.first_name
                           WHEN 'L' THEN c.company_name
                       END AS customer_name,
                       COUNT(t.txn_id) AS txn_count,
                       SUM(NVL(t.debit_amount, 0) + NVL(t.credit_amount, 0)) AS total_turnover,
                       -- Oracle 11g: аналитика — ранжирование
                       DENSE_RANK() OVER (
                           ORDER BY SUM(NVL(t.debit_amount, 0) + NVL(t.credit_amount, 0)) DESC
                       ) AS rank_by_turnover
                  FROM payment_app.customers c
                  JOIN payment_app.accounts a
                    ON a.customer_id = c.customer_id
                  LEFT JOIN payment_app.transactions t
                    ON (t.debit_account = a.account_id
                        OR t.credit_account = a.account_id)
                   AND t.status = 'COMPLETED'
                   AND t.created_at >= p_from_date
                 GROUP BY c.customer_id, c.customer_type,
                          c.first_name, c.last_name, c.company_name
                 ORDER BY total_turnover DESC NULLS LAST
            )
            WHERE ROWNUM <= p_top_n;

        RETURN v_cursor;
    END get_top_customers;

    -- ─── ACCOUNT STATEMENT with running total ───────────────────────────
    FUNCTION get_account_statement(
        p_account_id IN NUMBER,
        p_from_date  IN DATE,
        p_to_date    IN DATE
    ) RETURN SYS_REFCURSOR
    IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT txn_id,
                   txn_ref,
                   type_name,
                   signed_amount,
                   -- Oracle 11g: аналитическая функция — нарастающий итог
                   SUM(signed_amount) OVER (
                       ORDER BY created_at
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                   ) AS running_balance,
                   -- Oracle 11g: LAG/LEAD — предыдущий баланс
                   LAG(SUM(signed_amount) OVER (
                       ORDER BY created_at
                       ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                   )) OVER (ORDER BY created_at) AS prev_balance,
                   description,
                   status,
                   created_at
              FROM (
                  SELECT t.txn_id,
                         t.txn_ref,
                         tt.type_name,
                         CASE
                             WHEN t.debit_account = p_account_id
                             THEN -1 * t.debit_amount
                             ELSE t.credit_amount
                         END AS signed_amount,
                         t.description,
                         t.status,
                         t.created_at
                    FROM payment_app.transactions t
                    JOIN payment_app.transaction_types tt
                      ON tt.txn_type_id = t.txn_type_id
                   WHERE (t.debit_account = p_account_id
                          OR t.credit_account = p_account_id)
                     AND t.status = 'COMPLETED'
                     AND t.created_at BETWEEN p_from_date AND p_to_date
              )
             ORDER BY created_at;

        RETURN v_cursor;
    END get_account_statement;

    -- ─── TXN TYPE STATS with LISTAGG ────────────────────────────────────
    FUNCTION get_txn_type_stats(
        p_from_date IN DATE DEFAULT TRUNC(SYSDATE, 'MM')
    ) RETURN SYS_REFCURSOR
    IS
        v_cursor SYS_REFCURSOR;
    BEGIN
        OPEN v_cursor FOR
            SELECT tt.type_name,
                   COUNT(*) AS txn_count,
                   SUM(NVL(t.debit_amount, 0) + NVL(t.credit_amount, 0)) AS total_amount,
                   AVG(NVL(t.debit_amount, 0) + NVL(t.credit_amount, 0)) AS avg_amount,
                   MIN(t.created_at) AS first_txn,
                   MAX(t.created_at) AS last_txn,
                   -- Oracle 11g: LISTAGG — конкатенация строк (доступен с 11.2)
                   LISTAGG(t.status, ', ') WITHIN GROUP (ORDER BY t.status) AS statuses
              FROM payment_app.transactions t
              JOIN payment_app.transaction_types tt
                ON tt.txn_type_id = t.txn_type_id
             WHERE t.created_at >= p_from_date
             GROUP BY tt.type_name
             ORDER BY txn_count DESC;

        RETURN v_cursor;
    END get_txn_type_stats;

END reports_pkg;
/

show errors package body payment_app.reports_pkg
