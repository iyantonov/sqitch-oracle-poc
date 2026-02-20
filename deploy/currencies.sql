-- Deploy currencies
-- requires: appschema
-- Справочник валют по ISO 4217

set serveroutput on size 1000000

CREATE SEQUENCE payment_app.currency_id_seq
    START WITH 1 INCREMENT BY 1 NOMAXVALUE CACHE 10;

CREATE TABLE payment_app.currencies (
    currency_id    NUMBER(10)     NOT NULL,
    iso_code       CHAR(3)        NOT NULL,
    iso_num        CHAR(3),
    currency_name  VARCHAR2(200)  NOT NULL,
    minor_units    NUMBER(1)      DEFAULT 2 NOT NULL,
    is_active      NUMBER(1)      DEFAULT 1 NOT NULL,
    created_at     DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_currencies       PRIMARY KEY (currency_id),
    CONSTRAINT uq_currencies_code  UNIQUE (iso_code),
    CONSTRAINT ck_currencies_active CHECK (is_active IN (0, 1))
);

-- Oracle 11g: триггер для автоинкремента (нет IDENTITY столбцов!)
CREATE OR REPLACE TRIGGER payment_app.trg_currencies_bi
    BEFORE INSERT ON payment_app.currencies
    FOR EACH ROW
    WHEN (NEW.currency_id IS NULL)
BEGIN
    SELECT payment_app.currency_id_seq.NEXTVAL
      INTO :NEW.currency_id
      FROM DUAL;
END;
/

show errors trigger payment_app.trg_currencies_bi

COMMENT ON TABLE payment_app.currencies IS 'Справочник валют ISO 4217';
COMMENT ON COLUMN payment_app.currencies.iso_code IS 'Трёхбуквенный код валюты (RUB, USD, EUR)';
COMMENT ON COLUMN payment_app.currencies.minor_units IS 'Количество знаков после запятой (2 для RUB, 0 для JPY)';

BEGIN
    DBMS_OUTPUT.PUT_LINE('Таблица currencies создана');
END;
/
