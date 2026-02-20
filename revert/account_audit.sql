-- Revert account_audit
DROP TRIGGER payment_app.trg_accounts_audit;
DROP TABLE payment_app.account_audit_log;
DROP SEQUENCE payment_app.audit_id_seq;
