# avaliacao

Avaliação Marcelo 18/11/2026

## Sumário

- [Grupo](#grupo)
- [Descrição](#descrição)
- [Arquitetura](#arquitetura)
  - [Rotas da API (VM2)](#rotas-da-api-vm2)
- [Estrutura](#estrutura)
- [Instalação](#instalação)
  - [1. Dependências no host](#1-dependências-no-host)
  - [2. Imagem base e chave SSH](#2-imagem-base-e-chave-ssh)
  - [3. Provisionamento com OpenTofu](#3-provisionamento-com-opentofu)
  - [4. Configuração e implantação com Ansible](#4-configuração-e-implantação-com-ansible)
- [Acesso à aplicação](#acesso-à-aplicação)
- [Validação](#validação)
- [Remover o ambiente](#remover-o-ambiente)
- [Troubleshooting](#troubleshooting)

## Grupo

| RA | Nome |
|:---|:---|
| 24000057 | André Luis Bertelli Pena |
| 24000603 | Renan Augusto Cristi Avelar |

## Descrição

Sistema de cadastro de livros provisionado como infraestrutura como código:

| Ferramenta | Função |
|---|---|
| OpenTofu + libvirt | Cria a rede, os discos e as 2 VMs (KVM) |
| Ansible | Instala o Docker e implanta as aplicações |
| Docker Compose | Executa os containers em cada VM |
| Node.js (Express) | Aplicação web (VM1) e API REST (VM2) |
| MySQL 8 | Banco de dados (VM2) |

## Arquitetura

```
Navegador ──HTTP :80──► VM1 web (192.168.100.11)
                           │  HTTP GET /livros · POST /livro
                           ▼
                        VM2 api + mysql (192.168.100.12:3000)
```

- **VM1 (`web`)**: serve a interface HTML e repassa as chamadas para a API via HTTP.
- **VM2 (`db`)**: API REST em Node.js e MySQL em containers. O MySQL **não** é publicado externamente; só a API (porta 3000).
- Rede libvirt `lab` (NAT): `192.168.100.0/24`.

### Rotas da API (VM2)

| Método | Rota | Descrição |
|---|---|---|
| `POST` | `/livro` | Cadastra um livro (`titulo`, `autor`, `ano`) |
| `GET` | `/livros` | Lista os livros cadastrados |
| `GET` | `/health` | Verificação de saúde |

CORS permite apenas a origem da aplicação web (`WEB_ORIGIN`) e os métodos `GET` e `POST`.

## Estrutura

```
iac/        OpenTofu (main.tf, outputs.tf, cloud_init.yaml)
ansible/    inventory.ini, playbook.yml
api/        API Node.js + MySQL (docker-compose.yml, Dockerfile, server.js, init.sql)
app/        Aplicação web (docker-compose.yml, Dockerfile, server.js, public/index.html)
```

## Instalação

### 1. Dependências no host

**Debian / Ubuntu:**

```bash
sudo apt update
sudo apt install -y \
  git \
  openssh-client \
  qemu-kvm libvirt-daemon-system libvirt-clients virt-manager \
  ansible genisoimage libguestfs-tools \
  --fix-missing
```

**OpenTofu:**

```bash
curl -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
chmod +x install-opentofu.sh
./install-opentofu.sh --install-method deb
rm install-opentofu.sh
```

**Coleção do Ansible para Docker Compose:**

```bash
ansible-galaxy collection install community.docker
```

**Pool de imagens do Libvirt:**

```bash
sudo mkdir -p /var/lib/libvirt/images
sudo virsh pool-define-as default dir --target /var/lib/libvirt/images
sudo virsh pool-build default 2>/dev/null || true
sudo virsh pool-start default
```

**Adicionar o usuário aos grupos `libvirt` e `kvm`:**

```bash
sudo usermod -aG libvirt "$USER"
sudo usermod -aG kvm "$USER"
```

> [!TIP]
> A forma mais confiável de aplicar os novos grupos é **reiniciar a máquina**. Se quiser evitar o reboot, `newgrp libvirt` **sozinho não basta** — ele troca um grupo por vez. Use `newgrp libvirt` e depois `newgrp kvm` em **terminais separados**, ou apenas faça logout/login.

### 2. Imagem base e chave SSH

Imagem Debian 12 com cloud-init (variante `genericcloud`), usada como base das VMs:

```bash
sudo curl -L -o /var/lib/libvirt/images/debian-12-base.qcow2 \
  https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
```

Chave SSH (se ainda não existir). A chave pública é injetada nas VMs pelo OpenTofu:

```bash
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

### 3. Provisionamento com OpenTofu

```bash
cd iac/
tofu init
tofu apply -auto-approve
```

Saída esperada:

```
web_ip    = "192.168.100.11"
api_db_ip = "192.168.100.12"
```

Aguarde cerca de 1 minuto para o cloud-init terminar e teste o acesso:

```bash
ssh -i ~/.ssh/id_ed25519 debian@192.168.100.11 hostname
ssh -i ~/.ssh/id_ed25519 debian@192.168.100.12 hostname
```

### 4. Configuração e implantação com Ansible

```bash
cd ../ansible/
ansible all -i inventory.ini -m ping
ansible-playbook -i inventory.ini playbook.yml
```

O playbook instala o Docker CE nas duas VMs, copia `api/` para a VM2 (`/opt/api`) e `app/` para a VM1 (`/opt/app`), e sobe os containers.

> [!WARNING]
> As senhas do MySQL estão em `ansible/playbook.yml` (`mysql_root_password`, `mysql_password`). Troque-as antes de qualquer uso fora do laboratório (por exemplo, com `ansible-vault`).

## Acesso à aplicação

| Serviço | URL |
|---|---|
| **Aplicação web** | http://192.168.100.11 |
| API (VM2) | http://192.168.100.12:3000 |

> Os IPs são da rede privada `lab`, acessíveis a partir da máquina que executa o libvirt.

## Validação

```bash
# Saúde da API
curl http://192.168.100.12:3000/health

# Cadastrar pela VM1 (web -> API -> MySQL)
curl -X POST http://192.168.100.11/api/livros \
  -H 'Content-Type: application/json' \
  -d '{"titulo":"Dom Casmurro","autor":"Machado de Assis","ano":1899}'

# Listar pela VM1 e direto na API
curl http://192.168.100.11/api/livros
curl http://192.168.100.12:3000/livros

# Conferir a persistência no MySQL da VM2
ssh -i ~/.ssh/id_ed25519 debian@192.168.100.12 \
  'sudo docker compose -f /opt/api/docker-compose.yml exec mysql mysql -uapp -p<senha> livraria -e "SELECT * FROM livros;"'
```

Teste de CORS (deve retornar `Access-Control-Allow-Origin: http://192.168.100.11`):

```bash
curl -i -H 'Origin: http://192.168.100.11' http://192.168.100.12:3000/livros | grep -i access-control
```

## Remover o ambiente

```bash
cd iac/
tofu destroy -auto-approve
```

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| `Permission denied (publickey)` no SSH | Usuário incorreto ou chave diferente da injetada | Use `debian@` (imagem Debian). Confira `ssh-keygen -y -f ~/.ssh/id_ed25519 \| diff - ~/.ssh/id_ed25519.pub`. Se alterar o `cloud_init.yaml`, recrie as VMs (ver abaixo). |
| `No route to host` / VM sem rede | `network_config` não aplicado ou VM ainda no boot | Aguarde ~1 min. Veja `virsh list --all`, `virsh net-list --all`, `virsh console web` (sair com `Ctrl+]`). O `main.tf` usa `network_config` v1 com MAC fixo, que funciona no Debian. |
| `couldn't retrieve IP address of domain` no `tofu apply` | `wait_for_lease = true` com IP estático | Use `wait_for_lease = false` no `network_interface` (IP é definido pelo cloud-init). |
| `Reference to undeclared resource` em `outputs.tf` | Outputs apontando para recursos inexistentes | Use `local.vms["web"].ip` e `local.vms["db"].ip`. |
| `No package matching 'docker-compose-v2'` | Pacote inexistente no Debian 12 | O playbook instala o Docker CE pelo repositório oficial (`docker-compose-plugin`). |
| MySQL em loop de restart: `CPU does not support x86-64-v2` | CPU virtual padrão (`qemu64`) | No `libvirt_domain`, use `cpu { mode = "host-passthrough" }` e recrie as VMs. |
| `api-mysql-1 is unhealthy` | Primeira inicialização lenta ou volume antigo com outra senha | `sudo docker compose logs mysql`. Se necessário: `cd /opt/api && sudo docker compose down -v` e reexecute o playbook. |
| Web retorna `502 API indisponível` | VM1 não alcança a API da VM2 | Na VM1: `curl http://192.168.100.12:3000/health` e confira `API_URL` em `/opt/app/.env`. |
| `Permission denied` ao criar volume/pool | AppArmor/permissões do libvirt | Defina `security_driver = "none"` em `/etc/libvirt/qemu.conf` e rode `sudo systemctl restart libvirtd`. |
| Aviso `REMOTE HOST IDENTIFICATION HAS CHANGED` | VM recriada com novas chaves SSH | `ssh-keygen -R 192.168.100.11` e `ssh-keygen -R 192.168.100.12`. |
| Alterações no `cloud_init.yaml` não surtem efeito | O cloud-init só roda no primeiro boot | Recrie discos, cloud-init e VMs (comando abaixo). |

**Recriar as VMs do zero:**

```bash
cd iac/
tofu apply \
  -replace='libvirt_cloudinit_disk.init["web"]' -replace='libvirt_cloudinit_disk.init["db"]' \
  -replace='libvirt_volume.disk["web"]' -replace='libvirt_volume.disk["db"]' \
  -replace='libvirt_domain.vm["web"]' -replace='libvirt_domain.vm["db"]'
```

**Logs úteis:**

```bash
# Containers (na VM correspondente)
sudo docker compose -f /opt/api/docker-compose.yml logs
sudo docker compose -f /opt/app/docker-compose.yml logs

# cloud-init (com a VM desligada)
sudo virt-cat -d web /var/log/cloud-init.log | grep -iE "error|warn"
```
