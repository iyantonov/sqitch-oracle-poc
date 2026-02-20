-- Verify account_audit
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'ACCOUNT_AUDIT_LOG';
SELECT 1/COUNT(*) FROM user_triggers WHERE trigger_name = 'TRG_ACCOUNTS_AUDIT';
-- Проверка virtual column (Oracle 11g)
SELECT 1/COUNT(*) FROM user_tab_cols
 WHERE table_name = 'ACCOUNT_AUDIT_LOG' AND column_name = 'IS_SIGNIFICANT' AND virtual_column = 'YES';
