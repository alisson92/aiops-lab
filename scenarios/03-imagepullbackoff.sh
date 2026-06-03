#!/usr/bin/env bash
# Cenário 3: ImagePullBackOff
# Aponta o container para uma tag de imagem inexistente.
# O kubelet não consegue fazer pull → ImagePullBackOff.
#
# Reversão: ./03-imagepullbackoff.sh --revert

set -euo pipefail
trap 'echo "[ERRO] Script falhou na linha $LINENO" >&2' ERR

NAMESPACE="aiops-lab"
DEPLOYMENT="workload-vitima"
BROKEN_IMAGE="nginx:this-tag-does-not-exist-99999"

revert() {
  echo "Revertendo para imagem válida..."
  kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=60s
  echo "Revertido com sucesso."
}

if [[ "${1:-}" == "--revert" ]]; then
  revert
  exit 0
fi

echo "Injetando falha: ImagePullBackOff em $DEPLOYMENT/$NAMESPACE"
kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/image\",\"value\":\"$BROKEN_IMAGE\"}]"

echo "Aguardando ImagePullBackOff..."
sleep 15
kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
echo ""
echo "Reversão: $0 --revert"
