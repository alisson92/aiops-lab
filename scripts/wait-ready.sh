#!/usr/bin/env bash
# scripts/wait-ready.sh
#
# Aguarda todos os Deployments e StatefulSets do namespace ficarem prontos.
# Os checks rodam em paralelo — o tempo de espera é o do workload mais lento,
# não a soma de todos. Timeout global de 30 min (VM nova faz pull de ~6 GB).
#
# Uso: bash scripts/wait-ready.sh

set -euo pipefail

NAMESPACE="aiops-lab"
GLOBAL_TIMEOUT=1800  # 30 min — VM nova faz pull de ~6 GB de imagens; 15 min era insuficiente

echo "Aguardando workloads ficarem prontos no namespace '${NAMESPACE}'..."
echo "(timeout global: ${GLOBAL_TIMEOUT}s — checks em paralelo)"
echo ""

# Coleta todos os workloads (Deployments + StatefulSets)
mapfile -t WORKLOADS < <(
  kubectl get deployment,statefulset -n "${NAMESPACE}" -o name 2>/dev/null
)

if [[ ${#WORKLOADS[@]} -eq 0 ]]; then
  echo "[AVISO] Nenhum workload encontrado no namespace '${NAMESPACE}'."
  exit 0
fi

# Dispara um rollout status em background para cada workload
declare -A PIDS
for workload in "${WORKLOADS[@]}"; do
  kubectl rollout status "${workload}" -n "${NAMESPACE}" \
    --timeout="${GLOBAL_TIMEOUT}s" >/dev/null 2>&1 &
  PIDS["${workload}"]=$!
done

# Aguarda cada processo e coleta resultado
ALL_OK=true
declare -A RESULTS

for workload in "${!PIDS[@]}"; do
  if wait "${PIDS[$workload]}" 2>/dev/null; then
    RESULTS["${workload}"]="ok"
  else
    RESULTS["${workload}"]="fail"
    ALL_OK=false
  fi
done

# Imprime resultado ordenado
for workload in $(printf '%s\n' "${!RESULTS[@]}" | sort); do
  if [[ "${RESULTS[$workload]}" == "ok" ]]; then
    printf "  ✓ %s\n" "${workload}"
  else
    printf "  ✗ %s\n" "${workload}"
    printf "    → kubectl describe %s -n %s\n" "${workload}" "${NAMESPACE}"
    printf "    → k9s -n %s\n" "${NAMESPACE}"
  fi
done

echo ""

if $ALL_OK; then
  echo "Todos os workloads prontos. Prosseguindo com o bootstrap."
else
  echo "[ERRO] Um ou mais workloads não ficaram prontos em ${GLOBAL_TIMEOUT}s." >&2
  exit 1
fi
