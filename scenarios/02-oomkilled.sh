#!/usr/bin/env bash
# Cenário 2: OOMKilled
# Usa a imagem já presente no node (nginx-unprivileged) com um shell loop que
# cresce uma string exponencialmente até o kernel matar o processo por OOM.
# Limit de memória reduzido para 32Mi para forçar o kill rapidamente.
#
# Reversão: ./02-oomkilled.sh --revert

set -euo pipefail
trap 'echo "[ERRO] Script falhou na linha $LINENO" >&2' ERR

NAMESPACE="aiops-lab"
DEPLOYMENT="workload-vitima"

revert() {
  echo "Revertendo limites de memória e comando..."
  kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=60s
  echo "Revertido com sucesso."
}

if [[ "${1:-}" == "--revert" ]]; then
  revert
  exit 0
fi

echo "Injetando falha: OOMKilled em $DEPLOYMENT/$NAMESPACE"

# Usa imagem já disponível no node; loop de shell cresce string até OOMKill
# ⚠️ Kind vs EKS: cgroup v2 no Kind pode ter comportamento ligeiramente diferente
kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/command","value":["/bin/sh","-c","x=a; while true; do x=\"$x$x$x$x$x$x$x$x$x$x\"; done"]},
    {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"16Mi"},
    {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"32Mi"}
  ]'

echo "Aguardando OOMKill (pode levar ~30s)..."
sleep 15
kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT"
echo ""
echo "Reversão: $0 --revert"
