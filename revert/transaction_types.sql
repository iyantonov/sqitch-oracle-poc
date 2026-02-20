-- Revert transaction_types
DROP TRIGGER payment_app.trg_txn_types_bi;
DROP TABLE payment_app.transaction_types;
DROP SEQUENCE payment_app.txn_type_id_seq;
