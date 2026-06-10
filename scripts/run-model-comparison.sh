#!/usr/bin/env bash
# Executa os 4 cenários de falha para cada modelo Tier 2 e captura ai_rca.
# Uso: ./run-model-comparison.sh [modelo]  (sem argumento = roda todos)

set -euo pipefail

KEEP_API="http://localhost:8081"
OLLAMA_API="http://localhost:11436"
RESULTS_FILE="results/model-comparison-$(date +%Y%m%d-%H%M%S).json"
WORKFLOW_ID="60cbcfc1-2605-426b-9512-d5d4d338aebe"
WORKFLOW_FILE="charts/keep/workflows/ollama-grafana-alert-enrichment.yaml"

MODELS=("gemma2:2b" "phi3.5:3.8b" "qwen2.5:3b")
SCENARIOS=("01-crashloopbackoff.sh" "02-oomkilled.sh" "03-imagepullbackoff.sh" "04-readiness-failing.sh")
KEYWORDS=("CrashLoopBackOff" "OOMKilled" "ImagePullBackOff" "Readiness")
# for: 1m / 0s+30s OOMKill / 1m / 2m  +  ~36s LLM + 30s buffer
WAITS=(120 100 120 180)

if [[ -n "${1:-}" ]]; then
  MODELS=("$1")
fi

mkdir -p results
echo "[]" > "$RESULTS_FILE"

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
  done=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('done',False))" 2>/dev/null)
  [[ "$done" == "True" ]] && echo "OK ✓" || echo "FALHOU — verifique o Ollama"
}

get_rca() {
  local keyword="$1"
  curl -s -H "X-API-KEY: keepappkey" "${KEEP_API}/alerts?limit=30" \
  | python3 -c "
import sys, json
alerts = json.load(sys.stdin)
keyword = '$keyword'.lower()
for a in alerts:
    name = str(a.get('name','')).lower()
    rca = a.get('ai_rca')
    if keyword in name and rca and rca not in ('', 'null', None):
        print(json.dumps(rca, ensure_ascii=False))
        sys.exit(0)
print('NO_RCA')
" 2>/dev/null
}

append_result() {
  python3 -c "
import sys, json
f = '$RESULTS_FILE'
data = json.load(open(f))
data.append(json.loads(sys.stdin.read()))
json.dump(data, open(f,'w'), ensure_ascii=False, indent=2)
"
}

for model in "${MODELS[@]}"; do
  switch_model "$model"

  for i in "${!SCENARIOS[@]}"; do
    scenario="${SCENARIOS[$i]}"
    keyword="${KEYWORDS[$i]}"
    wait="${WAITS[$i]}"
    num=$(echo "$scenario" | cut -d- -f1)

    echo ""
    echo "  ── Cenário $((i+1)): $keyword ──"
    echo -n "  Injetando falha... "
    bash "scenarios/$scenario" 2>/dev/null | tail -1
    echo ""

    echo -n "  Aguardando ${wait}s (Grafana + LLM)..."
    sleep "$wait"
    echo " concluído"

    echo -n "  Capturando ai_rca... "
    rca=$(get_rca "$keyword")

    if [[ "$rca" == "NO_RCA" ]]; then
      echo "não encontrado — aguarda +60s"
      sleep 60
      rca=$(get_rca "$keyword")
    fi

    if [[ "$rca" != "NO_RCA" ]]; then
      echo "OK ✓"
    else
      echo "AUSENTE"
    fi

    python3 -c "
import sys, json
model = '$model'
scenario = '$keyword'
rca_raw = '''$rca'''
if rca_raw.strip() in ('NO_RCA', '', 'null'):
    rca = None
else:
    try:
        rca = json.loads(rca_raw)
    except Exception:
        rca = rca_raw.strip()
print(json.dumps({'model': model, 'scenario': scenario, 'ai_rca': rca}))
" 2>/dev/null | append_result

    echo -n "  Revertendo... "
    bash "scenarios/$scenario" --revert 2>/dev/null | tail -1
    echo ""
    echo "  Aguardando 40s para pod estabilizar..."
    sleep 40
  done
done

echo ""
echo "════════════════════════════════════════"
echo " Testes concluídos. Resultados em: $RESULTS_FILE"
echo "════════════════════════════════════════"
