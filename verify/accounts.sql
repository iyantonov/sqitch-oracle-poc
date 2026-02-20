-- Verify accounts
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'ACCOUNTS';
-- Проверка FK на customers и account_types
SELECT 1/COUNT(*) FROM user_constraints
 WHERE table_name = 'ACCOUNTS' AND constraint_name = 'FK_ACCOUNTS_CUSTOMER';
SELECT 1/COUNT(*) FROM user_constraints
 WHERE table_name = 'ACCOUNTS' AND constraint_name = 'FK_ACCOUNTS_TYPE';
