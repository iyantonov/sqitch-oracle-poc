-- Verify appschema
SELECT 1/COUNT(*) FROM payment_app.app_metadata WHERE param_name = 'APP_VERSION';
SELECT 1/COUNT(*) FROM user_sequences WHERE sequence_name = 'GLOBAL_ID_SEQ';
