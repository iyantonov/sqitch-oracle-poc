-- Verify transactions
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'TRANSACTIONS';
-- Проверка FK на accounts, currencies, transaction_types (WIDE dependency)
SELECT 1/COUNT(*) FROM user_constraints
 WHERE table_name = 'TRANSACTIONS' AND constraint_type = 'R';
