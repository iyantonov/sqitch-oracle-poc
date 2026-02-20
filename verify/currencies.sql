-- Verify currencies
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'CURRENCIES';
SELECT 1/COUNT(*) FROM user_triggers WHERE trigger_name = 'TRG_CURRENCIES_BI';
