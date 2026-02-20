-- Deploy accounts
-- requires: customers, account_types
-- ◆ DIAMOND зависимость: customers и account_types оба зависят от appschema
-- Sqitch автоматически разрешит порядок через топологическую сортировку

set serveroutput on size 1000000

CREATE SEQUENCE payment_app.account_id_seq
    START WITH 40800000001 INCREMENT BY 1 NOMAXVALUE CACHE 20;

CREATE TABLE payment_app.accounts (
    account_id     NUMBER(20)     NOT NULL,
    account_number VARCHAR2(20)   NOT NULL,  -- Формат: 408XXYYYYYYYYYY
    customer_id    NUMBER(12)     NOT NULL,
    acct_type_id   NUMBER(10)     NOT NULL,
    currency_code  CHAR(3)        DEFAULT 'RUB' NOT NULL,
    balance        NUMBER(18,2)   DEFAULT 0 NOT NULL,
    available      NUMBER(18,2)   DEFAULT 0 NOT NULL,  -- Доступный остаток (баланс - холды)
    hold_amount    NUMBER(18,2)   DEFAULT 0 NOT NULL,  -- Сумма холдов
    status         VARCHAR2(20)   DEFAULT 'ACTIVE' NOT NULL,
    opened_at      DATE           DEFAULT SYSDATE NOT NULL,
    closed_at      DATE,
    updated_at     DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_accounts          PRIMARY KEY (account_id),
    CONSTRAINT uq_account_number    UNIQUE (account_number),
    CONSTRAINT fk_accounts_customer FOREIGN KEY (customer_id)
        REFERENCES payment_app.customers(customer_id),
    CONSTRAINT fk_accounts_type     FOREIGN KEY (acct_type_id)
        REFERENCES payment_app.account_types(acct_type_id),
    CONSTRAINT ck_accounts_status   CHECK (status IN ('ACTIVE', 'FROZEN', 'CLOSED')),
    CONSTRAINT ck_accounts_hold     CHECK (hold_amount >= 0),
    CONSTRAINT ck_accounts_avail    CHECK (available = balance - hold_amount)
);

CREATE OR REPLACE TRIGGER payment_app.trg_accounts_bi
    BEFORE INSERT ON payment_app.accounts
    FOR EACH ROW
BEGIN
    IF :NEW.account_id IS NULL THEN
        SELECT payment_app.account_id_seq.NEXTVAL
          INTO :NEW.account_id
          FROM DUAL;
    END IF;
    -- Автогенерация номера счёта если не задан
    IF :NEW.account_number IS NULL THEN
        :NEW.account_number := '40800' || LPAD(TO_CHAR(:NEW.account_id), 15, '0');
    END IF;
    :NEW.available := :NEW.balance - NVL(:NEW.hold_amount, 0);
END;
/

show errors trigger payment_app.trg_accounts_bi

CREATE OR REPLACE TRIGGER payment_app.trg_accounts_bu
    BEFORE UPDATE ON payment_app.accounts
    FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSDATE;
    :NEW.available := :NEW.balance - NVL(:NEW.hold_amount, 0);
END;
/

show errors trigger payment_app.trg_accounts_bu

-- Индексы
CREATE INDEX payment_app.idx_accounts_customer ON payment_app.accounts(customer_id);
CREATE INDEX payment_app.idx_accounts_type ON payment_app.accounts(acct_type_id);
CREATE INDEX payment_app.idx_accounts_status ON payment_app.accounts(status);
CREATE INDEX payment_app.idx_accounts_currency ON payment_app.accounts(currency_code);

BEGIN
    DBMS_OUTPUT.PUT_LINE('Таблица accounts создана (DIAMOND: customers + account_types)');
END;
/
