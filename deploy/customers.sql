-- Deploy customers
-- requires: appschema
-- Таблица клиентов (физ.лица, юр.лица)

CREATE SEQUENCE payment_app.customer_id_seq
    START WITH 10000 INCREMENT BY 1 NOMAXVALUE CACHE 20;

CREATE TABLE payment_app.customers (
    customer_id    NUMBER(12)     NOT NULL,
    customer_type  CHAR(1)        NOT NULL,  -- P=physical, L=legal
    first_name     VARCHAR2(200),
    last_name      VARCHAR2(200),
    company_name   VARCHAR2(500),
    tax_id         VARCHAR2(20),             -- ИНН
    phone          VARCHAR2(30),
    email          VARCHAR2(200),
    -- Oracle 11g: нет JSON-типа, используем CLOB для дополнительных данных
    extra_data     CLOB,
    status         VARCHAR2(20)   DEFAULT 'ACTIVE' NOT NULL,
    created_at     DATE           DEFAULT SYSDATE NOT NULL,
    updated_at     DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_customers        PRIMARY KEY (customer_id),
    CONSTRAINT ck_customer_type    CHECK (customer_type IN ('P', 'L')),
    CONSTRAINT ck_customer_status  CHECK (status IN ('ACTIVE', 'BLOCKED', 'CLOSED')),
    -- ФЛ: обязательны ФИО. ЮЛ: обязательно наименование
    CONSTRAINT ck_customer_name    CHECK (
        (customer_type = 'P' AND first_name IS NOT NULL AND last_name IS NOT NULL)
        OR
        (customer_type = 'L' AND company_name IS NOT NULL)
    )
);

CREATE OR REPLACE TRIGGER payment_app.trg_customers_bi
    BEFORE INSERT ON payment_app.customers
    FOR EACH ROW
    WHEN (NEW.customer_id IS NULL)
BEGIN
    SELECT payment_app.customer_id_seq.NEXTVAL
      INTO :NEW.customer_id
      FROM DUAL;
END;
/

show errors trigger payment_app.trg_customers_bi

-- Триггер обновления updated_at (Oracle 11g: нет ON UPDATE DEFAULT)
CREATE OR REPLACE TRIGGER payment_app.trg_customers_bu
    BEFORE UPDATE ON payment_app.customers
    FOR EACH ROW
BEGIN
    :NEW.updated_at := SYSDATE;
END;
/

show errors trigger payment_app.trg_customers_bu

-- Индексы для поиска
CREATE INDEX payment_app.idx_customers_tax_id ON payment_app.customers(tax_id);
CREATE INDEX payment_app.idx_customers_phone ON payment_app.customers(phone);
CREATE INDEX payment_app.idx_customers_status ON payment_app.customers(status);

COMMENT ON TABLE payment_app.customers IS 'Клиенты: физические и юридические лица';
