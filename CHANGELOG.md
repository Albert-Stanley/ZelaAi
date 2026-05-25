# Changelog — ZelaAi

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.1.0] — 2026-05-25

Versão inicial do TCC.

### Adicionado
- **Backend Haskell** (Servant + Persistent + Warp na :5050) em camadas:
  Presentation → UseCase → Repository → InterfaceAdapters.
- **Entidades** com Persistent TH: User, Category, Politician, Mandate, Occurrence, Vote.
- **Auth**: JWT (HS256, expira em 24h) + bcrypt (slower policy).
- **Integração ViaCEP** para preencher cidade/UF a partir do CEP no cadastro.
- **Vinculação automática a mandato**: ao criar uma ocorrência, o backend
  identifica o mandato vigente na cidade/UF e grava a relação.
- **Endpoints REST** (16+): users, categories, politicians, mandates,
  occurrences (com `PATCH /:id/status`), votes, `GET /users/me/occurrences`,
  `GET /mandates/:id/score`.
- **CORS** habilitado para o front.
- **Frontend** Vanilla JS mobile-first:
  - Feed público com mapa Leaflet (tiles CARTO Voyager) e busca client-side.
  - Login / Cadastro com tabs.
  - Detalhe da ocorrência com voto e alteração de status.
  - Página **Termômetro de Gestão** (score por mandato com termômetro animado).
  - Página **Minhas ocorrências**.
- **Design system** moderno: Inter + Plus Jakarta Sans, paleta verde refinada,
  sombras em camadas, ícones SVG inline, skeleton loaders, microinterações.
- **Scripts** utilitários: `zelaai.sh` (start/build/reset/fresh),
  `seed-demo.sh` (popula dados de demo via API), `smoke-test.sh`
  (26 testes E2E dos endpoints — 26/26 PASS).
- **Docker**: Dockerfile multi-stage (Haskell 9.6 → Debian slim) +
  `docker-compose.yml` orquestrando postgres + backend + nginx (front).
- **Makefile** com atalhos (`make start`, `make docker-up`, `make seed`, etc).
- **Docs**: README raiz, DOCS.md (escopo, diagramas, regras),
  front/README.md (guia do front), .env.example.
