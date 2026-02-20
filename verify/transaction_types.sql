-- Verify transaction_types
SELECT 1/COUNT(*) FROM user_tables WHERE table_name = 'TRANSACTION_TYPES';
