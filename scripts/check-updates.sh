#!/usr/bin/env bash
# scripts/check-updates.sh
#
# Compara as versões de chart pinadas no helmfile.yaml com as versões mais
# recentes disponíveis nos repositórios upstream.
#
# Uso: bash scripts/check-updates.sh
#      make update-check
#
# Pré-requisito: helm e python3 instalados e acessíveis no PATH.

set -euo pipefail

HELMFILE="helmfile.yaml"

# ─── repositórios upstream ────────────────────────────────────────────────────

declare -A REPOS=(
  [prometheus-community]="https://prometheus-community.github.io/helm-charts"
  [ollama-helm]="https://helm.otwld.com/"
  [keephq]="https://keephq.github.io/helm-charts"
  [k8sgpt]="https://charts.k8sgpt.ai"
)

# ─── charts a verificar: "repo/chart:nome_do_release_no_helmfile" ─────────────

CHECKS=(
  "prometheus-community/kube-prometheus-stack:kube-prometheus-stack"
  "ollama-helm/ollama:ollama"
  "keephq/keep:keep"
  "k8sgpt/k8sgpt-operator:k8sgpt-operator"
)

# ─── extrai a versão pinada de um release no helmfile.yaml ───────────────────
# Usa Python para evitar falsos positivos do awk com nomes parciais nos repos
# (ex: "ollama-helm" contém "ollama", "keephq" contém "keep").

get_pinned_version() {
  local release_name="$1"
  python3 -c "
import sys, re

release_name = sys.argv[1]
in_releases = False
in_target = False

with open('$HELMFILE') as f:
    for line in f:
        stripped = line.strip()
        if stripped == 'releases:':
            in_releases = True
            continue
        if not in_releases:
            continue
        if re.match(r'^-\s+name:\s+', stripped):
            name = re.sub(r'^-\s+name:\s+', '', stripped)
            in_target = (name == release_name)
            continue
        if in_target and re.match(r'^version:', stripped):
            m = re.search(r'\"([^\"]+)\"', stripped)
            print(m.group(1) if m else '?')
            sys.exit(0)
print('?')
" "$release_name"
}

# ─── registrar repos (idempotente) ────────────────────────────────────────────

echo "Atualizando índices de repositórios..."
for name in "${!REPOS[@]}"; do
  helm repo add "$name" "${REPOS[$name]}" >/dev/null 2>&1 || true
done
helm repo update >/dev/null 2>&1
echo ""

# ─── cabeçalho ────────────────────────────────────────────────────────────────

printf "  %-32s %-10s %-12s %s\n" "Chart" "Pinada" "Disponível" "Status"
printf "  %s\n" "────────────────────────────────────────────────────────────────"

# ─── comparação por chart ─────────────────────────────────────────────────────

HAS_UPDATE=0

for entry in "${CHECKS[@]}"; do
  chart="${entry%%:*}"
  release_name="${entry##*:}"

  pinned=$(get_pinned_version "$release_name")

  if [[ "$pinned" == "?" ]]; then
    printf "  %-32s %-10s %-12s %s\n" "$release_name" "?" "?" "⚠️  não encontrado no helmfile"
    continue
  fi

  latest=$(helm search repo "$chart" -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data[0]['version'] if data else '?')
")

  if [[ "$pinned" == "$latest" ]]; then
    status="✅ atualizado"
  else
    status="⚠️  nova versão disponível"
    HAS_UPDATE=1
  fi

  printf "  %-32s %-10s %-12s %s\n" "$release_name" "$pinned" "$latest" "$status"
done

echo ""

# ─── instruções se houver atualizações ───────────────────────────────────────

if [[ "$HAS_UPDATE" -eq 1 ]]; then
  cat <<'GUIDE'
Para atualizar um chart:

  1. Verifique o changelog da nova versão no repositório upstream.

  2. Compare o schema de values para detectar chaves removidas ou renomeadas:
       helm show values <repo>/<chart> --version <nova> > /tmp/new-values.yaml
       diff /tmp/new-values.yaml values/<release>.yaml

  3. Ajuste values/<release>.yaml se necessário.

  4. Atualize a versão em helmfile.yaml.

  5. Faça um preview antes de aplicar:
       make diff               # requer: helm plugin install https://github.com/databus23/helm-diff

  6. Aplique o release alvo:
       helmfile -e local -l name=<release> sync

GUIDE
else
  echo "  Todos os charts estão na versão mais recente."
  echo ""
fi
