-- Revert seed_reference_data
DELETE FROM payment_app.transaction_types;
DELETE FROM payment_app.account_types;
DELETE FROM payment_app.currencies;
COMMIT;
