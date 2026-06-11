#!/usr/bin/env bash
# Aguarda o Postgres responder antes de subir o backend.
# Funciona em dois cenários:
#   - docker-compose local: host fixo "postgres" (via PG_HOST/PG_PORT)
#   - Render: deriva host/porta da DATABASE_URL (formato URL postgresql://...)
# Se não conseguir confirmar em 60s, inicia mesmo assim (o app tenta conectar
# e o Render reinicia caso falhe) — evita crash-loop por nc bloqueado.
set -e

HOST="${PG_HOST:-}"
PORT="${PG_PORT:-}"

# Se PG_HOST não foi passado explicitamente, tenta extrair da DATABASE_URL.
if [ -z "$HOST" ] && [ -n "$DATABASE_URL" ]; then
  case "$DATABASE_URL" in
    postgres://*|postgresql://*)
      # postgresql://user:pass@host:port/db -> isola "host:port"
      hostport="${DATABASE_URL#*@}"   # remove "scheme://user:pass@"
      hostport="${hostport%%/*}"      # remove "/db?params"
      HOST="${hostport%%:*}"
      case "$hostport" in
        *:*) PORT="${hostport##*:}" ;;
      esac
      ;;
    *)
      # formato libpq "key=value ...": extrai host= e port=
      for kv in $DATABASE_URL; do
        case "$kv" in
          host=*) HOST="${kv#host=}" ;;
          port=*) PORT="${kv#port=}" ;;
        esac
      done
      ;;
  esac
fi

HOST="${HOST:-postgres}"
PORT="${PORT:-5432}"

echo ">> aguardando Postgres em $HOST:$PORT ..."
for _ in $(seq 1 60); do
  if nc -z "$HOST" "$PORT" 2>/dev/null; then
    echo "✓ Postgres respondeu"
    exec "$@"
  fi
  sleep 1
done

echo "✗ Postgres não confirmou em 60s — iniciando o app mesmo assim"
exec "$@"
