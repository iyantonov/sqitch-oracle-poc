-- Revert accounts
DROP TRIGGER payment_app.trg_accounts_bu;
DROP TRIGGER payment_app.trg_accounts_bi;
DROP TABLE payment_app.accounts;
DROP SEQUENCE payment_app.account_id_seq;
