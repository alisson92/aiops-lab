#!/usr/bin/env bash
# scripts/wait-ready.sh
#
# Aguarda todos os Deployments e StatefulSets do namespace ficarem prontos.
# Executado entre o 'helmfile sync' e o 'keep-bootstrap.sh' para garantir
# que a stack inteira está Running antes de tentar configurar o Keep.
#
# Uso: bash scripts/wait-ready.sh

set -euo pipefail

NAMESPACE="aiops-lab"
TIMEOUT=600  # 10 min — Ollama e kube-prometheus-stack são lentos no primeiro pull

echo "Aguardando workloads ficarem prontos no namespace '${NAMESPACE}'..."
echo "(timeout: ${TIMEOUT}s — o primeiro pull de imagens pode demorar)"
echo ""

ALL_OK=true

# Deployments
for deploy in $(kubectl get deployment -n "${NAMESPACE}" -o name 2>/dev/null); do
  printf "  %-60s" "${deploy}"
  if kubectl rollout status "${deploy}" -n "${NAMESPACE}" --timeout="${TIMEOUT}s" \
       >/dev/null 2>&1; then
    echo "✓"
  else
    echo "✗  (timeout ou erro — verifique: kubectl describe ${deploy} -n ${NAMESPACE})"
    ALL_OK=false
  fi
done

# StatefulSets (ex: MySQL do Keep)
for sts in $(kubectl get statefulset -n "${NAMESPACE}" -o name 2>/dev/null); do
  printf "  %-60s" "${sts}"
  if kubectl rollout status "${sts}" -n "${NAMESPACE}" --timeout="${TIMEOUT}s" \
       >/dev/null 2>&1; then
    echo "✓"
  else
    echo "✗  (timeout ou erro — verifique: kubectl describe ${sts} -n ${NAMESPACE})"
    ALL_OK=false
  fi
done

echo ""

if $ALL_OK; then
  echo "Todos os workloads prontos. Prosseguindo com o bootstrap."
else
  echo "[ERRO] Um ou mais workloads não ficaram prontos no tempo limite." >&2
  echo "       Use 'k9s -n ${NAMESPACE}' para investigar." >&2
  exit 1
fi
