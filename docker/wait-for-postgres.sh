#!/usr/bin/env bash
# Aguarda o Postgres responder antes de subir o backend
set -e

HOST="${PG_HOST:-postgres}"
PORT="${PG_PORT:-5432}"

echo ">> aguardando Postgres em $HOST:$PORT ..."
for i in {1..60}; do
  if nc -z "$HOST" "$PORT" 2>/dev/null; then
    echo "✓ Postgres respondeu"
    exec "$@"
  fi
  sleep 1
done

echo "✗ Postgres não respondeu em 60s"
exit 1
