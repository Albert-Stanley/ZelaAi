#!/usr/bin/env bash
# ============================================================================
# ZelaAi — seed de dados de demonstração via API
#
# Cria:
#   - 1 user demo
#   - 1 prefeito + 1 governador (politicians)
#   - 2 mandatos (prefeito SP, governador SP)
#   - 4 ocorrencias de exemplo (2 abertas, 1 em_andamento, 1 resolvida)
#   - votos espalhados
#
# Pre-requisitos:
#   - Servidor rodando em :5050
#   - jq (brew install jq)
#
# Uso:
#   ./seed-demo.sh                  # usa defaults
#   ./seed-demo.sh --reset          # antes de seed, dropa banco e re-sobe
# ============================================================================

set -e

BASE="${BASE:-http://localhost:5050}"
DEMO_CEP="${DEMO_CEP:-01310100}"        # Av. Paulista
DEMO_USER="demo_$(date +%s)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'
log()  { printf "${BLUE}>>${NC} %s\n" "$*"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$*"; }
err()  { printf "${RED}✗${NC} %s\n" "$*" >&2; }

# ---------- helpers
post() {
  local path="$1"; local body="$2"; local token="${3:-}"
  local extra=()
  [[ -n "$token" ]] && extra=(-H "Authorization: Bearer $token")
  curl -sf -X POST "$BASE$path" \
    -H "Content-Type: application/json" \
    "${extra[@]}" \
    -d "$body"
}

patch() {
  local path="$1"; local body="$2"; local token="$3"
  curl -sf -X PATCH "$BASE$path" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -d "$body"
}

require_jq() {
  if ! command -v jq >/dev/null; then
    err "jq nao encontrado. Instala: brew install jq"
    exit 1
  fi
}
require_jq

# ---------- reset opcional
if [[ "${1:-}" == "--reset" ]]; then
  log "rodando ./zelaai.sh fresh em background"
  ./zelaai.sh stop 2>/dev/null || true
  ./zelaai.sh reset-db
  ./zelaai.sh start &
  log "esperando servidor subir..."
  for i in {1..20}; do
    if curl -sf "$BASE/" >/dev/null; then break; fi
    sleep 1
  done
fi

# ---------- check servidor
if ! curl -sf "$BASE/" >/dev/null; then
  err "servidor offline em $BASE"
  exit 1
fi
ok "servidor OK em $BASE"

# ---------- 1. user demo
log "criando user demo..."
USER_RESP=$(post /users/register "{
  \"name\": \"Demo User\",
  \"username\": \"$DEMO_USER\",
  \"password\": \"demo1234\",
  \"cep\": \"$DEMO_CEP\"
}")
USER_ID=$(echo "$USER_RESP" | jq -r '.userId')
CITY=$(echo "$USER_RESP" | jq -r '.userCity')
UF=$(echo "$USER_RESP" | jq -r '.userUf')
ok "user $DEMO_USER criado (id=$USER_ID, $CITY/$UF)"

# ---------- 2. login
LOGIN_RESP=$(post /users/login "{
  \"loginUsername\": \"$DEMO_USER\",
  \"loginPassword\": \"demo1234\"
}")
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.token')
ok "login ok, token guardado"

# ---------- 3. politicos
log "criando políticos..."
PREF_ID=$(post /politicians '{
  "polName": "Maria Silva",
  "polParty": "PCS",
  "polRole": "prefeito"
}' | jq -r '.politicianId')
ok "prefeito Maria Silva (id=$PREF_ID)"

GOV_ID=$(post /politicians '{
  "polName": "João Oliveira",
  "polParty": "PVD",
  "polRole": "governador"
}' | jq -r '.politicianId')
ok "governador João Oliveira (id=$GOV_ID)"

# ---------- 4. mandatos
log "criando mandatos..."
PREF_MAND=$(post /mandates "{
  \"manPoliticianId\": $PREF_ID,
  \"manCity\": \"$CITY\",
  \"manUf\": \"$UF\",
  \"manStartDate\": \"2025-01-01\",
  \"manEndDate\": \"2028-12-31\"
}" | jq -r '.mandateId')
ok "mandato prefeito (id=$PREF_MAND)"

GOV_MAND=$(post /mandates "{
  \"manPoliticianId\": $GOV_ID,
  \"manCity\": \"\",
  \"manUf\": \"$UF\",
  \"manStartDate\": \"2023-01-01\",
  \"manEndDate\": \"2026-12-31\"
}" | jq -r '.mandateId')
ok "mandato governador (id=$GOV_MAND)"

# ---------- 5. categorias (ja existem por seed automatico)
CAT_BURACO=$(curl -s "$BASE/categories" | jq -r '.[] | select(.categoryName=="Buraco") | .categoryId')
CAT_LUZ=$(curl -s "$BASE/categories" | jq -r '.[] | select(.categoryName=="Iluminacao") | .categoryId')
CAT_LIXO=$(curl -s "$BASE/categories" | jq -r '.[] | select(.categoryName=="Lixo") | .categoryId')

# ---------- 6. ocorrencias
log "criando ocorrências..."
OCC1=$(post /occurrences "{
  \"categoryId\": $CAT_BURACO,
  \"title\": \"Buraco gigante na Av. Paulista\",
  \"description\": \"Buraco fundo na altura do MASP. Já danificou pneus de carros.\",
  \"photoUrl\": \"https://picsum.photos/seed/1/600/400\",
  \"latitude\": -23.5613,
  \"longitude\": -46.6565
}" "$TOKEN" | jq -r '.occId')
ok "ocorrência aberta: Buraco Paulista (id=$OCC1)"

OCC2=$(post /occurrences "{
  \"categoryId\": $CAT_LUZ,
  \"title\": \"Poste apagado há 3 semanas\",
  \"description\": \"Rua escura, perigosa pra quem volta do trabalho.\",
  \"photoUrl\": \"https://picsum.photos/seed/2/600/400\",
  \"latitude\": -23.5400,
  \"longitude\": -46.6300
}" "$TOKEN" | jq -r '.occId')
ok "ocorrência aberta: Poste apagado (id=$OCC2)"

OCC3=$(post /occurrences "{
  \"categoryId\": $CAT_LIXO,
  \"title\": \"Lixo acumulado na praça\",
  \"description\": \"Caçamba sem coleta há dias. Atraindo ratos.\",
  \"photoUrl\": \"https://picsum.photos/seed/3/600/400\",
  \"latitude\": -23.5500,
  \"longitude\": -46.6400
}" "$TOKEN" | jq -r '.occId')
ok "ocorrência: Lixo praça (id=$OCC3)"

OCC4=$(post /occurrences "{
  \"categoryId\": $CAT_BURACO,
  \"title\": \"Calçada quebrada antiga\",
  \"description\": \"Calçada destruída em frente à escola. Reparada após meses.\",
  \"photoUrl\": \"https://picsum.photos/seed/4/600/400\",
  \"latitude\": -23.5700,
  \"longitude\": -46.6500
}" "$TOKEN" | jq -r '.occId')
ok "ocorrência: Calçada quebrada (id=$OCC4)"

# ---------- 7. mudar status
log "ajustando status das ocorrências..."
patch "/occurrences/$OCC3/status" '{"newStatus": "in_progress"}' "$TOKEN" > /dev/null
ok "OCC $OCC3 em andamento"
patch "/occurrences/$OCC4/status" '{"newStatus": "resolved"}' "$TOKEN" > /dev/null
ok "OCC $OCC4 resolvida"

# ---------- 8. votos
log "registrando voto do demo na OCC1..."
post "/occurrences/$OCC1/vote" "" "$TOKEN" > /dev/null
ok "voto registrado"

# ---------- resumo
echo
printf "${GREEN}=== SEED COMPLETO ===${NC}\n"
echo "User demo:        $DEMO_USER / senha: demo1234"
echo "City/UF:          $CITY / $UF"
echo "Prefeito:         id=$PREF_ID  Mandato=$PREF_MAND"
echo "Governador:       id=$GOV_ID   Mandato=$GOV_MAND"
echo "Ocorrências:      $OCC1, $OCC2, $OCC3 (em_andamento), $OCC4 (resolved)"
echo "Token (24h):      ${TOKEN:0:40}..."
echo
echo "Acesse:"
echo "  Feed:        http://localhost:8080/index.html"
echo "  Termômetro:  http://localhost:8080/mandates.html"
echo "  Login:       http://localhost:8080/login.html  (usa $DEMO_USER / demo1234)"
