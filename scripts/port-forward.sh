#!/usr/bin/env bash
# scripts/port-forward.sh
#
# Sobe os port-forwards necessários para acesso local ao lab.
# Executa em background e verifica conectividade antes de imprimir as URLs.
#
# Grafana e Prometheus NÃO precisam de port-forward — já expostos via NodePort:
#   kind-config.yaml: containerPort 30000 → hostPort 3000  (Grafana)
#   kind-config.yaml: containerPort 30090 → hostPort 9091  (Prometheus)
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
kubectl port-forward --address 0.0.0.0 svc/keep-backend  -n "${NAMESPACE}" 8081:8080  >/dev/null 2>&1 &
kubectl port-forward --address 0.0.0.0 svc/keep-frontend -n "${NAMESPACE}" 3001:3000  >/dev/null 2>&1 &

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
# Grafana e Prometheus via NodePort (sem port-forward)
wait_for "Grafana"     "http://localhost:3000/api/health"
wait_for "Prometheus"  "http://localhost:9091/-/ready"

# Detecta o IP principal da máquina para exibir URLs acessíveis externamente
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
HOST_IP=${HOST_IP:-localhost}

echo ""
echo "Serviço          URL"
echo "─────────────── ──────────────────────────────────"
echo "Keep frontend    http://${HOST_IP}:3001              [port-forward]"
echo "Keep API         http://${HOST_IP}:8081      (X-API-KEY: keepappkey)  [port-forward]"
echo "Grafana          http://${HOST_IP}:3000      (admin / admin)           [NodePort]"
echo "Prometheus       http://${HOST_IP}:9091                                [NodePort]"
echo ""
echo "⚠  Se o login do Keep redirecionar para localhost, atualize NEXTAUTH_URL:"
echo "   kubectl set env deployment/keep-frontend NEXTAUTH_URL=http://${HOST_IP}:3001 -n ${NAMESPACE}"
echo ""
echo "Para encerrar: pkill -f 'kubectl port-forward'"
