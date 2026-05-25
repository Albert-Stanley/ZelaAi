# =============================================================================
# ZelaAi — Dockerfile multi-stage para o backend Haskell
# Stage 1: build com GHC + cabal
# Stage 2: imagem fina rodando só o binário
# =============================================================================

# ----------------------------- 1) builder -----------------------------------
FROM haskell:9.6-slim AS builder

WORKDIR /build

# instala libs nativas necessárias
# postgresql-libpq-configure >= 0.11 exige PG >= 14; usa PGDG para garantir a versão certa
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl gnupg ca-certificates \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
       | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
    && . /etc/os-release \
    && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
       > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      libpq-dev \
      zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# copia o cabal/project primeiro pra aproveitar o cache de deps
COPY ZelaAi.cabal cabal.project ./
RUN cabal update && cabal build --only-dependencies -j

# agora copia o código e builda
COPY . .
RUN cabal build exe:ZelaAi -j

# copia o binário pra um lugar previsível
RUN cp "$(cabal list-bin exe:ZelaAi)" /build/ZelaAi-bin && \
    strip /build/ZelaAi-bin || true

# ----------------------------- 2) runtime -----------------------------------
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 \
      libgmp10 \
      ca-certificates \
      netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/ZelaAi-bin /app/ZelaAi

# wait-for-postgres helper
COPY docker/wait-for-postgres.sh /app/wait-for-postgres.sh
RUN chmod +x /app/wait-for-postgres.sh

ENV JWT_SECRET="change_me_in_production" \
    DATABASE_URL="host=postgres port=5432 user=postgres dbname=postgres password=postgres"

EXPOSE 5050

CMD ["/app/wait-for-postgres.sh", "/app/ZelaAi"]
