#!/usr/bin/env bash
# ============================================================================
# ZelaAi — script de gerenciamento do projeto
#
# Uso:
#   ./zelaai.sh start       Sobe o servidor (mata instancia anterior se houver)
#   ./zelaai.sh build       cabal build
#   ./zelaai.sh reset-db    Dropa TODAS as tabelas (proximo start recria)
#   ./zelaai.sh fresh       reset-db + build + start (do zero, util pra dev)
#   ./zelaai.sh stop        Mata o servidor se estiver rodando
#   ./zelaai.sh logs-db     Conecta ao psql do banco (pra inspecionar)
#   ./zelaai.sh help        Mostra esta ajuda
#
# Variaveis de ambiente (com defaults):
#   PG_HOST=localhost  PG_PORT=5432  PG_USER=postgres
#   PG_DB=postgres     PG_PASS=root  APP_PORT=5050
# ============================================================================

set -e

# ----------------------------- Configuracao ---------------------------------
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-postgres}"
PG_DB="${PG_DB:-postgres}"
PG_PASS="${PG_PASS:-root}"
APP_PORT="${APP_PORT:-5050}"

# ----------------------------- Helpers UI -----------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { printf "${GREEN}[zelaai]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[zelaai]${NC} %s\n" "$*"; }
err()  { printf "${RED}[zelaai]${NC} %s\n" "$*" >&2; }
step() { printf "${BLUE}>>${NC} %s\n" "$*"; }

# ----------------------------- Comandos -------------------------------------

kill_server() {
  local pid
  pid=$(lsof -ti :"$APP_PORT" 2>/dev/null || true)
  if [[ -n "$pid" ]]; then
    warn "matando processo em :$APP_PORT (pid $pid)"
    kill "$pid" || true
    sleep 1
    # se ainda vivo, mata forcado
    if kill -0 "$pid" 2>/dev/null; then
      warn "forcando kill -9"
      kill -9 "$pid" || true
    fi
  else
    log "nenhum servidor rodando em :$APP_PORT"
  fi
}

reset_db() {
  step "dropando tabelas em $PG_DB ($PG_HOST:$PG_PORT)"
  PGPASSWORD="$PG_PASS" psql \
    -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB" \
    -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS vote        CASCADE;
DROP TABLE IF EXISTS occurrence  CASCADE;
DROP TABLE IF EXISTS mandate     CASCADE;
DROP TABLE IF EXISTS politician  CASCADE;
DROP TABLE IF EXISTS category    CASCADE;
DROP TABLE IF EXISTS "user"      CASCADE;
SQL
  log "tabelas dropadas. Proximo start vai recria-las via migration + seed."
}

build_app() {
  step "cabal build"
  cabal build
  log "build ok"
}

start_app() {
  kill_server
  step "iniciando servidor em http://localhost:$APP_PORT"
  log "ctrl-c pra parar"
  cabal run ZelaAi
}

logs_db() {
  step "conectando ao psql ($PG_DB em $PG_HOST:$PG_PORT)"
  PGPASSWORD="$PG_PASS" psql \
    -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DB"
}

show_help() {
  cat <<EOF
ZelaAi - script de gerenciamento

Uso: ./zelaai.sh <comando>

Comandos:
  start       Sobe o servidor (mata instancia anterior se houver)
  build       cabal build
  reset-db    Dropa TODAS as tabelas. Proximo start recria via migration.
  fresh       reset-db + build + start (do zero - util pra dev)
  stop        Mata o servidor se estiver rodando em :$APP_PORT
  logs-db     Abre o psql conectado ao banco do projeto
  help        Mostra esta ajuda

Variaveis de ambiente (defaults entre parenteses):
  PG_HOST     ($PG_HOST)
  PG_PORT     ($PG_PORT)
  PG_USER     ($PG_USER)
  PG_DB       ($PG_DB)
  PG_PASS     ($PG_PASS)
  APP_PORT    ($APP_PORT)

Exemplos:
  ./zelaai.sh fresh                  # zera tudo e sobe
  ./zelaai.sh start                  # so restart
  PG_DB=zela ./zelaai.sh reset-db    # com outro DB
EOF
}

# ----------------------------- Dispatcher -----------------------------------

case "${1:-help}" in
  start)     start_app ;;
  build)     build_app ;;
  reset-db)  kill_server; reset_db ;;
  fresh)     kill_server; reset_db; build_app; start_app ;;
  stop)      kill_server ;;
  logs-db)   logs_db ;;
  help|-h|--help) show_help ;;
  *)
    err "comando desconhecido: $1"
    show_help
    exit 1
    ;;
esac
