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
TIMEOUT=120         # tempo de espera para o healthcheck responder após o pod estar Ready

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
  # /providers     → catálogo completo (installed=false para não instalados, id=null)
  # /providers/all → somente providers instalados com id real
  # Bug v0.1.96: provider pode existir no DB com installed=false após restart.
  # Nesse caso: deletar pelo id e reinstalar.
  local state
  state=$(curl -sf "${KEEP_API}/providers/export" \
    -H "X-API-KEY: ${API_KEY}" | \
    python3 -c "
import sys, json
providers = json.load(sys.stdin)
if isinstance(providers, dict):
    providers = providers.get('providers', [])
ollama = next((p for p in providers if p.get('type') == 'ollama'), None)
if not ollama:
    print('absent')
elif ollama.get('installed'):
    print('installed')
else:
    print('stale:' + (ollama.get('id') or ''))
" 2>/dev/null || echo "absent")

  if [[ "$state" == "installed" ]]; then
    echo "Provider Ollama já instalado."
    return
  fi

  if [[ "$state" == stale:* ]]; then
    local stale_id="${state#stale:}"
    echo "Provider em estado inconsistente. Removendo ID '${stale_id}'..."
    curl -sf -X DELETE "${KEEP_API}/providers/ollama/${stale_id}" \
      -H "X-API-KEY: ${API_KEY}" >/dev/null || true
  fi

  echo "Instalando provider Ollama..."
  curl -sf -X POST "${KEEP_API}/providers/install" \
    -H "X-API-KEY: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "provider_id":   "ollama-local",
      "provider_type": "ollama",
      "provider_name": "ollama-local",
      "host": "http://ollama.'"${NAMESPACE}"'.svc.cluster.local:11434"
    }' >/dev/null
  echo "Provider Ollama instalado."
}

# ─── workflow ─────────────────────────────────────────────────────────────────

import_workflow() {
  # Keep gera um UUID novo a cada import — checar pelo campo 'name' do workflow,
  # que mapeia para o campo 'name:' do YAML (estável entre imports).
  local exists
  exists=$(curl -sf "${KEEP_API}/workflows" \
    -H "X-API-KEY: ${API_KEY}" | \
    python3 -c "
import sys, json
workflows = json.load(sys.stdin)
print(any(w.get('name') == 'Ollama Grafana Alert Enrichment' for w in workflows))
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
