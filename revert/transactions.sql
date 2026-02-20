-- Revert transactions
DROP TRIGGER payment_app.trg_transactions_bi;
DROP TABLE payment_app.transactions;
DROP SEQUENCE payment_app.transaction_id_seq;
