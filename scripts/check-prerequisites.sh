#!/usr/bin/env bash
# scripts/check-prerequisites.sh
#
# Verifica se o ambiente está pronto para executar o aiops-lab.
# Detecta o SO, checa ferramentas, recursos e portas.
# Imprime o comando de instalação de tudo que estiver faltando.
#
# Uso: bash scripts/check-prerequisites.sh

# ── cores e helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
BOLD='\033[1m'; RESET='\033[0m'

ERRORS=0; WARNINGS=0

ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET} $*"; WARNINGS=$(( WARNINGS + 1 )); }
fail() { echo -e "  ${RED}✗${RESET} $*"; ERRORS=$(( ERRORS + 1 )); }
info() { echo -e "    ${YELLOW}→${RESET} $*"; }

# ── detecção de SO ────────────────────────────────────────────────────────────
OS="$(uname -s 2>/dev/null || echo unknown)"
IS_WSL=false; IS_MAC=false; IS_LINUX=false; PKG_MGR="unknown"

case "$OS" in
  Linux)
    IS_LINUX=true
    grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=true
    command -v apt-get &>/dev/null && PKG_MGR="apt"
    command -v dnf     &>/dev/null && PKG_MGR="dnf"
    command -v yum     &>/dev/null && PKG_MGR="yum"
    ;;
  Darwin)
    IS_MAC=true; PKG_MGR="brew"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo ""
    echo -e "${RED}${BOLD}Windows nativo detectado.${RESET}"
    echo ""
    echo "  Este projeto requer WSL2 rodando Ubuntu ou Debian."
    echo "  Execute os passos abaixo no PowerShell (como Administrador):"
    echo ""
    echo "    wsl --install -d Ubuntu"
    echo ""
    echo "  Depois abra o terminal Ubuntu e rode:"
    echo ""
    echo "    git clone https://github.com/alisson92/aiops-lab.git"
    echo "    cd aiops-lab"
    echo "    bash scripts/check-prerequisites.sh"
    echo ""
    exit 1
    ;;
esac

# ── cabeçalho ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   aiops-lab — verificação de ambiente    ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""

SYSTEM_LABEL="Linux"
if   $IS_WSL; then SYSTEM_LABEL="Linux / WSL2"
elif $IS_MAC; then SYSTEM_LABEL="macOS"
elif $IS_LINUX; then
  DISTRO=$(grep -oP '(?<=^ID=).+' /etc/os-release 2>/dev/null | tr -d '"' || echo "linux")
  SYSTEM_LABEL="Linux ($DISTRO)"
fi
echo -e "  Sistema detectado: ${BOLD}${SYSTEM_LABEL}${RESET}"
echo ""

# ── ferramentas ───────────────────────────────────────────────────────────────
echo -e "${BOLD}Ferramentas${RESET}"

# docker
if ! command -v docker &>/dev/null; then
  fail "docker — não encontrado"
  if $IS_MAC; then
    info "Instale o Docker Desktop: https://www.docker.com/products/docker-desktop/"
  elif $IS_WSL; then
    info "Opção A (recomendada): Docker Desktop para Windows com integração WSL2"
    info "  https://www.docker.com/products/docker-desktop/"
    info "Opção B (nativo no WSL2):"
    info "  curl -fsSL https://get.docker.com | sh"
    info "  sudo usermod -aG docker \$USER && newgrp docker"
  else
    info "curl -fsSL https://get.docker.com | sh"
    info "sudo usermod -aG docker \$USER && newgrp docker"
  fi
else
  DOCKER_VER=$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "?")
  ok "docker $DOCKER_VER"

  if ! docker info &>/dev/null 2>&1; then
    fail "docker daemon — não está rodando"
    if $IS_MAC || $IS_WSL; then
      info "Abra o Docker Desktop e aguarde inicializar"
    else
      info "sudo systemctl start docker && sudo systemctl enable docker"
    fi
  else
    ok "docker daemon — rodando"
  fi

  if $IS_LINUX && ! $IS_WSL && ! groups "$USER" 2>/dev/null | grep -q docker; then
    warn "usuário '${USER}' não está no grupo docker (pode precisar de sudo)"
    info "sudo usermod -aG docker \$USER"
    info "Faça logout/login ou execute: newgrp docker"
  fi
fi

# kind
if ! command -v kind &>/dev/null; then
  fail "kind — não encontrado"
  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  if $IS_MAC; then
    info "brew install kind"
  else
    info "curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-${ARCH}"
    info "sudo install -m 755 /tmp/kind /usr/local/bin/kind"
  fi
else
  ok "kind $(kind version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi

# kubectl
if ! command -v kubectl &>/dev/null; then
  fail "kubectl — não encontrado"
  if $IS_MAC; then
    info "brew install kubectl"
  else
    info "curl -LO \"https://dl.k8s.io/release/\$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
    info "sudo install -m 755 kubectl /usr/local/bin/kubectl && rm kubectl"
  fi
else
  KUBECTL_VER=$(kubectl version --client -o json 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['clientVersion']['gitVersion'])" 2>/dev/null \
    || kubectl version --client --short 2>/dev/null | grep -oE 'v[0-9.]+' | head -1 \
    || echo "?")
  ok "kubectl $KUBECTL_VER"
fi

# helm
if ! command -v helm &>/dev/null; then
  fail "helm — não encontrado"
  if $IS_MAC; then
    info "brew install helm"
  else
    info "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
  fi
else
  ok "helm $(helm version --short 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo '?')"
fi

# helmfile
if ! command -v helmfile &>/dev/null; then
  fail "helmfile — não encontrado"
  ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
  if $IS_MAC; then
    info "brew install helmfile"
  else
    info "curl -Lo /tmp/helmfile https://github.com/helmfile/helmfile/releases/download/v0.167.1/helmfile_linux_${ARCH}"
    info "sudo install -m 755 /tmp/helmfile /usr/local/bin/helmfile && rm /tmp/helmfile"
  fi
else
  ok "helmfile v$(helmfile version 2>/dev/null | awk '/Version/{print $2}' | head -1)"
fi

# make
if ! command -v make &>/dev/null; then
  fail "make — não encontrado"
  if $IS_MAC; then
    info "xcode-select --install"
  elif [[ "$PKG_MGR" == "apt" ]]; then
    info "sudo apt-get install -y make"
  elif [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    info "sudo $PKG_MGR install -y make"
  fi
else
  ok "make $(make --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+')"
fi

# python3
if ! command -v python3 &>/dev/null; then
  fail "python3 — não encontrado (usado nos scripts de bootstrap)"
  if $IS_MAC; then
    info "brew install python3"
  elif [[ "$PKG_MGR" == "apt" ]]; then
    info "sudo apt-get install -y python3"
  elif [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    info "sudo $PKG_MGR install -y python3"
  fi
else
  ok "python3 $(python3 --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi

# curl
if ! command -v curl &>/dev/null; then
  fail "curl — não encontrado"
  if [[ "$PKG_MGR" == "apt" ]]; then
    info "sudo apt-get install -y curl"
  elif [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    info "sudo $PKG_MGR install -y curl"
  fi
else
  ok "curl $(curl --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
fi

# pkill (procps)
if ! command -v pkill &>/dev/null; then
  warn "pkill — não encontrado (necessário para make pf encerrar port-forwards)"
  if [[ "$PKG_MGR" == "apt" ]]; then
    info "sudo apt-get install -y procps"
  elif [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    info "sudo $PKG_MGR install -y procps-ng"
  fi
else
  ok "pkill (procps)"
fi

# git
if ! command -v git &>/dev/null; then
  fail "git — não encontrado"
  if $IS_MAC; then
    info "xcode-select --install"
  elif [[ "$PKG_MGR" == "apt" ]]; then
    info "sudo apt-get install -y git"
  elif [[ "$PKG_MGR" == "dnf" || "$PKG_MGR" == "yum" ]]; then
    info "sudo $PKG_MGR install -y git"
  fi
else
  ok "git $(git --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi

# ── recursos ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Recursos do sistema${RESET}"

# RAM
if [[ -f /proc/meminfo ]]; then
  TOTAL_RAM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
  TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
else
  TOTAL_RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
  TOTAL_RAM_GB=$(( TOTAL_RAM_BYTES / 1024 / 1024 / 1024 ))
fi

if   (( TOTAL_RAM_GB >= 12 )); then ok   "RAM: ${TOTAL_RAM_GB} GB"
elif (( TOTAL_RAM_GB >= 8  )); then warn "RAM: ${TOTAL_RAM_GB} GB — mínimo viável; recomendado ≥12 GB para inferência confortável"
else                                 fail "RAM: ${TOTAL_RAM_GB} GB — insuficiente (mínimo: 8 GB)"
  info "Ollama com gemma2:2b requer ~4 GB; restante do stack ~3 GB"
fi

# Disco
DISK_FREE_KB=$(df -k "${HOME}" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
DISK_FREE_GB=$(( DISK_FREE_KB / 1024 / 1024 ))

if   (( DISK_FREE_GB >= 25 )); then ok   "Disco livre: ${DISK_FREE_GB} GB"
elif (( DISK_FREE_GB >= 15 )); then warn "Disco livre: ${DISK_FREE_GB} GB — mínimo; recomendado ≥25 GB"
  info "PVC do Ollama: 15 Gi + imagens de container (~3–5 GB)"
else                                 fail "Disco livre: ${DISK_FREE_GB} GB — insuficiente (mínimo: 15 GB)"
fi

# ── portas ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Portas locais${RESET}"

check_port() {
  local port="$1" desc="$2" in_use=false
  if   command -v ss      &>/dev/null && ss -tlnp 2>/dev/null | grep -q ":${port} "; then in_use=true
  elif command -v lsof    &>/dev/null && lsof -i ":${port}" -sTCP:LISTEN &>/dev/null;     then in_use=true
  elif command -v netstat &>/dev/null && netstat -tlnp 2>/dev/null | grep -q ":${port} "; then in_use=true
  fi

  if $in_use; then
    warn "Porta ${port} em uso — pode causar conflito com: ${desc}"
    info "Identifique o processo: ss -tlnp | grep :${port}"
  else
    ok "Porta ${port} livre (${desc})"
  fi
}

check_port 3000 "Grafana (NodePort)"
check_port 3001 "Keep frontend (port-forward)"
check_port 8081 "Keep API (port-forward)"
check_port 9091 "Prometheus (port-forward)"

# ── resumo ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Resumo${RESET}"

if (( ERRORS == 0 && WARNINGS == 0 )); then
  echo -e "  ${GREEN}${BOLD}✓ Ambiente pronto.${RESET} Próximos passos:"
  echo ""
  echo "    make setup   # cria cluster, sobe tudo e configura o Keep"
  echo "    make pf      # expõe os serviços localmente"
  echo ""
elif (( ERRORS == 0 )); then
  echo -e "  ${YELLOW}${BOLD}⚠ ${WARNINGS} aviso(s).${RESET} O lab deve funcionar — revise os itens marcados com ⚠."
  echo ""
  echo "    make setup"
  echo ""
else
  echo -e "  ${RED}${BOLD}✗ ${ERRORS} erro(s) encontrado(s).${RESET} Instale os itens marcados com ✗ e execute novamente:"
  echo ""
  echo "    bash scripts/check-prerequisites.sh"
  echo ""
fi
