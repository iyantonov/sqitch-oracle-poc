-- Revert account_types
DROP TRIGGER payment_app.trg_acct_types_bi;
DROP TABLE payment_app.account_types;
DROP SEQUENCE payment_app.acct_type_id_seq;
