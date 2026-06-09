#!/usr/bin/env bash
# scripts/keep-bootstrap.sh
#
# Registra o provider Ollama e importa o workflow de enriquecimento no Keep.
# Idempotente: verifica existência antes de criar — seguro para múltiplas execuções.
#
# Uso: bash scripts/keep-bootstrap.sh
# Requer: kubectl com contexto apontando para kind-aiops-lab

set -euo pipefail
trap 'echo "[ERRO] Falha na linha $LINENO" >&2' ERR

NAMESPACE="aiops-lab"
KEEP_SVC="keep-backend"
LOCAL_PORT="18081"  # porta local temporária (evita conflito com pf existente)
KEEP_API="http://localhost:${LOCAL_PORT}"
API_KEY="keepappkey"
WORKFLOW_FILE="charts/keep/workflows/ollama-grafana-alert-enrichment.yaml"
TIMEOUT=60

# ─── port-forward temporário ─────────────────────────────────────────────────

start_pf() {
  kubectl port-forward "svc/${KEEP_SVC}" -n "${NAMESPACE}" "${LOCAL_PORT}:8080" \
    >/dev/null 2>&1 &
  PF_PID=$!
  echo "Port-forward iniciado (PID ${PF_PID})"
}

stop_pf() {
  kill "${PF_PID}" 2>/dev/null || true
  echo "Port-forward encerrado."
}

# ─── aguardar backend ─────────────────────────────────────────────────────────

wait_for_keep() {
  echo "Aguardando Keep backend..."
  local elapsed=0
  until curl -sf "${KEEP_API}/healthcheck" -H "X-API-KEY: ${API_KEY}" >/dev/null 2>&1; do
    if (( elapsed >= TIMEOUT )); then
      echo "[ERRO] Keep não respondeu em ${TIMEOUT}s." >&2
      exit 1
    fi
    sleep 3
    elapsed=$(( elapsed + 3 ))
  done
  echo "Keep pronto."
}

# ─── provider Ollama ──────────────────────────────────────────────────────────

install_ollama_provider() {
  local installed
  installed=$(curl -sf "${KEEP_API}/providers" \
    -H "X-API-KEY: ${API_KEY}" | \
    python3 -c "
import sys, json
providers = json.load(sys.stdin)
print(any(p.get('type') == 'ollama' and p.get('installed') for p in providers))
" 2>/dev/null || echo "False")

  if [[ "$installed" == "True" ]]; then
    echo "Provider Ollama já instalado."
    return
  fi

  echo "Instalando provider Ollama..."
  curl -sf -X POST "${KEEP_API}/providers/install" \
    -H "X-API-KEY: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "provider_type": "ollama",
      "provider_name": "ollama-local",
      "host": "http://ollama.'"${NAMESPACE}"'.svc.cluster.local:11434"
    }' >/dev/null
  echo "Provider Ollama instalado."
}

# ─── workflow ─────────────────────────────────────────────────────────────────

import_workflow() {
  local exists
  exists=$(curl -sf "${KEEP_API}/workflows" \
    -H "X-API-KEY: ${API_KEY}" | \
    python3 -c "
import sys, json
workflows = json.load(sys.stdin)
print(any(w.get('id') == 'ollama-grafana-alert-enrichment' for w in workflows))
" 2>/dev/null || echo "False")

  if [[ "$exists" == "True" ]]; then
    echo "Workflow já importado."
    return
  fi

  echo "Importando workflow..."
  curl -sf -X POST "${KEEP_API}/workflows" \
    -H "X-API-KEY: ${API_KEY}" \
    -F "file=@${WORKFLOW_FILE}" \
    >/dev/null
  echo "Workflow importado."
}

# ─── main ─────────────────────────────────────────────────────────────────────

start_pf
trap stop_pf EXIT  # garante cleanup mesmo se o script falhar

sleep 2  # aguarda o port-forward estabilizar
wait_for_keep
install_ollama_provider
import_workflow

echo ""
echo "Bootstrap concluído."
