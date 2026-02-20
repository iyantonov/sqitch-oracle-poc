-- Deploy account_audit
-- requires: accounts
-- Триггерный аудит изменений баланса счетов
-- Oracle 11g: compound trigger (доступен с 11.1)

set serveroutput on size 1000000

-- Таблица аудита
CREATE TABLE payment_app.account_audit_log (
    audit_id        NUMBER(18)    NOT NULL,
    account_id      NUMBER(20)    NOT NULL,
    operation       VARCHAR2(10)  NOT NULL,  -- UPDATE, INSERT
    old_balance     NUMBER(18,2),
    new_balance     NUMBER(18,2),
    balance_change  NUMBER(18,2),
    old_status      VARCHAR2(20),
    new_status      VARCHAR2(20),
    changed_by      VARCHAR2(100) DEFAULT USER NOT NULL,
    changed_at      DATE          DEFAULT SYSDATE NOT NULL,
    -- Oracle 11g: VIRTUAL COLUMN (вычисляемый столбец, доступен с 11.1)
    is_significant  NUMBER(1) GENERATED ALWAYS AS (
        CASE WHEN ABS(NVL(balance_change, 0)) > 1000000 THEN 1 ELSE 0 END
    ) VIRTUAL,
    CONSTRAINT pk_account_audit PRIMARY KEY (audit_id)
);

CREATE SEQUENCE payment_app.audit_id_seq
    START WITH 1 INCREMENT BY 1 NOMAXVALUE CACHE 100;

-- Oracle 11g: COMPOUND TRIGGER (введён в 11g)
-- Позволяет объединить BEFORE и AFTER логику в одном триггере
CREATE OR REPLACE TRIGGER payment_app.trg_accounts_audit
    FOR UPDATE OF balance, status ON payment_app.accounts
    COMPOUND TRIGGER

    -- Декларативная секция compound trigger
    TYPE t_audit_rec IS RECORD (
        account_id     NUMBER(20),
        old_balance    NUMBER(18,2),
        new_balance    NUMBER(18,2),
        old_status     VARCHAR2(20),
        new_status     VARCHAR2(20)
    );
    TYPE t_audit_tab IS TABLE OF t_audit_rec INDEX BY PLS_INTEGER;

    v_audit_records t_audit_tab;
    v_idx PLS_INTEGER := 0;

    -- AFTER EACH ROW: собираем записи
    AFTER EACH ROW IS
    BEGIN
        IF :OLD.balance != :NEW.balance OR :OLD.status != :NEW.status THEN
            v_idx := v_idx + 1;
            v_audit_records(v_idx).account_id  := :NEW.account_id;
            v_audit_records(v_idx).old_balance := :OLD.balance;
            v_audit_records(v_idx).new_balance := :NEW.balance;
            v_audit_records(v_idx).old_status  := :OLD.status;
            v_audit_records(v_idx).new_status  := :NEW.status;
        END IF;
    END AFTER EACH ROW;

    -- AFTER STATEMENT: массовая вставка (эффективнее построчной)
    AFTER STATEMENT IS
    BEGIN
        IF v_audit_records.COUNT > 0 THEN
            FORALL i IN 1..v_audit_records.COUNT
                INSERT INTO payment_app.account_audit_log (
                    audit_id, account_id, operation,
                    old_balance, new_balance, balance_change,
                    old_status, new_status
                ) VALUES (
                    payment_app.audit_id_seq.NEXTVAL,
                    v_audit_records(i).account_id,
                    'UPDATE',
                    v_audit_records(i).old_balance,
                    v_audit_records(i).new_balance,
                    v_audit_records(i).new_balance - v_audit_records(i).old_balance,
                    v_audit_records(i).old_status,
                    v_audit_records(i).new_status
                );
        END IF;
        v_audit_records.DELETE;
        v_idx := 0;
    END AFTER STATEMENT;

END trg_accounts_audit;
/

show errors trigger payment_app.trg_accounts_audit

-- Индексы для аналитики аудита
CREATE INDEX payment_app.idx_audit_account ON payment_app.account_audit_log(account_id);
CREATE INDEX payment_app.idx_audit_date ON payment_app.account_audit_log(changed_at DESC);
CREATE INDEX payment_app.idx_audit_signif ON payment_app.account_audit_log(is_significant);

BEGIN
    DBMS_OUTPUT.PUT_LINE('Аудит-триггер (compound trigger Oracle 11g) создан');
END;
/
