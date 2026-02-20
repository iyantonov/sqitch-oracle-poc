-- Verify seed_test_data
SELECT 1/COUNT(*) FROM payment_app.customers WHERE ROWNUM = 1;
SELECT 1/COUNT(*) FROM payment_app.accounts WHERE ROWNUM = 1;
SELECT 1/COUNT(*) FROM payment_app.transactions WHERE ROWNUM = 1;
