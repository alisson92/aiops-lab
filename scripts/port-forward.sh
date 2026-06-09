#!/usr/bin/env bash
# scripts/port-forward.sh
#
# Sobe todos os port-forwards necessários para acesso local ao lab.
# Executa em background e imprime as URLs de acesso.
#
# Uso: bash scripts/port-forward.sh
# Para encerrar: pkill -f "kubectl port-forward"

set -euo pipefail

NAMESPACE="aiops-lab"

echo "Encerrando port-forwards anteriores (se houver)..."
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1

echo "Subindo port-forwards..."

kubectl port-forward svc/keep-backend    -n "${NAMESPACE}" 8081:8080  >/dev/null 2>&1 &
kubectl port-forward svc/keep-frontend   -n "${NAMESPACE}" 3001:3000  >/dev/null 2>&1 &
kubectl port-forward svc/kube-prometheus-stack-prometheus -n "${NAMESPACE}" 9091:9090 >/dev/null 2>&1 &

# Grafana: usa o pod diretamente (serviço NodePort exposto via kind-config.yaml porta 3000)
GRAFANA_POD=$(kubectl get pod -n "${NAMESPACE}" \
  -l app.kubernetes.io/name=grafana \
  -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward "pod/${GRAFANA_POD}" -n "${NAMESPACE}" 3000:3000 >/dev/null 2>&1 &

echo ""
echo "Serviço          URL"
echo "─────────────── ──────────────────────────"
echo "Keep frontend    http://localhost:3001"
echo "Keep API         http://localhost:8081      (X-API-KEY: keepappkey)"
echo "Grafana          http://localhost:3000      (admin / admin)"
echo "Prometheus       http://localhost:9091"
echo ""
echo "Para encerrar: pkill -f 'kubectl port-forward'"
