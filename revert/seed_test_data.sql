-- Revert seed_test_data
DELETE FROM payment_app.exchange_rates;
DELETE FROM payment_app.transactions;
DELETE FROM payment_app.accounts;
DELETE FROM payment_app.customers;
COMMIT;
