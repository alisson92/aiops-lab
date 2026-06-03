#!/usr/bin/env bash
# Cenário 4: Readiness probe falhando
# Aponta a readinessProbe para um path que retorna 404.
# O pod fica Running mas nunca Ready → tráfego não é roteado.
#
# Reversão: ./04-readiness-failing.sh --revert

set -euo pipefail
trap 'echo "[ERRO] Script falhou na linha $LINENO" >&2' ERR

NAMESPACE="aiops-lab"
DEPLOYMENT="workload-vitima"

revert() {
  echo "Revertendo readinessProbe para path válido..."
  kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=60s
  echo "Revertido com sucesso."
}

if [[ "${1:-}" == "--revert" ]]; then
  revert
  exit 0
fi

echo "Injetando falha: Readiness probe quebrada em $DEPLOYMENT/$NAMESPACE"
kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/this-path-will-never-exist"}]'

echo "Aguardando pod ficar Running mas não Ready (pode levar ~30s)..."
sleep 20
kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
echo ""
echo "Reversão: $0 --revert"
