-- ==========================================================================
-- Инициализация Oracle XE для PoC Sqitch миграций
-- Выполняется автоматически при первом запуске контейнера
-- (через /container-entrypoint-initdb.d/)
-- ==========================================================================

-- Создание схемы для реестра Sqitch (отдельно от бизнес-данных!)
-- Принцип 6 из стратегии: отдельная схема для реестра миграций
CREATE USER sqitch_registry IDENTIFIED BY SqitchReg2025
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP;

GRANT CONNECT, RESOURCE TO sqitch_registry;
GRANT UNLIMITED TABLESPACE TO sqitch_registry;

-- Даём payment_app права на чтение реестра sqitch (для аудита)
-- APP_USER (payment_app) уже создан gvenzl-образом через переменные окружения
GRANT CREATE SESSION TO payment_app;
GRANT CREATE TABLE TO payment_app;
GRANT CREATE VIEW TO payment_app;
GRANT CREATE SEQUENCE TO payment_app;
GRANT CREATE PROCEDURE TO payment_app;
GRANT CREATE TRIGGER TO payment_app;
GRANT CREATE TYPE TO payment_app;
GRANT CREATE SYNONYM TO payment_app;
GRANT UNLIMITED TABLESPACE TO payment_app;

-- Права для работы с DBMS_OUTPUT (нужно для PL/SQL пакетов)
GRANT EXECUTE ON DBMS_OUTPUT TO payment_app;
GRANT EXECUTE ON DBMS_LOCK TO payment_app;

-- Права для sqitch registry — sqitch будет создавать таблицы
-- в схеме payment_app (registry_schema в sqitch.conf)
GRANT SELECT ON dba_tab_columns TO payment_app;

EXIT;
