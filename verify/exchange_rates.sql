-- Verify exchange_rates
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'EXCHANGE_RATES';
SELECT 1/COUNT(*) FROM user_constraints
 WHERE table_name = 'EXCHANGE_RATES' AND constraint_name = 'FK_EXCH_FROM_CURR';
