#!/usr/bin/env bash
# Cenário 1: CrashLoopBackOff
# Substitui o comando do container por um que sai imediatamente com código de erro.
# O kubelet reinicia o container repetidamente → CrashLoopBackOff.
#
# Reversão: ./01-crashloopbackoff.sh --revert

set -euo pipefail
trap 'echo "[ERRO] Script falhou na linha $LINENO" >&2' ERR

NAMESPACE="aiops-lab"
DEPLOYMENT="workload-vitima"

revert() {
  echo "Revertendo para imagem e comando normais..."
  kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=60s
  echo "Revertido com sucesso."
}

if [[ "${1:-}" == "--revert" ]]; then
  revert
  exit 0
fi

echo "Injetando falha: CrashLoopBackOff em $DEPLOYMENT/$NAMESPACE"
kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["/bin/sh","-c","exit 1"]}]'

echo "Aguardando primeiro restart..."
sleep 10
kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
echo ""
echo "Reversão: $0 --revert"
