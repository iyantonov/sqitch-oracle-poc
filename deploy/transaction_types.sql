-- Deploy transaction_types
-- requires: appschema
-- Типы операций (транзакций)

CREATE SEQUENCE payment_app.txn_type_id_seq
    START WITH 1 INCREMENT BY 1 NOMAXVALUE CACHE 10;

CREATE TABLE payment_app.transaction_types (
    txn_type_id    NUMBER(10)     NOT NULL,
    type_code      VARCHAR2(20)   NOT NULL,
    type_name      VARCHAR2(200)  NOT NULL,
    debit_credit   CHAR(1)        NOT NULL,  -- D=debit, C=credit, B=both(transfer)
    description    VARCHAR2(1000),
    is_active      NUMBER(1)      DEFAULT 1 NOT NULL,
    created_at     DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_transaction_types    PRIMARY KEY (txn_type_id),
    CONSTRAINT uq_txn_types_code      UNIQUE (type_code),
    CONSTRAINT ck_txn_debit_credit     CHECK (debit_credit IN ('D', 'C', 'B'))
);

CREATE OR REPLACE TRIGGER payment_app.trg_txn_types_bi
    BEFORE INSERT ON payment_app.transaction_types
    FOR EACH ROW
    WHEN (NEW.txn_type_id IS NULL)
BEGIN
    SELECT payment_app.txn_type_id_seq.NEXTVAL
      INTO :NEW.txn_type_id
      FROM DUAL;
END;
/

show errors trigger payment_app.trg_txn_types_bi

COMMENT ON TABLE payment_app.transaction_types IS 'Справочник типов операций: пополнение, списание, перевод, комиссия';
