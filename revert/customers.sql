-- Revert customers
DROP TRIGGER payment_app.trg_customers_bu;
DROP TRIGGER payment_app.trg_customers_bi;
DROP TABLE payment_app.customers;
DROP SEQUENCE payment_app.customer_id_seq;
