-- Verify reports_pkg
SELECT 1/COUNT(*) FROM user_objects
 WHERE object_name = 'REPORTS_PKG' AND object_type = 'PACKAGE' AND status = 'VALID';
SELECT 1/COUNT(*) FROM user_objects
 WHERE object_name = 'REPORTS_PKG' AND object_type = 'PACKAGE BODY' AND status = 'VALID';
