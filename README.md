# ZelaAi

> Plataforma colaborativa de zeladoria pública — o **Reclame Aqui da infraestrutura urbana**, com ranking comunitário e **termômetro de gestão** dos políticos.

**TCC — projeto acadêmico**. Stack: **Haskell (Servant + Persistent) · PostgreSQL · JavaScript Vanilla · Leaflet/OSM**.

---

## Sumário

1. [Visão Geral](#visão-geral)
2. [Diferenciais](#diferenciais)
3. [Arquitetura](#arquitetura)
4. [Stack](#stack)
5. [Setup](#setup-rápido)
6. [Subindo o projeto](#subindo-o-projeto)
7. [Demo / seed](#demo--seed)
8. [Endpoints da API](#endpoints-da-api)
9. [Estrutura de pastas](#estrutura-de-pastas)
10. [Documentação completa](#documentação-completa)

---

## Visão Geral

Cidadão reclama de buraco no Twitter, foto some, ninguém cobra ninguém. O **ZelaAi** resolve isso: estrutura os relatos, ranqueia por votos, e — diferente de qualquer canal oficial — cruza ocorrências com os mandatos políticos vigentes para produzir um **score transparente de cada gestão**.

- **Feed público** (qualquer pessoa lê, vê no mapa, busca por CEP/cidade/título)
- **Login simples** (Nome + Username + Senha + CEP → cidade/UF puxadas via ViaCEP)
- **Reportar ocorrência**: foto, descrição, categoria e geolocalização
- **Votar / desvotar** (1 voto por usuário por ocorrência)
- **Alterar status** (`open → in_progress → resolved`)
- **Termômetro de Gestão**: por mandato, mostra % resolvido, votos totais e tempo médio de resolução

---

## Diferenciais

- **Acesso híbrido** — leitura aberta + escrita autenticada. Maximiza tráfego e participação sem barreira inicial.
- **Vinculação automática a mandato** — quando uma ocorrência é criada, o backend identifica qual mandato está vigente na cidade/UF do CEP e cria a ligação `occurrence → mandate`.
- **Score por mandato** — agregação SQL que calcula:
  - total reportado
  - total resolvido
  - % resolvido
  - tempo médio (em dias) para resolver
  - votos totais recebidos
- **Backend funcional em Haskell** com camadas bem separadas (clean-ish architecture: Presentation → UseCase → Repository → InterfaceAdapters), demonstrando domínio de tipos e composição funcional para regras de negócio.

---

## Arquitetura

```
┌──────────────────────┐         HTTP / JSON          ┌──────────────────────┐
│   Frontend (Vanilla) │  ────────────────────────►   │  Backend Haskell      │
│   index/login/...    │   Bearer JWT (Authorization) │  Servant + Warp :5050 │
│   Leaflet + OSM map  │  ◄────────────────────────   │                       │
└──────────────────────┘                              │   ┌────────────────┐  │
                                                      │   │ Presentation   │  │
                                                      │   │ Controllers /  │  │
                                                      │   │ Auth / Errors  │  │
                                                      │   └───────┬────────┘  │
                                                      │           │            │
                                                      │   ┌───────▼────────┐  │
                                                      │   │ UseCases       │  │
                                                      │   │ User / Occ /   │  │
                                                      │   │ Vote / Score   │  │
                                                      │   └───────┬────────┘  │
                                                      │           │            │
                                                      │   ┌───────▼────────┐  │
                                                      │   │ Repository     │  │
                                                      │   │ (Persistent)   │  │
                                                      │   └───────┬────────┘  │
                                                      │           │            │
                                                      │  ┌────────▼─────────┐ │
                                                      │  │  PostgreSQL :5432│ │
                                                      │  └──────────────────┘ │
                                                      └───────────────────────┘
                                                                  ▲
                                                                  │
                                       ViaCEP   ─────────────────► (HTTP client)
```

### Entidades

```
User ─────┐
          │ 1..N
          ▼
       Occurrence ──► Category
          │
          │ N..1
          ▼
       Mandate ──► Politician
          ▲
          │
   Vote ──┘ (N..M user × occurrence)
```

Diagrama completo, atributos, casos de uso e regras: ver **[DOCS.md](./DOCS.md)**.

---

## Stack

| Camada       | Tecnologia                                                   |
|--------------|--------------------------------------------------------------|
| Backend      | Haskell (GHC 9.6) · Servant · Warp · Persistent · Aeson      |
| Auth         | JWT (HS256) · bcrypt (slower policy)                         |
| Banco        | PostgreSQL 15+                                               |
| API externa  | ViaCEP (preencher cidade/UF a partir do CEP)                 |
| Frontend     | Vanilla JS (modules) · Leaflet/OSM · CSS mobile-first        |
| Container    | Docker + docker-compose (opcional)                           |

---

## Setup Rápido

### Pré-requisitos

- **Haskell**: `GHCup` com GHC 9.6+ e `cabal` 3.10+
- **PostgreSQL** 15+ rodando local na porta `5432`
- **jq** (para os scripts) — `brew install jq`
- (opcional) **Docker** + **docker-compose**
- Um servidor estático para o front (qualquer um serve — `python3 -m http.server 8080` em `front/`)

### Variáveis de ambiente (opcionais)

| Variável        | Default                                                                            |
|-----------------|------------------------------------------------------------------------------------|
| `DATABASE_URL`  | `host=localhost port=5432 user=postgres dbname=postgres password=root`             |
| `JWT_SECRET`    | `zelaai_dev_secret`                                                                |

> Em produção, **sempre** redefina `JWT_SECRET`.

---

## Subindo o projeto

### Modo manual (dev local)

```bash
# 1. Garanta o Postgres rodando local na 5432
# 2. Build + start do backend
./zelaai.sh start

# 3. Em outro terminal, sirva o front
cd front
python3 -m http.server 8080

# 4. Acesse
open http://localhost:8080/index.html
```

### Comandos do `zelaai.sh`

```bash
./zelaai.sh start       # cabal build + cabal run, sobe a :5050
./zelaai.sh build       # só compila
./zelaai.sh stop        # mata o processo na :5050
./zelaai.sh reset-db    # drop + create do schema (cuidado!)
./zelaai.sh fresh       # reset-db + start
./zelaai.sh logs-db     # follow do log do postgres
./zelaai.sh help
```

### Docker (alternativa)

```bash
docker-compose up --build
# backend  → http://localhost:5050
# front    → http://localhost:8080
# postgres → localhost:5432
```

---

## Demo / seed

Após o backend estar rodando, popule dados de demo num clique:

```bash
./seed-demo.sh
```

Cria:

- 1 user demo (`demo_<timestamp>` / senha `demo1234`)
- 1 prefeito + 1 governador
- 2 mandatos vigentes (prefeitura SP + governo SP)
- 4 ocorrências (2 abertas, 1 em andamento, 1 resolvida)
- voto da demo na primeira ocorrência

No final ele imprime user/senha pra você logar no front.

Para testar tudo de uma vez (todos os endpoints):

```bash
./smoke-test.sh
```

Output esperado: `Total: 26 | PASS: 26 | FAIL: 0`.

---

## Endpoints da API

Base: `http://localhost:5050`

| Método   | Rota                                | Auth | Descrição                                       |
|----------|-------------------------------------|------|-------------------------------------------------|
| `GET`    | `/`                                 | —    | Healthcheck                                     |
| `POST`   | `/users/register`                   | —    | Cadastro (preenche cidade/UF via ViaCEP)        |
| `POST`   | `/users/login`                      | —    | Login, retorna JWT                              |
| `GET`    | `/categories`                       | —    | Lista categorias (seed automático)              |
| `POST`   | `/politicians`                      | —    | Cria político                                   |
| `GET`    | `/politicians`                      | —    | Lista políticos                                 |
| `POST`   | `/mandates`                         | —    | Cria mandato                                    |
| `GET`    | `/mandates`                         | —    | Lista mandatos com político embutido            |
| `GET`    | `/mandates/{id}/score`              | —    | Score completo do mandato (termômetro)          |
| `GET`    | `/occurrences`                      | —    | Lista pública (ordem: votos desc, depois data)  |
| `GET`    | `/occurrences/{id}`                 | —    | Detalhe de uma ocorrência                       |
| `POST`   | `/occurrences`                      | ✅   | Cria ocorrência (vincula ao mandato vigente)    |
| `PATCH`  | `/occurrences/{id}/status`          | ✅   | Atualiza status (`open` / `in_progress` / `resolved`) |
| `POST`   | `/occurrences/{id}/vote`            | ✅   | Vota                                            |
| `DELETE` | `/occurrences/{id}/vote`            | ✅   | Tira voto                                       |
| `GET`    | `/users/me/occurrences`             | ✅   | Lista as minhas ocorrências (do usuário do JWT) |

Header de auth para rotas protegidas:

```
Authorization: Bearer <token>
```

---

## Estrutura de pastas

```
ZelaAi/
├── app/                        # Main.hs (entrypoint)
├── src/
│   ├── MyLib.hs                # bootstrap (CORS, Warp, migrations, seed)
│   ├── Api.hs                  # tipo Servant da API
│   ├── Db.hs                   # pool de conexões
│   ├── Presentation/
│   │   ├── Controllers.hs      # handlers Servant
│   │   ├── Auth.hs             # parsing do header Authorization
│   │   ├── Errors.hs           # erros de domínio → erros HTTP
│   │   └── Responses.hs        # DTOs de resposta
│   ├── UseCase/
│   │   ├── UserCase.hs         # register + login (ViaCEP + bcrypt + JWT)
│   │   ├── CategoryCase.hs
│   │   ├── PoliticianCase.hs
│   │   ├── MandateCase.hs
│   │   ├── OccurrenceCase.hs   # criar / listar / mudar status / minhas
│   │   ├── VoteCase.hs
│   │   └── ScoreCase.hs        # termômetro de gestão
│   ├── Repository/
│   │   └── Entities.hs         # esquema Persistent
│   ├── Dto/                    # DTOs de entrada
│   └── InterfaceAdapters/
│       ├── Libs.hs             # JWT + bcrypt + UUID
│       └── Apis.hs             # cliente ViaCEP
├── front/
│   ├── index.html              # Feed público + mapa + criar
│   ├── login.html              # Login / cadastro com tabs
│   ├── occurrence.html         # Detalhe + voto + status
│   ├── mandates.html           # Termômetro de gestão
│   ├── my.html                 # Minhas ocorrências
│   ├── css/style.css           # design system mobile-first
│   └── js/                     # módulos: api, auth, feed, occurrence, mandates, my, login
├── zelaai.sh                   # script de gestão (start/stop/reset/fresh)
├── seed-demo.sh                # popular dados de demo via API
├── smoke-test.sh               # 26 testes E2E dos endpoints
├── Dockerfile                  # build multi-stage do backend
├── docker-compose.yml          # backend + front + postgres
├── DOCS.md                     # documentação detalhada (escopo, diagramas, regras)
├── CHANGELOG.md
└── ZelaAi.cabal
```

---

## Documentação completa

- **[DOCS.md](./DOCS.md)** — escopo, problema, solução, diagramas (ER e casos de uso), atributos e regras de negócio
- **[front/README.md](./front/README.md)** — guia do frontend
- **[CHANGELOG.md](./CHANGELOG.md)** — histórico de mudanças

---

## Créditos

Projeto de TCC desenvolvido por **Albert Stanley**.

Inspirado na arquitetura do TCC em Go de Lorenzo (mesma faculdade), portado para Haskell mantendo a separação de camadas e adicionando o **Termômetro de Gestão** como diferencial.

---

## Licença

MIT — ver [LICENSE](./LICENSE).
