# ============================================================================
# ZelaAi — Makefile (atalhos pra dev)
# ============================================================================

.PHONY: help start build stop reset fresh logs seed test \
        docker-up docker-down docker-build docker-logs docker-clean \
        front-serve

help:           ## mostra os comandos disponíveis
	@echo "ZelaAi — comandos:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------- modo nativo ----------------------------------------

start:          ## sobe o backend Haskell na :5050
	./zelaai.sh start

build:          ## só compila o backend (cabal build)
	./zelaai.sh build

stop:           ## mata o processo na :5050
	./zelaai.sh stop

reset:          ## drop + create do schema (CUIDADO)
	./zelaai.sh reset-db

fresh:          ## reset-db + start
	./zelaai.sh fresh

seed:           ## popula dados de demo (precisa do backend rodando)
	./seed-demo.sh

test:           ## smoke test E2E de todos os endpoints
	./smoke-test.sh

front-serve:    ## serve o front estático na :8080
	cd front && python3 -m http.server 8080

# ---------------------- modo docker ----------------------------------------

docker-up:      ## sobe tudo (postgres + backend + nginx) em background
	docker compose up -d --build

docker-down:    ## derruba tudo
	docker compose down

docker-build:   ## (re)build da imagem do backend
	docker compose build backend

docker-logs:    ## follow dos logs do backend
	docker compose logs -f backend

docker-clean:   ## derruba tudo + apaga volumes (zera o banco)
	docker compose down -v
