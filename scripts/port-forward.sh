#!/usr/bin/env bash
# scripts/port-forward.sh
#
# Sobe os port-forwards necessários para acesso local ao lab.
# Executa em background e verifica conectividade antes de imprimir as URLs.
#
# Nota: Grafana NÃO precisa de port-forward — já está exposto via NodePort
# (kind-config.yaml: containerPort 30000 → hostPort 3000).
#
# Uso: bash scripts/port-forward.sh
# Para encerrar: pkill -f "kubectl port-forward"

set -euo pipefail

NAMESPACE="aiops-lab"
TIMEOUT=15  # segundos para cada serviço responder

echo "Encerrando port-forwards anteriores (se houver)..."
pkill -f "kubectl port-forward" 2>/dev/null || true
sleep 1

echo "Subindo port-forwards..."
# --address 0.0.0.0 expõe em todas as interfaces — necessário para acesso externo à VM
kubectl port-forward --address 0.0.0.0 svc/keep-backend                     -n "${NAMESPACE}" 8081:8080  >/dev/null 2>&1 &
kubectl port-forward --address 0.0.0.0 svc/keep-frontend                    -n "${NAMESPACE}" 3001:3000  >/dev/null 2>&1 &
kubectl port-forward --address 0.0.0.0 svc/kube-prometheus-stack-prometheus -n "${NAMESPACE}" 9091:9090  >/dev/null 2>&1 &

# ─── verificar conectividade ──────────────────────────────────────────────────

wait_for() {
  local name="$1" url="$2" elapsed=0
  until curl -sf --max-time 2 "$url" >/dev/null 2>&1; do
    if (( elapsed >= TIMEOUT )); then
      echo "[AVISO] $name não respondeu em ${TIMEOUT}s — verifique o pod."
      return
    fi
    sleep 2; elapsed=$(( elapsed + 2 ))
  done
  echo "  ✓ $name"
}

echo "Verificando conectividade..."
wait_for "Keep API"    "http://localhost:8081/healthcheck"
wait_for "Keep UI"     "http://localhost:3001"
wait_for "Prometheus"  "http://localhost:9091/-/ready"
# Grafana via NodePort (sem port-forward)
wait_for "Grafana"     "http://localhost:3000/api/health"

echo ""
echo "Serviço          URL"
echo "─────────────── ──────────────────────────────────"
echo "Keep frontend    http://localhost:3001"
echo "Keep API         http://localhost:8081      (X-API-KEY: keepappkey)"
echo "Grafana          http://localhost:3000      (admin / admin)  [NodePort]"
echo "Prometheus       http://localhost:9091"
echo ""
echo "Para encerrar: pkill -f 'kubectl port-forward'"
