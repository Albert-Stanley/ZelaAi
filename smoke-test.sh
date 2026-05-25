#!/usr/bin/env bash
# ============================================================================
# ZelaAi — Smoke test do backend
#
# Roda o fluxo end-to-end: register -> login -> categories -> politician ->
# mandate -> occurrence (vinculando ao mandato) -> vote -> ranking -> score
# -> unvote. Reporta PASS/FAIL em cada etapa.
#
# Pre-requisitos:
#   - Servidor JA rodando em :5050 (sobe antes com ./zelaai.sh start)
#   - jq instalado (brew install jq) OU python3 instalado
#   - Banco com tabelas vazias eh ideal (./zelaai.sh fresh antes)
#
# Uso: ./smoke-test.sh
# ============================================================================

set -u

BASE="${BASE:-http://localhost:5050}"
PASS=0
FAIL=0
FAILED_STEPS=()

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ---------------------------- helpers ---------------------------------------

# extrai campo JSON usando jq se disponivel, senao python3.
json_get() {
  local body="$1"
  local field="$2"
  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r ".$field // empty"
  else
    echo "$body" | python3 -c "import sys, json
try:
    d = json.load(sys.stdin)
    keys = '$field'.split('.')
    for k in keys: d = d[k] if isinstance(d, dict) else d
    print(d)
except Exception:
    pass"
  fi
}

# req METHOD URL [BODY] [TOKEN]
# imprime "<status>|<body>"
req() {
  local method="$1"
  local url="$2"
  local body="${3:-}"
  local token="${4:-}"

  local headers=(-H "Content-Type: application/json")
  [[ -n "$token" ]] && headers+=(-H "Authorization: Bearer $token")

  if [[ -n "$body" ]]; then
    curl -s -o /tmp/zelaai_body.txt -w "%{http_code}" \
      -X "$method" "$url" "${headers[@]}" -d "$body"
  else
    curl -s -o /tmp/zelaai_body.txt -w "%{http_code}" \
      -X "$method" "$url" "${headers[@]}"
  fi
  echo
  cat /tmp/zelaai_body.txt
}

# expect "label" expected_status method url [body] [token]
# Roda a request e valida que o status bate. Body fica em $LAST_BODY.
expect() {
  local label="$1"
  local expected="$2"
  local method="$3"
  local url="$4"
  local body="${5:-}"
  local token="${6:-}"

  printf "${BLUE}>>${NC} %s ... " "$label"

  local response status
  response=$(req "$method" "$url" "$body" "$token")
  status=$(echo "$response" | head -1)
  LAST_BODY=$(echo "$response" | tail -n +2)

  if [[ "$status" == "$expected" ]]; then
    printf "${GREEN}PASS${NC} (HTTP $status)\n"
    PASS=$((PASS + 1))
  else
    printf "${RED}FAIL${NC} (esperado HTTP $expected, recebido $status)\n"
    printf "    body: %s\n" "$LAST_BODY"
    FAIL=$((FAIL + 1))
    FAILED_STEPS+=("$label")
  fi
}

# ---------------------------- check de pre-reqs -----------------------------

printf "${YELLOW}### Verificando pre-requisitos${NC}\n"
if ! curl -sf "$BASE/" >/dev/null; then
  printf "${RED}servidor nao responde em %s${NC}\n" "$BASE"
  printf "    sobe primeiro: ./zelaai.sh start\n"
  exit 1
fi
printf "${GREEN}servidor OK${NC}\n\n"

# username unico por execucao pra evitar conflito em runs repetidos
SUFFIX=$(date +%s)
USERNAME="albert_$SUFFIX"

# ---------------------------- 1. Health -------------------------------------

printf "${YELLOW}### 1. Health check${NC}\n"
expect "GET /"                       200 GET  "$BASE/"

# ---------------------------- 2. Users --------------------------------------

printf "\n${YELLOW}### 2. Users (register + login)${NC}\n"

expect "POST /users/register"        200 POST "$BASE/users/register" \
  "{\"name\":\"Albert Smoke\",\"username\":\"$USERNAME\",\"password\":\"senha123\",\"cep\":\"01310100\"}"
USER_ID=$(json_get "$LAST_BODY" "userId")
printf "    userId=%s\n" "$USER_ID"

expect "POST /users/register (duplicado)" 400 POST "$BASE/users/register" \
  "{\"name\":\"Outro\",\"username\":\"$USERNAME\",\"password\":\"x\",\"cep\":\"01310100\"}"

expect "POST /users/register (cep invalido)" 400 POST "$BASE/users/register" \
  "{\"name\":\"X\",\"username\":\"never_$SUFFIX\",\"password\":\"y\",\"cep\":\"abc\"}"

expect "POST /users/login (ok)"      200 POST "$BASE/users/login" \
  "{\"loginUsername\":\"$USERNAME\",\"loginPassword\":\"senha123\"}"
TOKEN=$(json_get "$LAST_BODY" "token")
printf "    token=%s...\n" "${TOKEN:0:30}"

expect "POST /users/login (senha errada)" 401 POST "$BASE/users/login" \
  "{\"loginUsername\":\"$USERNAME\",\"loginPassword\":\"errado\"}"

# ---------------------------- 3. Categories ---------------------------------

printf "\n${YELLOW}### 3. Categories${NC}\n"
expect "GET /categories"             200 GET  "$BASE/categories"
CAT_ID=$(json_get "$LAST_BODY" "[0].categoryId")
printf "    categoryId=%s\n" "$CAT_ID"

# ---------------------------- 4. Politician + Mandate -----------------------

printf "\n${YELLOW}### 4. Politician + Mandate${NC}\n"

expect "POST /politicians"           200 POST "$BASE/politicians" \
  "{\"polName\":\"Smoke Test Prefeito\",\"polParty\":\"PST\",\"polRole\":\"prefeito\"}"
POL_ID=$(json_get "$LAST_BODY" "politicianId")
printf "    politicianId=%s\n" "$POL_ID"

expect "POST /politicians (role invalido)" 400 POST "$BASE/politicians" \
  "{\"polName\":\"X\",\"polParty\":\"Y\",\"polRole\":\"vereador\"}"

# pega city/uf do user pra alinhar com o mandato
CITY=$(curl -s "$BASE/users/login" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"loginUsername\":\"$USERNAME\",\"loginPassword\":\"senha123\"}" \
  | (command -v jq >/dev/null && jq -r '.user.userCity' || python3 -c "import sys,json; print(json.load(sys.stdin)['user']['userCity'])"))
UF=$(curl -s "$BASE/users/login" -X POST \
  -H "Content-Type: application/json" \
  -d "{\"loginUsername\":\"$USERNAME\",\"loginPassword\":\"senha123\"}" \
  | (command -v jq >/dev/null && jq -r '.user.userUf' || python3 -c "import sys,json; print(json.load(sys.stdin)['user']['userUf'])"))
printf "    user city/uf: %s / %s\n" "$CITY" "$UF"

expect "POST /mandates"              200 POST "$BASE/mandates" \
  "{\"manPoliticianId\":$POL_ID,\"manCity\":\"$CITY\",\"manUf\":\"$UF\",\"manStartDate\":\"2025-01-01\",\"manEndDate\":\"2028-12-31\"}"
MAN_ID=$(json_get "$LAST_BODY" "mandateId")
printf "    mandateId=%s\n" "$MAN_ID"

expect "POST /mandates (politico inexistente)" 400 POST "$BASE/mandates" \
  "{\"manPoliticianId\":99999,\"manCity\":\"$CITY\",\"manUf\":\"$UF\",\"manStartDate\":\"2025-01-01\",\"manEndDate\":\"2028-12-31\"}"

expect "GET /mandates"               200 GET  "$BASE/mandates"

# ---------------------------- 5. Occurrences --------------------------------

printf "\n${YELLOW}### 5. Occurrences${NC}\n"

expect "POST /occurrences (sem JWT)"  401 POST "$BASE/occurrences" \
  "{\"categoryId\":$CAT_ID,\"title\":\"x\",\"description\":\"y\",\"photoUrl\":\"z\"}"

expect "POST /occurrences"           200 POST "$BASE/occurrences" \
  "{\"categoryId\":$CAT_ID,\"title\":\"Buraco no smoke test\",\"description\":\"E2E\",\"photoUrl\":\"https://x.com/foto.jpg\",\"latitude\":-23.5,\"longitude\":-46.6}" \
  "$TOKEN"
OCC_ID=$(json_get "$LAST_BODY" "occId")
OCC_MANDATE=$(json_get "$LAST_BODY" "occMandateId")
printf "    occId=%s   mandate vinculado=%s\n" "$OCC_ID" "$OCC_MANDATE"

if [[ "$OCC_MANDATE" != "$MAN_ID" ]]; then
  printf "${RED}    AVISO: occurrence nao vinculou ao mandate (esperado $MAN_ID, recebeu $OCC_MANDATE)${NC}\n"
  FAIL=$((FAIL + 1))
  FAILED_STEPS+=("vinculo automatico de mandato")
fi

expect "GET /occurrences"            200 GET  "$BASE/occurrences"
expect "GET /occurrences/$OCC_ID"    200 GET  "$BASE/occurrences/$OCC_ID"
expect "GET /occurrences/99999"      404 GET  "$BASE/occurrences/99999"
expect "GET /occurrences/by-location?cep=01310100" 200 GET "$BASE/occurrences/by-location?cep=01310100"

# ---------------------------- 6. Votes --------------------------------------

printf "\n${YELLOW}### 6. Votes${NC}\n"

expect "POST /occurrences/$OCC_ID/vote (sem JWT)" 401 POST "$BASE/occurrences/$OCC_ID/vote"

expect "POST /occurrences/$OCC_ID/vote"  200 POST "$BASE/occurrences/$OCC_ID/vote" "" "$TOKEN"
COUNT=$(json_get "$LAST_BODY" "voteCount")
if [[ "$COUNT" != "1" ]]; then
  printf "${RED}    AVISO: voteCount esperado=1, recebido=$COUNT${NC}\n"
  FAIL=$((FAIL + 1))
  FAILED_STEPS+=("voteCount apos primeiro voto")
fi

expect "POST /occurrences/$OCC_ID/vote (duplicado)" 409 POST "$BASE/occurrences/$OCC_ID/vote" "" "$TOKEN"

expect "DELETE /occurrences/$OCC_ID/vote" 200 DELETE "$BASE/occurrences/$OCC_ID/vote" "" "$TOKEN"

expect "DELETE /occurrences/$OCC_ID/vote (nao votou)" 404 DELETE "$BASE/occurrences/$OCC_ID/vote" "" "$TOKEN"

# Vota de novo pra ter algo no score
expect "POST /occurrences/$OCC_ID/vote (segundo voto)" 200 POST "$BASE/occurrences/$OCC_ID/vote" "" "$TOKEN"

# ---------------------------- 7. Score --------------------------------------

printf "\n${YELLOW}### 7. Score (termometro de gestao)${NC}\n"

expect "GET /mandates/$MAN_ID/score" 200 GET "$BASE/mandates/$MAN_ID/score"
T=$(json_get "$LAST_BODY" "scoreTotal")
V=$(json_get "$LAST_BODY" "scoreTotalVotes")
printf "    scoreTotal=%s   scoreTotalVotes=%s\n" "$T" "$V"

expect "GET /mandates/99999/score (404)" 404 GET "$BASE/mandates/99999/score"

# ---------------------------- Resumo ----------------------------------------

printf "\n${YELLOW}### Resumo${NC}\n"
TOTAL=$((PASS + FAIL))
printf "Total: %d  |  ${GREEN}PASS: %d${NC}  |  ${RED}FAIL: %d${NC}\n" "$TOTAL" "$PASS" "$FAIL"

if [[ $FAIL -gt 0 ]]; then
  printf "\n${RED}Etapas que falharam:${NC}\n"
  for s in "${FAILED_STEPS[@]}"; do
    printf "  - %s\n" "$s"
  done
  exit 1
fi

printf "\n${GREEN}TUDO VERDE. Backend OK pra seguir pro frontend.${NC}\n"
