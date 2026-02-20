-- Deploy seed_reference_data
-- requires: currencies, account_types, transaction_types
-- Заполнение справочных таблиц

set serveroutput on size 1000000

-- ─── Валюты ─────────────────────────────────────────────────────────────
INSERT INTO payment_app.currencies (iso_code, iso_num, currency_name, minor_units)
VALUES ('RUB', '643', 'Российский рубль', 2);

INSERT INTO payment_app.currencies (iso_code, iso_num, currency_name, minor_units)
VALUES ('USD', '840', 'Доллар США', 2);

INSERT INTO payment_app.currencies (iso_code, iso_num, currency_name, minor_units)
VALUES ('EUR', '978', 'Евро', 2);

INSERT INTO payment_app.currencies (iso_code, iso_num, currency_name, minor_units)
VALUES ('CNY', '156', 'Китайский юань', 2);

INSERT INTO payment_app.currencies (iso_code, iso_num, currency_name, minor_units)
VALUES ('JPY', '392', 'Японская иена', 0);

INSERT INTO payment_app.currencies (iso_code, iso_num, currency_name, minor_units)
VALUES ('GBP', '826', 'Фунт стерлингов', 2);

-- ─── Типы счетов ────────────────────────────────────────────────────────
INSERT INTO payment_app.account_types (type_code, type_name, description, allows_debit, allows_credit, min_balance)
VALUES ('CURRENT', 'Расчётный счёт', 'Основной текущий счёт для расчётов', 1, 1, 0);

INSERT INTO payment_app.account_types (type_code, type_name, description, allows_debit, allows_credit, min_balance)
VALUES ('DEPOSIT', 'Депозитный счёт', 'Срочный вклад с начислением процентов', 0, 1, 1000);

INSERT INTO payment_app.account_types (type_code, type_name, description, allows_debit, allows_credit, min_balance)
VALUES ('LOAN', 'Ссудный счёт', 'Счёт учёта задолженности по кредиту', 1, 1, 0);

INSERT INTO payment_app.account_types (type_code, type_name, description, allows_debit, allows_credit, min_balance)
VALUES ('TRANSIT', 'Транзитный счёт', 'Счёт для промежуточных операций', 1, 1, 0);

INSERT INTO payment_app.account_types (type_code, type_name, description, allows_debit, allows_credit, min_balance)
VALUES ('ESCROW', 'Эскроу-счёт', 'Условный счёт для сделок', 0, 1, 0);

-- ─── Типы транзакций ────────────────────────────────────────────────────
INSERT INTO payment_app.transaction_types (type_code, type_name, debit_credit, description)
VALUES ('DEPOSIT', 'Пополнение', 'C', 'Зачисление средств на счёт');

INSERT INTO payment_app.transaction_types (type_code, type_name, debit_credit, description)
VALUES ('WITHDRAW', 'Списание', 'D', 'Списание средств со счёта');

INSERT INTO payment_app.transaction_types (type_code, type_name, debit_credit, description)
VALUES ('TRANSFER', 'Перевод', 'B', 'Перевод между счетами');

INSERT INTO payment_app.transaction_types (type_code, type_name, debit_credit, description)
VALUES ('FEE', 'Комиссия', 'D', 'Комиссия банка за операцию');

INSERT INTO payment_app.transaction_types (type_code, type_name, debit_credit, description)
VALUES ('INTEREST', 'Проценты', 'C', 'Начисление процентов по вкладу');

INSERT INTO payment_app.transaction_types (type_code, type_name, debit_credit, description)
VALUES ('REVERSAL', 'Возврат', 'B', 'Отмена/возврат операции');

COMMIT;

BEGIN
    DBMS_OUTPUT.PUT_LINE('Справочники заполнены:');
    DBMS_OUTPUT.PUT_LINE('  Валют: ' || SQL%ROWCOUNT);
    FOR rec IN (SELECT 'currencies' AS t, COUNT(*) AS c FROM payment_app.currencies
                UNION ALL
                SELECT 'account_types', COUNT(*) FROM payment_app.account_types
                UNION ALL
                SELECT 'transaction_types', COUNT(*) FROM payment_app.transaction_types)
    LOOP
        DBMS_OUTPUT.PUT_LINE('  ' || rec.t || ': ' || rec.c || ' записей');
    END LOOP;
END;
/
