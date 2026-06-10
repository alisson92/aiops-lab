#!/usr/bin/env bash
# scripts/bootstrap-vm.sh
#
# Instala todos os pré-requisitos e executa make setup na VM.
# Projetado para rodar como root durante o provisionamento do Vagrant,
# mas funciona também com `sudo bash scripts/bootstrap-vm.sh` em qualquer
# VM Debian/Ubuntu limpa.
#
# Ao final: cluster Kind pronto + stack AIOps deployada + Keep configurado.
# Próximo passo manual: vagrant ssh → cd /vagrant → make pf

set -euo pipefail
trap 'echo -e "\n[ERRO] bootstrap-vm.sh falhou na linha $LINENO" >&2' ERR

# Detecta o usuário real: quando executado via `sudo`, SUDO_USER é definido.
# No Vagrant o provisionador roda direto como root (SUDO_USER vazio) → usa "vagrant".
VM_USER="${SUDO_USER:-vagrant}"
PROJECT_DIR="/vagrant"  # diretório sincronizado pelo Vagrant
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')

log()  { echo -e "\n\033[1;32m▶  $*\033[0m"; }
info() { echo    "   → $*"; }
ok()   { echo -e "   \033[0;32m✓\033[0m $*"; }

# ── 1. pacotes base ───────────────────────────────────────────────────────────

log "Atualizando pacotes base..."
apt-get update -qq
apt-get install -y -qq \
  git make curl python3 procps \
  apt-transport-https ca-certificates gnupg lsb-release

ok "Pacotes base instalados"

# ── 2. Docker ─────────────────────────────────────────────────────────────────

log "Instalando Docker..."
if command -v docker &>/dev/null; then
  ok "Docker já instalado — pulando"
else
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  ok "Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) instalado"
fi

# Adiciona o usuário ao grupo docker para rodar sem sudo
usermod -aG docker "${VM_USER}"
info "Usuário '${VM_USER}' adicionado ao grupo docker"

# ── 3. kind ───────────────────────────────────────────────────────────────────

log "Instalando kind..."
if command -v kind &>/dev/null; then
  ok "kind já instalado — pulando"
else
  KIND_VER=$(curl -sf https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
    | grep '"tag_name"' | sed 's/.*"tag_name":.*"\(v[^"]*\)".*/\1/')
  curl -Lo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-${ARCH}"
  install -m 755 /tmp/kind /usr/local/bin/kind
  rm /tmp/kind
  ok "kind ${KIND_VER} instalado"
fi

# ── 4. kubectl ────────────────────────────────────────────────────────────────

log "Instalando kubectl..."
if command -v kubectl &>/dev/null; then
  ok "kubectl já instalado — pulando"
else
  KUBECTL_VER=$(curl -Ls https://dl.k8s.io/release/stable.txt)
  curl -Lo /tmp/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/${ARCH}/kubectl"
  install -m 755 /tmp/kubectl /usr/local/bin/kubectl
  rm /tmp/kubectl
  ok "kubectl ${KUBECTL_VER} instalado"
fi

# ── 5. Helm ───────────────────────────────────────────────────────────────────

log "Instalando Helm..."
if command -v helm &>/dev/null; then
  ok "helm já instalado — pulando"
else
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  ok "helm $(helm version --short | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+') instalado"
fi

# ── 6. helmfile ───────────────────────────────────────────────────────────────

log "Instalando helmfile..."
if command -v helmfile &>/dev/null; then
  ok "helmfile já instalado — pulando"
else
  # Release é .tar.gz desde a v0.150+ — a versão no nome do arquivo não tem prefixo 'v'
  HF_VER=$(curl -sf https://api.github.com/repos/helmfile/helmfile/releases/latest \
    | grep '"tag_name"' | sed 's/.*"tag_name":.*"v\([^"]*\)".*/\1/')
  curl -Lo /tmp/helmfile.tar.gz \
    "https://github.com/helmfile/helmfile/releases/download/v${HF_VER}/helmfile_${HF_VER}_linux_${ARCH}.tar.gz"
  tar -xzf /tmp/helmfile.tar.gz -C /tmp helmfile
  install -m 755 /tmp/helmfile /usr/local/bin/helmfile
  rm /tmp/helmfile /tmp/helmfile.tar.gz
  ok "helmfile v${HF_VER} instalado"
fi

# ── 7. k9s ────────────────────────────────────────────────────────────────────

log "Instalando k9s..."
if command -v k9s &>/dev/null; then
  ok "k9s já instalado — pulando"
else
  K9S_VER=$(curl -sf https://api.github.com/repos/derailed/k9s/releases/latest \
    | grep '"tag_name"' | sed 's/.*"tag_name":.*"v\([^"]*\)".*/\1/')
  curl -Lo /tmp/k9s.tar.gz \
    "https://github.com/derailed/k9s/releases/download/v${K9S_VER}/k9s_Linux_${ARCH}.tar.gz"
  tar -xzf /tmp/k9s.tar.gz -C /tmp k9s
  install -m 755 /tmp/k9s /usr/local/bin/k9s
  rm /tmp/k9s /tmp/k9s.tar.gz
  ok "k9s v${K9S_VER} instalado"
fi

# ── 8. helm-diff (plugin exigido pelo helmfile sync) ─────────────────────────

log "Instalando plugin helm-diff..."
# Roda como VM_USER para que o plugin fique no home correto (~/.local/share/helm/plugins)
if su -l "${VM_USER}" -c "helm plugin list 2>/dev/null | grep -q diff"; then
  ok "helm-diff já instalado — pulando"
else
  su -l "${VM_USER}" -c \
    "helm plugin install https://github.com/databus23/helm-diff"
  ok "helm-diff instalado"
fi

# ── 9. make setup ─────────────────────────────────────────────────────────────

log "Executando make setup (cluster + deploy + wait-ready + bootstrap)..."
info "Isso pode levar ~20 min no primeiro boot (pull de imagens e modelo Ollama)"
info "Diretório do projeto: ${PROJECT_DIR}"

# su -l abre um shell de login — garante que o grupo docker esteja ativo
# e que o PATH inclua /usr/local/bin (onde estão kind, helm, helmfile, etc.)
su -l "${VM_USER}" -c "cd ${PROJECT_DIR} && make setup"

# ── 10. instruções finais ─────────────────────────────────────────────────────

echo ""
echo -e "\033[1m╔══════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1m║           aiops-lab — VM pronta!                             ║\033[0m"
echo -e "\033[1m╠══════════════════════════════════════════════════════════════╣\033[0m"
echo -e "\033[1m║  Próximo passo:                                               ║\033[0m"
echo    "║    vagrant ssh                                                ║"
echo    "║    cd /vagrant && make pf                                     ║"
echo -e "\033[1m╠══════════════════════════════════════════════════════════════╣\033[0m"
echo    "║  Serviços (após make pf) — acesso no host Windows:           ║"
echo    "║    Grafana      http://localhost:13000  (admin / admin)       ║"
echo    "║    Keep         http://localhost:13001                        ║"
echo    "║    Keep API     http://localhost:18081  (X-API-KEY: keepappkey)║"
echo    "║    Prometheus   http://localhost:19091                        ║"
echo -e "\033[1m╠══════════════════════════════════════════════════════════════╣\033[0m"
echo    "║  ⚠  make pf deve ser executado dentro da VM (vagrant ssh).   ║"
echo    "║     Se um pod reiniciar, os port-forwards morrem —           ║"
echo    "║     execute make pf novamente.                               ║"
echo -e "\033[1m╚══════════════════════════════════════════════════════════════╝\033[0m"
echo ""
