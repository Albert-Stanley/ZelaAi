<div align="center">

# 🟢 ZelaAi

**Plataforma colaborativa de zeladoria pública** — o *Reclame Aqui* da infraestrutura urbana, com ranking comunitário e **termômetro de gestão** dos políticos.

<p>
  <img alt="Haskell"      src="https://img.shields.io/badge/Haskell-9.6-5e5086?logo=haskell&logoColor=white">
  <img alt="Servant"      src="https://img.shields.io/badge/Servant-0.20-blue">
  <img alt="PostgreSQL"   src="https://img.shields.io/badge/PostgreSQL-15-336791?logo=postgresql&logoColor=white">
  <img alt="Docker"       src="https://img.shields.io/badge/Docker-multi--stage-2496ED?logo=docker&logoColor=white">
  <img alt="PWA"          src="https://img.shields.io/badge/PWA-installable-5A0FC8?logo=pwa&logoColor=white">
  <img alt="Render-ready" src="https://img.shields.io/badge/Render-deploy--ready-46E3B7?logo=render&logoColor=white">
  <img alt="License"      src="https://img.shields.io/badge/license-MIT-green">
</p>

</div>

---

## ✨ O que tem aqui

| Camada | Destaques |
|---|---|
| **Backend (Haskell)** | Servant + Persistent · JWT + bcrypt · Healthcheck com DB ping · CORS via env · Migrations e **seed automático** no boot · arquitetura em camadas (Presentation → UseCase → Repository) |
| **Frontend (Vanilla JS)** | **Dark / Light mode** persistido · **PWA instalável** com Service Worker · **Dashboard** com KPIs e Chart.js · Mapa Leaflet com lazy init e *circle markers* · ViaCEP no signup e nas ocorrências · Upload de foto via Cloudinary · Banner de cold-start com retry transparente · OG tags pro WhatsApp/LinkedIn |
| **Diferencial** | **Termômetro de Gestão**: cruza ocorrências com mandatos vigentes para calcular % resolvido, tempo médio de resolução e votos por gestão — visualizado em barras de calor |
| **Deploy** | `render.yaml` único: 1 clique sobe Postgres + backend Haskell + front estático |

---

## 🚀 Como rodar (local, em 2 minutos)

Pré-requisito: **Docker + Docker Compose** instalados.

```bash
git clone https://github.com/seu-user/ZelaAi.git
cd ZelaAi
docker compose up -d --build      # ~10min no primeiro build (compila Haskell)
```

Quando terminar:

| Serviço | URL |
|---|---|
| **Web app** | http://localhost:8080 |
| **API**     | http://localhost:5050 |
| **Health**  | http://localhost:5050/health |
| **Postgres**| `localhost:5433` (usuário/senha: `postgres`/`postgres`) |

O backend roda o **seed automático** no primeiro boot: cria `@demo / demo1234`, 4 políticos com mandatos em SP/RJ/BH, 16 ocorrências com fotos reais do Unsplash e votos distribuídos. Pode desligar com `SEED_DEMO=false`.

---

## 🧭 Tour pelas telas

| Tela | URL | O que tem |
|---|---|---|
| **Feed** | `/` | Mapa, busca em tempo real, filtros por status, cards com lazy loading |
| **Dashboard** | `/dashboard.html` | 4 KPIs, doughnut de status, top categorias, evolução por mês, polar area, top cidades, top votadas |
| **Termômetro** | `/mandates.html` | Score visual por mandato: barra de calor + 4 estatísticas |
| **Minhas** | `/my.html` | Suas ocorrências (login obrigatório) |
| **Detalhe** | `/occurrence.html?id=N` | Foto grande, infos, voto, mudança de status |
| **Auth** | `/login.html` | Login + cadastro com CEP que auto-completa cidade/UF |

🔁 Em todas as telas tem **toggle de tema** no header e botão flutuante para **instalar como app**.

---

## 🔌 Endpoints da API

```
GET    /                                   healthcheck básico
GET    /health                             healthcheck com ping no DB (200|503)

POST   /users/register                     cadastro (ViaCEP + bcrypt)
POST   /users/login                        retorna JWT
GET    /users/me/occurrences          🔐   minhas ocorrências
GET    /categories                         seed automático
GET    /occurrences                        feed público (ordenado por votos)
GET    /occurrences/:id                    detalhe
GET    /occurrences/by-location?cep=…      filtro por CEP
POST   /occurrences                   🔐   cria + vincula ao mandato vigente
PATCH  /occurrences/:id/status        🔐   open | in_progress | resolved
POST   /occurrences/:id/vote          🔐   vota (1 por user)
DELETE /occurrences/:id/vote          🔐   tira voto
POST   /politicians                        cria político
POST   /mandates                           cria mandato
GET    /mandates                           lista com político embutido
GET    /mandates/:id/score                 % resolvido, tempo médio, votos
```

Autenticação: `Authorization: Bearer <jwt>` nas rotas marcadas com 🔐.

---

## ⚙️ Variáveis de ambiente

| Variável | Default | Quando setar |
|---|---|---|
| `DATABASE_URL`             | `host=localhost port=5432 user=postgres dbname=postgres password=root` | Sempre (injetado pelo Compose/Render) |
| `JWT_SECRET`               | `change_me_in_production` | Sempre em produção |
| `PORT`                     | `5050`  | Render injeta automaticamente |
| `CORS_ALLOWED_ORIGINS`     | (aberto) | Produção: `https://app.com,https://outro.com` |
| `SEED_DEMO`                | `true`  | `false` para subir com DB vazio |

Front (meta tags em todas as HTMLs):

| Meta | Função |
|---|---|
| `api-base`                     | URL pública do backend (vazio = auto-detect) |
| `cloudinary-cloud-name`        | Habilita upload de foto direto (sem isso, fallback de URL manual) |
| `cloudinary-upload-preset`     | Preset *unsigned* configurado no Cloudinary |

---

## 🏗️ Arquitetura

```
┌─────────────────┐      ┌──────────────────────────────────────┐      ┌────────────┐
│                 │      │            Backend Haskell            │      │            │
│  Frontend       │      │                                       │      │            │
│  (Vanilla JS)   │ ───► │  Presentation (Servant handlers)      │ ───► │ PostgreSQL │
│  + Leaflet      │      │      │                                │      │            │
│  + Chart.js     │      │      ▼                                │      │            │
│  + PWA / SW     │      │  UseCase (regras de negócio)          │      │            │
│                 │      │      │                                │      │            │
│  - dark mode    │      │      ▼                                │      │            │
│  - cold-start   │      │  Repository (Persistent)              │      │            │
│  - ViaCEP       │      │      │                                │      │            │
│  - Cloudinary   │      │      ▼                                │      │            │
│                 │      │  InterfaceAdapters (ViaCEP, JWT,      │      │            │
│                 │      │     bcrypt, logs)                     │      │            │
└─────────────────┘      └──────────────────────────────────────┘      └────────────┘
```

**Camadas isoladas, dependências apontam para dentro** (clean-ish architecture).

---

## 📁 Estrutura

```
ZelaAi/
├── app/Main.hs                  entrypoint (line-buffered stdout)
├── src/
│   ├── MyLib.hs                 bootstrap: pool, migrations, seed, CORS, Warp
│   ├── Api.hs                   tipo Servant + /health
│   ├── Db.hs                    conexão Postgres
│   ├── Presentation/            handlers, auth, erros
│   ├── UseCase/                 lógica de domínio (incluindo SeedCase)
│   ├── Repository/Entities.hs   schemas Persistent
│   ├── Dto/                     DTOs de entrada e resposta
│   └── InterfaceAdapters/       JWT, bcrypt, ViaCEP, logs
├── front/
│   ├── index.html               Feed + mapa + modal de criação
│   ├── dashboard.html           ✨ Dashboard com 7 visualizações
│   ├── mandates.html            Termômetro de gestão
│   ├── my.html · occurrence.html · login.html
│   ├── manifest.json + sw.js    PWA (offline-capable)
│   ├── assets/                  favicon SVG + OG image
│   ├── css/style.css            design system v3 (light + dark)
│   └── js/                      api · auth · theme · cep · upload · pwa · feed · dashboard · etc
├── render.yaml                  Render Blueprint (1-click deploy)
├── Dockerfile                   build multi-stage Haskell
├── docker-compose.yml           postgres + backend + nginx
├── seed-demo.sh / smoke-test.sh scripts auxiliares
└── DOCS.md · CHANGELOG.md
```

---

## ☁️ Deploy na Render (1 clique)

1. Push do repo pro GitHub
2. https://dashboard.render.com/blueprints/new → conecte o repo
3. A Render lê o [render.yaml](./render.yaml) e cria automaticamente:
   - **Postgres** (free, 90 dias)
   - **Backend** Haskell (web service, free — dorme após 15min)
   - **Front estático** (free, sempre acordado)
4. `JWT_SECRET` é gerado automaticamente; preencha `CORS_ALLOWED_ORIGINS` com a URL do front

O front detecta a URL da API via meta tag `api-base` que o build da Render preenche. O backend dorme no plano free — o front mostra **banner "acordando servidor…"** + retry transparente para suavizar.

### Cloudinary (opcional, para upload de foto)

1. Conta grátis em https://cloudinary.com (sem cartão)
2. Settings → Upload → Add preset: Signing Mode = **Unsigned**
3. Preencha em todas as HTMLs (ou via injeção no build):

```html
<meta name="cloudinary-cloud-name"  content="seu_cloud_name" />
<meta name="cloudinary-upload-preset" content="seu_preset" />
```

Sem isso, o front mantém o campo "URL da foto" manual como antes.

---

## 🧪 Scripts úteis

```bash
# Modo Docker (recomendado)
docker compose up -d --build              # sobe tudo
docker compose logs -f backend            # acompanha o backend
docker compose down -v                    # derruba e zera o DB

# Modo nativo (precisa ghcup com 9.6+)
make start                                 # zelaai.sh start (porta 5050)
make seed                                  # popular dados de demo
make test                                  # smoke test E2E (26 testes)
```

---

## 📚 Documentação extra

- **[DOCS.md](./DOCS.md)** — escopo, problema, solução, diagrama ER, casos de uso, atributos e regras de negócio
- **[CHANGELOG.md](./CHANGELOG.md)** — histórico de mudanças
- **[front/README.md](./front/README.md)** — guia do frontend

---

## 👥 Créditos

Projeto de TCC desenvolvido por **Albert Stanley**.

Inspirado na arquitetura do TCC em Go de Lorenzo (mesma faculdade), portado para Haskell mantendo a separação de camadas e adicionando o **Termômetro de Gestão** + Dashboard como diferenciais.

## 📄 Licença

MIT — ver [LICENSE](./LICENSE).
