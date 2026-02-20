-- Deploy account_types
-- requires: appschema
-- Типы банковских счетов

CREATE SEQUENCE payment_app.acct_type_id_seq
    START WITH 1 INCREMENT BY 1 NOMAXVALUE CACHE 10;

CREATE TABLE payment_app.account_types (
    acct_type_id    NUMBER(10)     NOT NULL,
    type_code       VARCHAR2(20)   NOT NULL,
    type_name       VARCHAR2(200)  NOT NULL,
    description     VARCHAR2(1000),
    allows_debit    NUMBER(1)      DEFAULT 1 NOT NULL,
    allows_credit   NUMBER(1)      DEFAULT 1 NOT NULL,
    min_balance     NUMBER(18,2)   DEFAULT 0,
    is_active       NUMBER(1)      DEFAULT 1 NOT NULL,
    created_at      DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_account_types      PRIMARY KEY (acct_type_id),
    CONSTRAINT uq_acct_types_code    UNIQUE (type_code),
    CONSTRAINT ck_acct_allows_debit  CHECK (allows_debit IN (0, 1)),
    CONSTRAINT ck_acct_allows_credit CHECK (allows_credit IN (0, 1))
);

CREATE OR REPLACE TRIGGER payment_app.trg_acct_types_bi
    BEFORE INSERT ON payment_app.account_types
    FOR EACH ROW
    WHEN (NEW.acct_type_id IS NULL)
BEGIN
    SELECT payment_app.acct_type_id_seq.NEXTVAL
      INTO :NEW.acct_type_id
      FROM DUAL;
END;
/

show errors trigger payment_app.trg_acct_types_bi

COMMENT ON TABLE payment_app.account_types IS 'Типы банковских счетов (текущий, депозитный, ссудный, транзитный)';
