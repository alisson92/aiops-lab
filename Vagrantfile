# Vagrantfile — aiops-lab
#
# Suporta dois providers. Escolha conforme seu ambiente:
#
#   VIRTUALBOX (padrão — máquina sem WSL2 / sem Hyper-V ativo)
#     vagrant up
#     vagrant ssh → make pf
#     Acesso via localhost com port forwarding (ver seção abaixo)
#
#   HYPER-V (máquinas com WSL2 ou sem VirtualBox instalado)
#     Requer PowerShell como Administrador
#     vagrant up --provider=hyperv
#     vagrant ssh → make pf
#     Acesso via IP da VM (sem localhost). Após o boot:
#       vagrant ssh -c "hostname -I | awk '{print $1}'"
#     Use o IP retornado no lugar de localhost no browser.
#
# Comandos comuns (ambos os providers):
#   vagrant up           # cria VM + instala tudo (~20 min no primeiro boot)
#   vagrant ssh          # acessa a VM
#   vagrant halt         # desliga a VM (dados preservados)
#   vagrant destroy      # remove a VM completamente
#
# Pré-requisitos no host:
#   VirtualBox: https://www.virtualbox.org/ + Vagrant
#   Hyper-V:    recurso nativo do Windows Pro/Enterprise/Education
#               habilitar via: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"

  # ── VirtualBox ───────────────────────────────────────────────────────────────
  # Usar quando Hyper-V NÃO está ativo (máquina sem WSL2).
  # Port forwarding funciona nativamente — acesso via localhost no host.
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "aiops-lab"
    vb.cpus   = 4
    vb.memory = 8192  # 8 GB — mínimo validado; recomendado 12288 para matriz completa de modelos
  end

  # ── Hyper-V ──────────────────────────────────────────────────────────────────
  # Usar quando Hyper-V está ativo (WSL2 instalado) ou quando VirtualBox não está disponível.
  # enable_virtualization_extensions: expõe nested virtualization para a VM —
  #   obrigatório para o Kind conseguir subir o cluster Kubernetes dentro de containers Docker.
  # ⚠️  Port forwarding via config.vm.network é ignorado pelo provider Hyper-V.
  #     Use o IP da VM diretamente (ver instruções no cabeçalho acima).
  #
  # Box: generic/debian12 em vez de debian/bookworm64 — o box oficial do projeto Debian
  # não publica variante Hyper-V no Vagrant Cloud. O generic/debian12 é mantido pelo
  # projeto "generic" (rogerioalves/generic-boxes) e suporta VirtualBox, Hyper-V, VMware,
  # libvirt — Debian 12 idêntico, apenas empacotado para mais providers.
  config.vm.provider "hyperv" do |hv, override|
    override.vm.box                    = "generic/debian12"
    hv.vmname                          = "aiops-lab"
    hv.cpus                            = 4
    hv.memory                          = 8192   # startup memory
    hv.maxmemory                       = 8192   # sem maxmemory, o Hyper-V entra em modo dinâmico
                                                # com faixas inconsistentes — forçar max == startup
                                                # resolve "Maximum memory < required minimum"
    hv.enable_virtualization_extensions = true
  end

  # ── Port forwarding (VirtualBox only) ────────────────────────────────────────
  # Portas do host com offset +10000 para não conflitar com o lab rodando no WSL2
  # (que ocupa 3000, 3001, 8081 e 9091 diretamente no localhost do Windows).
  # Com Hyper-V estas entradas são ignoradas — acesse via IP da VM na porta original.
  #
  #   Serviço        VirtualBox (localhost)   Hyper-V (IP da VM)
  #   Grafana        http://localhost:13000   http://<VM_IP>:3000
  #   Prometheus     http://localhost:19091   http://<VM_IP>:9091
  #   Keep frontend  http://localhost:13001   http://<VM_IP>:3001
  #   Keep API       http://localhost:18081   http://<VM_IP>:8081
  config.vm.network "forwarded_port", guest: 3000, host: 13000  # Grafana    (NodePort 30000)
  config.vm.network "forwarded_port", guest: 9091, host: 19091  # Prometheus (NodePort 30090)
  config.vm.network "forwarded_port", guest: 3001, host: 13001  # Keep frontend (make pf)
  config.vm.network "forwarded_port", guest: 8081, host: 18081  # Keep API      (make pf)

  # ── Provisionamento ───────────────────────────────────────────────────────────
  # Instala todas as dependências e executa make setup.
  # Com Hyper-V: o Vagrant usará SMB para sincronizar /vagrant — será solicitado
  # usuário e senha Windows durante o primeiro `vagrant up`.
  config.vm.provision "shell", path: "scripts/bootstrap-vm.sh"
end
