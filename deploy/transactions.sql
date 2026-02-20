-- Deploy transactions
-- requires: accounts, currencies, transaction_types
-- ◆ WIDE зависимость: объединяет 3 независимые ветки DAG
-- Sqitch выполнит все три зависимости перед этим change

set serveroutput on size 1000000

CREATE SEQUENCE payment_app.transaction_id_seq
    START WITH 1 INCREMENT BY 1 NOMAXVALUE CACHE 100;

-- Основная таблица транзакций
CREATE TABLE payment_app.transactions (
    txn_id          NUMBER(18)     NOT NULL,
    txn_ref         VARCHAR2(36)   NOT NULL,   -- UUID-подобный идентификатор
    txn_type_id     NUMBER(10)     NOT NULL,
    -- Дебетовая сторона
    debit_account   NUMBER(20),
    debit_amount    NUMBER(18,2),
    debit_currency  CHAR(3),
    -- Кредитовая сторона
    credit_account  NUMBER(20),
    credit_amount   NUMBER(18,2),
    credit_currency CHAR(3),
    -- Курс конвертации (если валюты разные)
    exchange_rate   NUMBER(18,8),
    -- Описание и статус
    description     VARCHAR2(1000),
    status          VARCHAR2(20)   DEFAULT 'PENDING' NOT NULL,
    error_code      VARCHAR2(50),
    error_message   VARCHAR2(1000),
    -- Аудит
    created_at      DATE           DEFAULT SYSDATE NOT NULL,
    processed_at    DATE,
    created_by      VARCHAR2(100)  DEFAULT USER NOT NULL,
    --
    CONSTRAINT pk_transactions       PRIMARY KEY (txn_id),
    CONSTRAINT uq_txn_ref           UNIQUE (txn_ref),
    CONSTRAINT fk_txn_type          FOREIGN KEY (txn_type_id)
        REFERENCES payment_app.transaction_types(txn_type_id),
    CONSTRAINT fk_txn_debit_acct    FOREIGN KEY (debit_account)
        REFERENCES payment_app.accounts(account_id),
    CONSTRAINT fk_txn_credit_acct   FOREIGN KEY (credit_account)
        REFERENCES payment_app.accounts(account_id),
    CONSTRAINT ck_txn_status        CHECK (status IN (
        'PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'REVERSED'
    )),
    CONSTRAINT ck_txn_has_side      CHECK (
        debit_account IS NOT NULL OR credit_account IS NOT NULL
    )
);

CREATE OR REPLACE TRIGGER payment_app.trg_transactions_bi
    BEFORE INSERT ON payment_app.transactions
    FOR EACH ROW
BEGIN
    IF :NEW.txn_id IS NULL THEN
        SELECT payment_app.transaction_id_seq.NEXTVAL
          INTO :NEW.txn_id
          FROM DUAL;
    END IF;
    -- Генерация уникальной ссылки (Oracle 11g: нет SYS_GUID в формате UUID)
    IF :NEW.txn_ref IS NULL THEN
        :NEW.txn_ref := RAWTOHEX(SYS_GUID());
    END IF;
END;
/

show errors trigger payment_app.trg_transactions_bi

-- Партиционирование в Oracle 11g XE недоступно (нужен EE)
-- В production: PARTITION BY RANGE (created_at) INTERVAL (NUMTOYMINTERVAL(1,'MONTH'))

-- Индексы для производительности
CREATE INDEX payment_app.idx_txn_debit ON payment_app.transactions(debit_account);
CREATE INDEX payment_app.idx_txn_credit ON payment_app.transactions(credit_account);
CREATE INDEX payment_app.idx_txn_status ON payment_app.transactions(status);
CREATE INDEX payment_app.idx_txn_created ON payment_app.transactions(created_at DESC);
CREATE INDEX payment_app.idx_txn_type ON payment_app.transactions(txn_type_id);

-- Составной индекс для типичного запроса: транзакции счёта за период
CREATE INDEX payment_app.idx_txn_acct_date ON payment_app.transactions(
    debit_account, created_at DESC
);

BEGIN
    DBMS_OUTPUT.PUT_LINE('Таблица transactions создана');
    DBMS_OUTPUT.PUT_LINE('WIDE зависимость: accounts + currencies + transaction_types');
END;
/
