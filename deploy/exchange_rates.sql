-- Deploy exchange_rates
-- requires: currencies

CREATE SEQUENCE payment_app.exch_rate_id_seq
    START WITH 1 INCREMENT BY 1 NOMAXVALUE CACHE 20;

CREATE TABLE payment_app.exchange_rates (
    rate_id         NUMBER(12)     NOT NULL,
    from_currency   CHAR(3)        NOT NULL,
    to_currency     CHAR(3)        NOT NULL,
    rate            NUMBER(18,8)   NOT NULL,
    rate_date       DATE           NOT NULL,
    source          VARCHAR2(100)  DEFAULT 'CBR' NOT NULL,
    created_at      DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT pk_exchange_rates    PRIMARY KEY (rate_id),
    CONSTRAINT fk_exch_from_curr    FOREIGN KEY (from_currency)
        REFERENCES payment_app.currencies(iso_code),
    CONSTRAINT fk_exch_to_curr      FOREIGN KEY (to_currency)
        REFERENCES payment_app.currencies(iso_code),
    CONSTRAINT ck_exch_rate_pos     CHECK (rate > 0),
    CONSTRAINT ck_exch_diff_curr    CHECK (from_currency != to_currency),
    CONSTRAINT uq_exch_rate_pair    UNIQUE (from_currency, to_currency, rate_date, source)
);

CREATE OR REPLACE TRIGGER payment_app.trg_exch_rates_bi
    BEFORE INSERT ON payment_app.exchange_rates
    FOR EACH ROW
    WHEN (NEW.rate_id IS NULL)
BEGIN
    SELECT payment_app.exch_rate_id_seq.NEXTVAL
      INTO :NEW.rate_id
      FROM DUAL;
END;
/

show errors trigger payment_app.trg_exch_rates_bi

-- Индекс для поиска по дате
CREATE INDEX payment_app.idx_exch_rates_date ON payment_app.exchange_rates(rate_date DESC);
CREATE INDEX payment_app.idx_exch_rates_pair ON payment_app.exchange_rates(from_currency, to_currency);

COMMENT ON TABLE payment_app.exchange_rates IS 'Курсы валют ЦБ РФ';
