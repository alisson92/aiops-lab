# Vagrantfile — aiops-lab
#
# Provisiona uma VM Debian 12 com todos os pré-requisitos e executa make setup
# automaticamente. Após `vagrant up`, basta `vagrant ssh` e `make pf`.
#
# Uso:
#   vagrant up           # cria VM + instala tudo + make setup (~20 min no primeiro boot)
#   vagrant ssh          # acessa a VM
#   vagrant halt         # desliga a VM (dados preservados)
#   vagrant destroy      # remove a VM completamente
#
# Pré-requisitos no host:
#   - VirtualBox (https://www.virtualbox.org/)
#   - Vagrant    (https://www.vagrantup.com/)

Vagrant.configure("2") do |config|
  config.vm.box = "debian/bookworm64"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "aiops-lab"
    vb.cpus   = 4
    vb.memory = 8192  # 8 GB — mínimo validado; recomendado 12288 para matriz completa de modelos
  end

  # Port forwarding: host Windows/Linux → VM Vagrant → kind container → NodePort/PF
  #
  # Grafana e Prometheus usam NodePort (kind-config.yaml mapeia containerPort → hostPort
  # dentro da VM). O Vagrant então encaminha essa hostPort do guest para o host.
  #
  # Keep usa port-forward do kubectl (make pf) — exposto em 0.0.0.0 na VM,
  # encaminhado aqui para o host.
  config.vm.network "forwarded_port", guest: 3000, host: 3000  # Grafana   (NodePort 30000)
  config.vm.network "forwarded_port", guest: 9091, host: 9091  # Prometheus (NodePort 30090)
  config.vm.network "forwarded_port", guest: 3001, host: 3001  # Keep frontend (make pf)
  config.vm.network "forwarded_port", guest: 8081, host: 8081  # Keep API      (make pf)

  # Provisionamento: instala todas as dependências e executa make setup
  config.vm.provision "shell", path: "scripts/bootstrap-vm.sh"
end
