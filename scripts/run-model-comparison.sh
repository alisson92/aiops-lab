#!/usr/bin/env bash
# Executa os 4 cenários de falha para cada modelo Tier 2 e captura ai_rca.
# Uso: ./run-model-comparison.sh [modelo] [arquivo-saida]
#   modelo       : rodar apenas um modelo específico (opcional)
#   arquivo-saida: caminho do JSON de saída (padrão: timestamped em results/)

set -euo pipefail

KEEP_API="http://localhost:8081"
OLLAMA_API="http://localhost:11436"
RESULTS_FILE="${2:-results/model-comparison-$(date +%Y%m%d-%H%M%S).json}"
WORKFLOW_ID="60cbcfc1-2605-426b-9512-d5d4d338aebe"
WORKFLOW_FILE="charts/keep/workflows/ollama-grafana-alert-enrichment.yaml"
FINAL_MODEL="phi3.5:3.8b"  # modelo restaurado ao final

MODELS=("gemma2:2b" "phi3.5:3.8b" "qwen2.5:3b")
SCENARIOS=("01-crashloopbackoff.sh" "02-oomkilled.sh" "03-imagepullbackoff.sh" "04-readiness-failing.sh")
KEYWORDS=("CrashLoopBackOff" "OOMKilled" "ImagePullBackOff" "Readiness")
# waits: Grafana eval (60s) + LLM (36s max) + buffer — OOMKilled precisa do container crashar
WAITS=(180 200 180 240)

if [[ -n "${1:-}" ]]; then
  MODELS=("$1")
fi

mkdir -p results
echo "[]" > "$RESULTS_FILE"

check_keep() {
  local response
  response=$(curl -s --max-time 10 -H "X-API-KEY: keepappkey" "${KEEP_API}/healthcheck" 2>/dev/null || true)
  if [[ -z "$response" ]]; then
    echo "⚠️  Keep API não responde em ${KEEP_API}. Verifique o port-forward." >&2
    exit 1
  fi
}

switch_model() {
  local model="$1"
  echo ""
  echo "════════════════════════════════════════"
  echo " Modelo: $model"
  echo "════════════════════════════════════════"

  sed -i "s|model: \".*\"|model: \"${model}\"|g" "$WORKFLOW_FILE"
  sed -i "s|Ollama local (.*)\.|Ollama local (${model}).|g" "$WORKFLOW_FILE"

  curl -s -X PUT "${KEEP_API}/workflows/${WORKFLOW_ID}" \
    -H "X-API-KEY: keepappkey" \
    -H "Content-Type: application/yaml" \
    --data-binary @"$WORKFLOW_FILE" > /dev/null

  echo -n "  Aquecendo $model... "
  result=$(curl -s -X POST "${OLLAMA_API}/api/generate" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${model}\",\"prompt\":\"ready\",\"stream\":false,\"options\":{\"num_predict\":1}}" \
    --max-time 120)
  done_flag=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('done',False))" 2>/dev/null || echo "False")
  [[ "$done_flag" == "True" ]] && echo "OK ✓" || echo "FALHOU — verifique o Ollama"
}

get_rca() {
  local keyword="$1"
  local since="$2"
  local tmpfile
  tmpfile=$(mktemp)

  # Captura a resposta em arquivo para evitar problemas de quoting com conteúdo JSON
  curl -s --max-time 15 -H "X-API-KEY: keepappkey" "${KEEP_API}/alerts?limit=100" > "$tmpfile" 2>/dev/null || true

  # Passa valores via env para evitar expansão indevida de $ dentro do heredoc Python
  KEYWORD="$keyword" SINCE="$since" TMPFILE="$tmpfile" python3 << 'PYEOF' 2>/dev/null
import json, ast, sys, os
from datetime import datetime, timezone

keyword  = os.environ['KEYWORD'].lower()
since_ts = float(os.environ['SINCE'])
tmpfile  = os.environ['TMPFILE']

try:
    with open(tmpfile) as f:
        alerts = json.load(f)
except Exception:
    print('NO_RCA')
    sys.exit(0)

matches = []
for a in alerts:
    alertname = str(a.get('alertname', '')).lower()
    scenario  = str(a.get('scenario',  '')).lower()
    rca = a.get('ai_rca')
    if not (keyword in alertname or keyword in scenario):
        continue
    if not rca or str(rca).strip() in ('', 'null', 'None'):
        continue
    last_recv = a.get('lastReceived', '')
    try:
        ts = datetime.fromisoformat(last_recv.replace('Z', '+00:00')).timestamp()
    except Exception:
        ts = 0
    matches.append((ts, rca))

# Ordena por timestamp desc — pega o alerta mais recente desta injeção
matches.sort(key=lambda x: x[0], reverse=True)

for ts, rca in matches:
    if ts >= since_ts - 30:  # 30s de margem para clock skew / processamento
        # Keep armazena ai_rca como Python repr dict (aspas simples) — converte para JSON
        if isinstance(rca, str):
            try:
                rca = ast.literal_eval(rca)
            except Exception:
                pass
        print(json.dumps(rca, ensure_ascii=False))
        sys.exit(0)

print('NO_RCA')
PYEOF

  rm -f "$tmpfile"
}

append_result() {
  local model="$1"
  local scenario="$2"
  local rca_raw="$3"
  local tmpfile
  tmpfile=$(mktemp)
  printf '%s' "$rca_raw" > "$tmpfile"

  MODEL="$model" SCENARIO="$scenario" TMPFILE="$tmpfile" RESULTS_FILE="$RESULTS_FILE" python3 << 'PYEOF' 2>/dev/null
import json, ast, sys, os

model       = os.environ['MODEL']
scenario    = os.environ['SCENARIO']
results_f   = os.environ['RESULTS_FILE']
tmpfile     = os.environ['TMPFILE']

with open(tmpfile) as f:
    rca_raw = f.read().strip()

data = json.load(open(results_f))

if rca_raw in ('NO_RCA', '', 'null', 'None'):
    rca = None
else:
    # Tenta JSON; fallback para ast.literal_eval (Python repr do Keep)
    try:
        rca = json.loads(rca_raw)
        if isinstance(rca, str):
            try:
                rca = ast.literal_eval(rca)
            except Exception:
                pass
    except Exception:
        try:
            rca = ast.literal_eval(rca_raw)
        except Exception:
            rca = rca_raw

data.append({'model': model, 'scenario': scenario, 'ai_rca': rca})
json.dump(data, open(results_f, 'w'), ensure_ascii=False, indent=2)
PYEOF

  rm -f "$tmpfile"
}

restore_model() {
  local model="$1"
  echo ""
  echo "  Restaurando workflow para modelo padrão: $model"
  sed -i "s|model: \".*\"|model: \"${model}\"|g" "$WORKFLOW_FILE"
  sed -i "s|Ollama local (.*)\.|Ollama local (${model}).|g" "$WORKFLOW_FILE"
  curl -s -X PUT "${KEEP_API}/workflows/${WORKFLOW_ID}" \
    -H "X-API-KEY: keepappkey" \
    -H "Content-Type: application/yaml" \
    --data-binary @"$WORKFLOW_FILE" > /dev/null
  echo "  Restaurado ✓"
}

check_keep

for model in "${MODELS[@]}"; do
  switch_model "$model"

  for i in "${!SCENARIOS[@]}"; do
    scenario="${SCENARIOS[$i]}"
    keyword="${KEYWORDS[$i]}"
    wait_secs="${WAITS[$i]}"

    echo ""
    echo "  ── Cenário $((i+1)): $keyword ──"
    echo -n "  Injetando falha... "
    injection_ts=$(date +%s)
    bash "scenarios/$scenario" 2>/dev/null | tail -1 || true
    echo ""

    echo -n "  Aguardando ${wait_secs}s (Grafana + LLM)..."
    sleep "$wait_secs"
    echo " concluído"

    echo -n "  Capturando ai_rca... "
    rca=$(get_rca "$keyword" "$injection_ts")

    if [[ "$rca" == "NO_RCA" ]]; then
      echo "não encontrado — aguarda +90s"
      sleep 90
      rca=$(get_rca "$keyword" "$injection_ts")
    fi

    if [[ "$rca" != "NO_RCA" ]]; then
      echo "OK ✓"
    else
      echo "AUSENTE"
    fi

    append_result "$model" "$keyword" "$rca"

    echo -n "  Revertendo... "
    bash "scenarios/$scenario" --revert 2>/dev/null | tail -1 || true
    echo ""
    echo "  Aguardando 40s para pod estabilizar..."
    sleep 40
  done
done

restore_model "$FINAL_MODEL"

echo ""
echo "════════════════════════════════════════"
echo " Testes concluídos. Resultados em: $RESULTS_FILE"
echo "════════════════════════════════════════"
