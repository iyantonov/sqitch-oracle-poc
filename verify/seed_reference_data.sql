-- Verify seed_reference_data
SELECT 1/COUNT(*) FROM payment_app.currencies WHERE ROWNUM = 1;
SELECT 1/COUNT(*) FROM payment_app.account_types WHERE ROWNUM = 1;
SELECT 1/COUNT(*) FROM payment_app.transaction_types WHERE ROWNUM = 1;
