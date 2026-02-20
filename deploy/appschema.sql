-- Deploy appschema
-- Корень DAG: настройка схемы приложения
-- Все остальные миграции зависят от этого change

-- Примечание: Sqitch автоматически устанавливает:
--   WHENEVER SQLERROR EXIT SQL.SQLCODE
--   WHENEVER OSERROR EXIT 9
-- перед запуском этого скрипта через sqlplus

-- Настройки сессии (SQL*Plus-специфичные команды — работают в Sqitch!)
set serveroutput on size 1000000
set echo off

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Настройка схемы payment_app ===');
    DBMS_OUTPUT.PUT_LINE('Время: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
END;
/

-- Создание табличного пространства для данных приложения (Oracle 11g)
-- В XE только USERS доступен, поэтому используем его
-- В production: CREATE TABLESPACE payment_data ...

-- Создание последовательности для глобальных ID
CREATE SEQUENCE payment_app.global_id_seq
    START WITH 1000
    INCREMENT BY 1
    NOMAXVALUE
    CACHE 20;

-- Таблица метаданных приложения (Oracle 11g: нет IDENTITY, используем DEFAULT)
CREATE TABLE payment_app.app_metadata (
    param_name   VARCHAR2(100)  NOT NULL,
    param_value  VARCHAR2(4000),
    updated_at   DATE           DEFAULT SYSDATE NOT NULL,
    updated_by   VARCHAR2(100)  DEFAULT USER NOT NULL,
    CONSTRAINT pk_app_metadata PRIMARY KEY (param_name)
);

-- Заполнение метаданных
INSERT INTO payment_app.app_metadata (param_name, param_value)
VALUES ('APP_VERSION', '1.0.0');

INSERT INTO payment_app.app_metadata (param_name, param_value)
VALUES ('SCHEMA_OWNER', 'PAYMENT_APP');

INSERT INTO payment_app.app_metadata (param_name, param_value)
VALUES ('MIGRATION_TOOL', 'Sqitch');

COMMIT;

BEGIN
    DBMS_OUTPUT.PUT_LINE('=== Схема payment_app настроена ===');
END;
/
