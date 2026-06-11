#!/usr/bin/env bash
# Troca o modelo LLM do workflow Keep e aquece o Ollama.
# Uso: ./switch-llm-model.sh <modelo>
# Exemplo: ./switch-llm-model.sh phi3.5:3.8b
#
# Modelos viáveis (passaram nos gates da Fase 0):
#   gemma2:2b | phi3.5:3.8b | qwen2.5:3b

set -euo pipefail
trap 'echo "[ERRO] Script falhou na linha $LINENO" >&2' ERR

# Carregar .env se existir — nunca commitar o .env (ver .gitignore)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -z "$key" || "$key" == "$line" ]] && continue
    if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
      value="${value:1:${#value}-2}"
    fi
    export "$key=$value"
  done < "${PROJECT_ROOT}/.env"
fi

MODEL="${1:-}"
NAMESPACE="aiops-lab"
KEEP_API="http://localhost:8081"
OLLAMA_API="http://localhost:11436"
WORKFLOW_ID="60cbcfc1-2605-426b-9512-d5d4d338aebe"
WORKFLOW_FILE="config/keep/workflows/ollama-grafana-alert-enrichment.yaml"

if [[ -z "$MODEL" ]]; then
  echo "Uso: $0 <modelo>"
  echo "Modelos viáveis: gemma2:2b | phi3.5:3.8b | qwen2.5:3b"
  exit 1
fi

echo "=== Trocando modelo para: $MODEL ==="

# 1. Atualiza o workflow YAML
sed -i "s|model: \".*\"|model: \"${MODEL}\"|g" "$WORKFLOW_FILE"
sed -i "s|Ollama local (.*)\.|Ollama local (${MODEL}).|g" "$WORKFLOW_FILE"

# 2. Aplica no Keep via API
echo "Atualizando workflow no Keep..."
RESULT=$(curl -s -X PUT "${KEEP_API}/workflows/${WORKFLOW_ID}" \
  -H "X-API-KEY: ${KEEP_API_KEY:-keepappkey}" \
  -H "Content-Type: application/yaml" \
  --data-binary @"$WORKFLOW_FILE")
REVISION=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('revision','?'))" 2>/dev/null)
echo "  → Workflow atualizado (revision ${REVISION})"

# 3. Aquece o modelo no Ollama (elimina cold start)
echo "Aquecendo modelo ${MODEL} no Ollama (pode levar até 60s)..."
RESPONSE=$(curl -s -X POST "${OLLAMA_API}/api/generate" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"prompt\":\"ready\",\"stream\":false,\"options\":{\"num_predict\":1}}" \
  --max-time 120)
DONE=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('done','false'))" 2>/dev/null)

if [[ "$DONE" == "True" || "$DONE" == "true" ]]; then
  echo "  → Modelo carregado na memória ✓"
else
  echo "  → AVISO: resposta inesperada do Ollama — verifique manualmente"
  echo "    $RESPONSE" | head -c 200
fi

# 4. Confirma keep-alive
EXPIRES=$(curl -s "${OLLAMA_API}/api/ps" | \
  python3 -c "import sys,json; models=json.load(sys.stdin).get('models',[]); m=[x for x in models if x.get('name','').startswith('${MODEL}')]; print(m[0].get('expires_at','?') if m else 'não encontrado')" 2>/dev/null)
echo "  → Expires at: ${EXPIRES}"

echo ""
echo "=== Pronto! Modelo ativo: ${MODEL} ==="
echo "Próximo passo: injete o cenário de falha e observe o ai_rca no Keep."
