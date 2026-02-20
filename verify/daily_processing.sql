-- Verify daily_processing
SELECT 1/COUNT(*) FROM user_objects
 WHERE object_name = 'DAILY_PROCESSING' AND object_type = 'PACKAGE' AND status = 'VALID';
SELECT 1/COUNT(*) FROM user_objects
 WHERE object_name = 'DAILY_PROCESSING' AND object_type = 'PACKAGE BODY' AND status = 'VALID';
