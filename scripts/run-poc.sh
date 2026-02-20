#!/bin/bash
###############################################################################
# run-poc.sh — Главный скрипт запуска PoC
# Выполнять с хост-машины (не из контейнера)
###############################################################################
set -euo pipefail

COMPOSE="docker compose"
SQITCH="$COMPOSE exec sqitch sqitch"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

###############################################################################
log "═══════════════════════════════════════════════════════════════════"
log "   Sqitch + Oracle 11g — Proof of Concept"
log "═══════════════════════════════════════════════════════════════════"

# ─── Шаг 1: Запуск инфраструктуры ────────────────────────────────────────
log ""
log "Шаг 1: Запуск Oracle 11g и сборка Sqitch-образа..."
$COMPOSE up -d --build

log "Ожидание готовности Oracle (может занять 1-3 минуты)..."
$COMPOSE exec sqitch bash -c '
    for i in $(seq 1 60); do
        if echo "SELECT 1 FROM DUAL;" | sqlplus -S payment_app/PayApp2025@//oracle-db:1521/XE 2>/dev/null | grep -q "1"; then
            echo "Oracle готов!"
            exit 0
        fi
        echo "Ожидание... ($i/60)"
        sleep 5
    done
    echo "TIMEOUT: Oracle не готов"
    exit 1
'
ok "Oracle 11g запущен и доступен"

# ─── Шаг 2: Статус до деплоя ─────────────────────────────────────────────
log ""
log "Шаг 2: Проверка sqitch status (до деплоя)..."
$SQITCH status || true
echo ""

# ─── Шаг 3: Полный деплой ────────────────────────────────────────────────
log ""
log "Шаг 3: DEPLOY — применение всех 14 миграций..."
log "Sqitch разрешит DAG-зависимости автоматически:"
log "  • DIAMOND: accounts ← (customers + account_types)"
log "  • WIDE:    transactions ← (accounts + currencies + transaction_types)"
log "  • CROSS:   daily_processing ← (payments_pkg + exchange_rates)"
log "  • DEEP:    seed_test_data ← 6 уровней вложенности"
echo ""
$SQITCH deploy -vvv

ok "Все 14 миграций успешно применены"

# ─── Шаг 4: Верификация ──────────────────────────────────────────────────
log ""
log "Шаг 4: VERIFY — проверка корректности всех миграций..."
$SQITCH verify

ok "Все verify-скрипты прошли успешно"

# ─── Шаг 5: Статус после деплоя ──────────────────────────────────────────
log ""
log "Шаг 5: Полный статус sqitch..."
$SQITCH status
echo ""
$SQITCH log --format format:%h' '%n' [%t]' | head -20

# ─── Шаг 6: Тест отката ──────────────────────────────────────────────────
log ""
log "Шаг 6: REVERT — тестируем откат 3 последних миграций..."
$SQITCH revert --to daily_processing -y
ok "Откат seed_test_data и seed_reference_data выполнен"

log ""
log "Повторный деплой откачённых миграций..."
$SQITCH deploy
ok "Повторный деплой успешен — идемпотентность работает!"

# ─── Шаг 7: Проверка данных ──────────────────────────────────────────────
log ""
log "Шаг 7: Проверка данных в Oracle..."
$COMPOSE exec sqitch bash -c '
echo "
SET LINESIZE 120
SET PAGESIZE 50

PROMPT === Объекты в схеме payment_app ===
SELECT object_type, COUNT(*) as cnt
  FROM user_objects
 WHERE status = '\''VALID'\''
 GROUP BY object_type
 ORDER BY 1;

PROMPT === Таблицы с данными ===
SELECT table_name, num_rows
  FROM user_tables
 ORDER BY table_name;

PROMPT === Валидные PL/SQL пакеты ===
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type LIKE '\''PACKAGE%'\''
 ORDER BY object_name, object_type;

PROMPT === Баланс счетов ===
SELECT a.account_id, a.account_number, c.last_name, a.balance, a.currency_code
  FROM accounts a
  JOIN customers c ON c.customer_id = a.customer_id
 ORDER BY a.account_id;

EXIT;
" | sqlplus -S payment_app/PayApp2025@//oracle-db:1521/XE
'

# ─── Итоги ────────────────────────────────────────────────────────────────
log ""
log "═══════════════════════════════════════════════════════════════════"
ok "PoC ЗАВЕРШЁН УСПЕШНО"
log ""
log "Что было продемонстрировано:"
log "  1. Sqitch корректно разрешает DAG-зависимости (14 миграций)"
log "  2. PL/SQL пакеты Oracle 11g развёрнуты без ошибок"
log "  3. SQL*Plus-специфичные команды работают (set, show errors, /)"
log "  4. Deploy/Verify/Revert цикл работает"
log "  5. Compound triggers, BULK COLLECT, SYS_REFCURSOR — всё ОК"
log ""
log "Команды для дальнейшей работы:"
log "  $COMPOSE exec sqitch sqitch status        # Статус"
log "  $COMPOSE exec sqitch sqitch log            # Лог изменений"
log "  $COMPOSE exec sqitch sqitch revert -y      # Откатить всё"
log "  $COMPOSE exec sqitch sqitch deploy         # Применить всё"
log "  $COMPOSE down                              # Остановить"
log "═══════════════════════════════════════════════════════════════════"
