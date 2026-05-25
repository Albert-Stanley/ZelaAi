# =============================================================================
# ZelaAi — Dockerfile multi-stage para o backend Haskell
# Stage 1: build com GHC + cabal
# Stage 2: imagem fina rodando só o binário
# =============================================================================

# ----------------------------- 1) builder -----------------------------------
FROM haskell:9.6.4-slim AS builder

WORKDIR /build

# instala libs nativas necessárias (postgres, ssl)
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq-dev \
      zlib1g-dev \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# copia apenas o cabal primeiro pra aproveitar o cache de deps
COPY ZelaAi.cabal cabal.project* ./
RUN cabal update && cabal build --only-dependencies -j

# agora copia o código e builda
COPY . .
RUN cabal build exe:ZelaAi -j

# copia o binário pra um lugar previsível
RUN cp "$(cabal list-bin exe:ZelaAi)" /build/ZelaAi-bin

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
