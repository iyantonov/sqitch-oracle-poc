-- Revert exchange_rates
DROP TRIGGER payment_app.trg_exch_rates_bi;
DROP TABLE payment_app.exchange_rates;
DROP SEQUENCE payment_app.exch_rate_id_seq;
