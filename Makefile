SHELL        := /bin/bash
.DEFAULT_GOAL := help

# ─── variáveis ────────────────────────────────────────────────────────────────

CLUSTER_NAME := aiops-lab
ENV          := local

# ─── targets principais ───────────────────────────────────────────────────────

.PHONY: help check setup cluster-up deploy wait-ready bootstrap pf teardown update-check diff

help: ## Mostra esta ajuda
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS=":.*##"}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check: ## Verifica pré-requisitos do ambiente (ferramentas, RAM, disco, portas)
	bash scripts/check-prerequisites.sh

setup: cluster-up deploy wait-ready bootstrap ## Sobe o lab completo do zero (≈15 min)

cluster-up: ## Cria o cluster Kind aiops-lab (idempotente)
	@if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster '$(CLUSTER_NAME)' já existe. Pulando criação."; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml; \
	fi

deploy: ## Aplica todos os releases via helmfile (⚠️ remove holmesgpt se presente)
	helmfile -e $(ENV) sync

wait-ready: ## Aguarda todos os pods ficarem Running/Ready antes de prosseguir
	bash scripts/wait-ready.sh

bootstrap: ## Registra Ollama provider e workflow no Keep (idempotente)
	bash scripts/keep-bootstrap.sh

pf: ## Sobe port-forwards e verifica conectividade (Grafana via NodePort, sem PF)
	bash scripts/port-forward.sh

teardown: ## Destroi o cluster e todos os dados (pede confirmação)
	@read -p "Destruir cluster '$(CLUSTER_NAME)'? Dados do PVC serão perdidos. [y/N] " c \
	  && [ "$$c" = "y" ] \
	  && kind delete cluster --name $(CLUSTER_NAME) \
	  || echo "Cancelado."

# ─── manutenção / upgrades ────────────────────────────────────────────────────

update-check: ## Compara versões pinadas no helmfile com as últimas disponíveis upstream
	bash scripts/check-updates.sh

diff: ## Preview das mudanças antes de aplicar (requer: helm plugin install helm-diff)
	@helm plugin list 2>/dev/null | grep -q "diff" || { \
	  echo "⚠️  Plugin helm-diff não encontrado."; \
	  echo "   Instale com: helm plugin install https://github.com/databus23/helm-diff"; \
	  exit 1; \
	}
	helmfile -e $(ENV) diff
