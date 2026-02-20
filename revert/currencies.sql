-- Revert currencies
DROP TRIGGER payment_app.trg_currencies_bi;
DROP TABLE payment_app.currencies;
DROP SEQUENCE payment_app.currency_id_seq;
