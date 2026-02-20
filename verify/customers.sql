-- Verify customers
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'CUSTOMERS';
SELECT 1/COUNT(*) FROM user_triggers WHERE trigger_name = 'TRG_CUSTOMERS_BI';
SELECT 1/COUNT(*) FROM user_triggers WHERE trigger_name = 'TRG_CUSTOMERS_BU';
