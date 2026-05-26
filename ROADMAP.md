# ZelaAi — Roadmap de Melhorias

Documento de varredura do projeto com sugestões de **incrementos**, **novas features** e **refatorações**. Organizado por camada e prioridade.

Legenda de prioridade: 🔴 crítico · 🟡 importante · 🟢 nice-to-have

---

## 1. Segurança & Auth 🔴

### 1.1 Secret de JWT em produção 🔴
- Arquivo: `src/InterfaceAdapters/Libs.hs:27`
- Hoje: `jwtSecret = ... fromMaybe "zelaai_dev_secret"` — se a env var não estiver setada, sobe com um secret público e previsível.
- **Ação:** fazer `fail` no boot quando `JWT_SECRET` ausente em produção (`ENV=production`). Em dev pode manter fallback, mas com warning no log.

### 1.2 Refresh tokens / sessão longa 🟡
- JWT expira em 24h (`Libs.hs:49`) e força re-login. Faltam **refresh tokens** ou *sliding sessions*.
- **Ação:** adicionar endpoint `POST /auth/refresh` e armazenar refresh tokens no DB com revocation.

### 1.3 Rate limiting & brute-force 🔴
- Não há rate limit em `/users/login`, `/users/register`, `POST /occurrences/:id/vote` nem em `/comments`.
- **Ação:** middleware WAI de rate limiting (`wai-extra` ou Redis). Mínimo: 5 tentativas/min/IP no login.

### 1.4 Validação de inputs 🟡
- `Validation/*.hs` está mínimo (25–33 linhas). Faltam regras para:
  - Tamanho mínimo de senha (hoje aceita 1 char?).
  - Sanitização de URL de foto (`photoUrl`) — qualquer URL passa, inclusive `javascript:`.
  - Tamanho máximo de `description` e `title` no backend (front limita, mas backend deve replicar).
- **Ação:** centralizar regras de tamanho em `Validation/Common.hs` e validar todas as DTOs.

### 1.5 CORS muito aberto 🟡
- `wai-cors` configurado por env (`README.md`). Verificar se está em `*` em produção.
- **Ação:** lista de domínios explícita via `CORS_ORIGINS=https://zelaai.app,https://www.zelaai.app`.

### 1.6 Headers de segurança no front 🟡
- Faltam `Content-Security-Policy`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`.
- **Ação:** adicionar via `docker/nginx.conf` e via `<meta http-equiv>` no HTML.

### 1.7 XSS no front 🟡
- `front/js/*.js` tem **62 usos de `innerHTML`**. Há `escapeHtml`, mas é fácil esquecer.
- **Ação:** padronizar todo rendering em uma função `el(tag, attrs, children)` ou usar `<template>` + `cloneNode` para conteúdo dinâmico.

---

## 2. Backend (Haskell) 🟡

### 2.1 Zero testes automatizados 🔴
- `ZelaAi.cabal` não declara `test-suite`. Não há `tests/`, `*Spec.hs`.
- **Ação:** adicionar `hspec` + `hspec-wai` cobrindo no mínimo:
  - login / register feliz e infeliz.
  - vote dedup (`UniqueUserOccurrence`).
  - score de mandato.
  - autorização (token inválido → 401).

### 2.2 N+1 nos listings 🟡
- `listOccurrences` provavelmente carrega occurrences e depois itera buscando categoria/usuário (padrão de `Persistent` ingênuo).
- **Ação:** auditar `UseCase/OccurrenceCase.hs` com `selectList` em batch ou `esqueleto` para JOIN.

### 2.3 Paginação ausente 🔴
- `/occurrences`, `/comments`, `/users/me/occurrences` retornam **tudo**. Quando a base crescer, vai estourar memória/rede.
- **Ação:** `?page=N&pageSize=M` com cursor (id DESC) ou offset. Front já tem skeleton — só ligar o "carregar mais".

### 2.4 Soft-delete inconsistente 🟡
- `Occurrence.deletedAt` existe mas precisa filtrar em **toda** query. Fácil esquecer.
- **Ação:** wrapper `selectActive` em `Repository/Generic.hs` que injeta `deletedAt = NULL`.

### 2.5 Logs estruturados 🟢
- `InterfaceAdapters/Logs.hs` provavelmente é `putStrLn`.
- **Ação:** `katip` ou `co-log` com JSON em produção, level configurável por env.

### 2.6 Health check mais rico 🟢
- Hoje pinga DB. Adicionar:
  - latência do DB.
  - versão do build (commit hash via `git rev-parse` em build time).
  - tempo de uptime.

### 2.7 Migrations versionadas 🟡
- `migrateAll` (Persistent TH) faz auto-migration no boot. Não há histórico de migrations.
- **Ação:** migrar para `dbmate` ou `flyway`, ou ao menos congelar schema com snapshots SQL em `db/migrations/`.

### 2.8 Endpoint `/categories` é só leitura 🟢
- Não há CRUD de categorias para admin.
- **Ação:** adicionar `POST/PATCH/DELETE /categories` protegido por `role=admin`.

---

## 3. Modelagem de Dados 🟡

### 3.1 Comentários sem `updatedAt`, sem `deletedAt` 🟡
- `Comment` em `Repository/Entities.hs:73-78` só tem `createdAt`. UI permite edição mas backend perde o histórico.
- **Ação:** adicionar `updatedAt`, `deletedAt` (soft-delete) e expor `commentUpdatedAt` no DTO.

### 3.2 Histórico de status da ocorrência 🟡
- `Occurrence.status` é mutável e perdemos a timeline (quem mudou pra `in_progress`, quando, quem fechou).
- **Ação:** nova tabela `OccurrenceStatusLog` (occurrenceId, oldStatus, newStatus, changedBy, changedAt).

### 3.3 Categorias de imagem / múltiplas fotos 🟢
- `Occurrence.photoUrl` é só uma. Problemas urbanos costumam ter várias evidências.
- **Ação:** tabela `OccurrencePhoto` 1:N com ordem.

### 3.4 Tags / categorias secundárias 🟢
- Categoria fixa só uma. Adicionar `tags Text[]` (Postgres `text[]`) para filtros mais ricos.

### 3.5 Endereço estruturado 🟢
- Hoje guardamos `cep`, `city`, `uf`. Faltam `bairro`, `logradouro`, `numero` — úteis para agrupar por bairro.

---

## 4. Frontend — UX & Features 🟡

### 4.1 Sem testes E2E nem unitários 🔴
- `front/` é vanilla JS sem nenhum teste.
- **Ação:** Playwright para 3 jornadas críticas: cadastro→login→criar ocorrência→votar→comentar.

### 4.2 Estado global ad-hoc 🟡
- `feed.js` (575 linhas) mistura DOM, estado, fetch, mapa. Cada página tem seu próprio padrão.
- **Ação:** extrair um `store.js` simples (event-emitter) ou migrar para Alpine.js / Lit (mantém o "sem build").

### 4.3 Service Worker pouco usado 🟡
- `sw.js` existe e PWA é instalável, mas não há cache estratégico (network-first/stale-while-revalidate).
- **Ação:** Workbox-like: cache de tiles do mapa, cache do feed para offline read.

### 4.4 Notificações push 🟢
- PWA permite. Use cases: "sua ocorrência foi marcada como resolvida", "alguém comentou".
- **Ação:** Web Push API + backend salvando subscriptions.

### 4.5 Filtros do feed limitados 🟡
- Hoje: status, busca livre, "próximas a mim", chips. Faltam:
  - por **categoria** (chips multi-select).
  - por **período** (últimos 7d / 30d).
  - por **bairro** quando tivermos endereço estruturado.
  - ordenação: mais votadas, mais recentes, mais comentadas.

### 4.6 Comentários: threading + reactions 🟢
- Hoje comentários são flat. Reddit-style threads (1 nível) já melhora muito.
- **Ação:** adicionar `parentCommentId` nullable em `Comment`.

### 4.7 Mapa: clustering de markers 🟡
- Com 1000+ ocorrências fica ilegível. Usar `Leaflet.markercluster`.

### 4.8 Mapa: filtros aplicados também ao mapa 🟡
- Hoje filtro de status filtra cards mas o mapa pode mostrar todos. Confirmar e unificar.

### 4.9 i18n 🟢
- Strings em PT-BR hardcoded. Externalizar em `front/i18n/pt-BR.json` para futura tradução.

### 4.10 Acessibilidade 🟡
- `aria-label` existe em alguns botões. Faltam:
  - foco visível consistente.
  - `role="dialog"` no modal de criação + trap de foco.
  - contraste do tema light em badges (testar com Lighthouse).
  - skip-link "pular para o conteúdo".

### 4.11 Onboarding 🟢
- Primeiro acesso não tem tour. Um *coach mark* simples na primeira visita ensina a votar/criar.

### 4.12 Avatares de usuário 🟢
- Comentários mostram inicial. Permitir upload de avatar (Cloudinary já configurado).

### 4.13 Galeria/Lightbox na foto 🟢
- Clicar na foto no detalhe deve abrir lightbox fullscreen.

### 4.14 Mensagem de erro genérica 🟡
- Vários `toast(err.message)` expõem mensagens do backend que podem ser técnicas. Mapear erros conhecidos para strings amigáveis.

---

## 5. Performance 🟡

### 5.1 Bundle / cache 🟢
- HTML carrega JS modules em runtime; sem bundling, é OK em escala pequena. Em escala maior, considerar `esbuild` para concatenar.

### 5.2 Imagens 🟡
- `Cloudinary` está integrado. Garantir:
  - `f_auto,q_auto` na URL para WebP/AVIF automático.
  - `w_720` para cards, `w_1200` para detalhe (responsive).
  - `loading="lazy"` já está, ✓.

### 5.3 Postgres: índices 🟡
- Conferir índices em colunas usadas em filtros:
  - `Occurrence(status, createdAt DESC)`
  - `Occurrence(city, uf)`
  - `Vote(occurrenceId)` (já tem unique composto)
  - `Comment(occurrenceId, createdAt)`
- **Ação:** migration manual `CREATE INDEX CONCURRENTLY ...`.

### 5.4 Compressão HTTP 🟢
- `nginx.conf` provavelmente serve estático. Garantir `gzip on` e `brotli` se disponível.

---

## 6. Observabilidade & Operação 🟡

### 6.1 Métricas 🟡
- Sem `/metrics`. Não dá pra ver QPS, latência, taxa de erro.
- **Ação:** `prometheus-haskell` expondo `/metrics`, painel Grafana básico.

### 6.2 Tracing 🟢
- OpenTelemetry no Servant (`servant-opentelemetry`) ajuda a debugar produção.

### 6.3 Sentry / error tracking 🟡
- Erros do front somem (sem `console.log` global). Sentry no front e no back acelera muito o triagem.

### 6.4 Backups de DB 🔴
- `docker-compose.yml` sobe Postgres local. Em produção (Render), garantir backups automáticos diários.

### 6.5 CI/CD 🟡
- Sem `.github/workflows/`. Mínimo desejado:
  - Build do Haskell + cache de Stack/Cabal.
  - Testes unitários.
  - Lint do JS (eslint).
  - Build da imagem Docker e push em tag.

---

## 7. Features novas de produto 🟢

### 7.1 Engajamento cívico
- **Petições**: agrupar várias ocorrências em uma petição com assinaturas digitais.
- **Resposta oficial**: prefeituras com login verificado podem responder na ocorrência (badge "oficial").
- **"Seguir" ocorrência**: receber notificações de mudanças sem ter votado.

### 7.2 Termômetro de Gestão v2
- Hoje tem score simples. Adicionar:
  - série temporal (gráfico do score mês a mês).
  - comparar dois mandatos lado a lado.
  - export PDF / share image para redes sociais.

### 7.3 Gamificação
- Badges para usuários (`primeiro reporte`, `10 ocorrências resolvidas`, `super-zelador do bairro`).
- Ranking de cidadãos mais ativos por cidade.

### 7.4 Integrações
- **Webhook** out: avisar canal Slack/Telegram da prefeitura quando ocorrência da cidade chegar.
- **Importar** do 156 / portais "Fala Município".

### 7.5 Mobile nativo
- PWA já cobre 80%. Para câmera + geolocalização contínua, considerar wrapper Capacitor.

### 7.6 IA (de leve, sem alucinar)
- Classificação automática de categoria a partir da foto (modelo pequeno via API).
- Detecção de duplicatas (mesmo problema relatado por 5 pessoas) por embedding de texto + geo proximidade.
- Sugestão de prioridade baseada em histórico.

---

## 8. DX (Developer Experience) 🟢

### 8.1 Pre-commit hooks 🟢
- `ormolu` / `fourmolu` no Haskell + `prettier` no JS/CSS via `pre-commit`.

### 8.2 README de contribuição 🟢
- Falta `CONTRIBUTING.md` com como rodar testes, padrão de commit, fluxo de PR.

### 8.3 OpenAPI / Swagger 🟡
- `servant-swagger` gera spec a partir dos tipos. Documentação interativa em `/docs`.

### 8.4 Seed mais rico 🟢
- `seed-demo.sh` cria 16 ocorrências. Para stress-test e demo visual: 200+ com distribuição geográfica realística.

### 8.5 Makefile como entrypoint único 🟢
- `Makefile` já existe. Padronizar `make dev`, `make test`, `make seed`, `make logs`, `make psql`.

---

## 9. Quick Wins (1–2h cada) 🟢

Lista de itens fáceis para encaixar em sprints curtos:

- [ ] Adicionar `meta name="description"` específica em cada página (hoje todas têm a mesma).
- [ ] Adicionar `<link rel="canonical">` em cada HTML.
- [ ] `sitemap.xml` + `robots.txt`.
- [ ] Mostrar contador de comentários no card (já temos no detalhe).
- [ ] Botão "copiar CEP" no detalhe.
- [ ] Atalho `?` que abre um modal com a lista de keyboard shortcuts (`keys.js` já existe).
- [ ] `404.html` customizado.
- [ ] Loading state no botão "Próximas a mim" já existe — replicar nos botões de status na detail page.
- [ ] `prefers-reduced-motion`: desabilitar animação de hover/scale dos cards.
- [ ] Validar `JWT_SECRET` no boot e logar warning se for o default.

---

## 10. Ordem sugerida de execução

**Sprint 1 (segurança & fundação):** §1.1, §1.3, §2.1 (testes mínimos), §2.3 (paginação), §6.4 (backup).

**Sprint 2 (UX e engajamento):** §4.5 (filtros), §4.7 (cluster mapa), §3.2 (histórico status), §4.10 (a11y).

**Sprint 3 (escala e observabilidade):** §5.3 (índices), §6.1 (métricas), §6.5 (CI), §2.7 (migrations).

**Sprint 4 (produto):** §7.1, §7.2 (termômetro v2), §7.3 (gamificação).

---

> Documento gerado a partir de varredura estática do repositório em `/Users/marcelosilva/ZelaAi`. Itens marcados podem precisar de validação contra o backlog real do time.
