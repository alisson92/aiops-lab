.DEFAULT_GOAL := help

# ─── variáveis ────────────────────────────────────────────────────────────────

CLUSTER_NAME := aiops-lab
ENV          := local

# ─── targets principais ───────────────────────────────────────────────────────

.PHONY: help setup cluster-up deploy bootstrap pf teardown

help: ## Mostra esta ajuda
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS=":.*##"}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: cluster-up deploy bootstrap ## Sobe o lab completo do zero (≈10 min)

cluster-up: ## Cria o cluster Kind aiops-lab
	kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml

deploy: ## Aplica todos os releases via helmfile (requer cluster ativo)
	helmfile -e $(ENV) sync

bootstrap: ## Registra Ollama provider e workflow no Keep (idempotente)
	bash scripts/keep-bootstrap.sh

pf: ## Sobe port-forwards para acesso local (Grafana, Prometheus, Keep)
	bash scripts/port-forward.sh

teardown: ## Destroi o cluster e todos os dados (pede confirmação)
	@read -p "Destruir cluster '$(CLUSTER_NAME)'? Dados do PVC serão perdidos. [y/N] " c \
	  && [ "$$c" = "y" ] \
	  && kind delete cluster --name $(CLUSTER_NAME) \
	  || echo "Cancelado."
