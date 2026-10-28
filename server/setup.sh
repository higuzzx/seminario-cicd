#!/usr/bin/env bash
# Prepara a EC2 do seminário. Rode UMA vez, dentro da pasta server/:
#   cp config.env.example config.env && nano config.env
#   sudo ./setup.sh
#
# O que faz:
#   1. Cria 2 GB de swap (a t3.micro tem só 1 GB de RAM)
#   2. Instala Docker + Docker Compose
#   3. Cria o usuário "deploy" (usado pelo GitHub Actions via SSH)
#   4. Copia a estrutura para /opt/seminario e gera os .env
#   5. Cria a rede "proxy" e sobe o Traefik e o Dozzle

set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Rode com sudo: sudo ./setup.sh"; exit 1; }
cd "$(dirname "$0")"
[[ -f config.env ]] || { echo "Crie o config.env a partir do config.env.example"; exit 1; }
# shellcheck disable=SC1091
source config.env

BASE=/opt/seminario
log() { echo -e "\n\033[1;34m==> $*\033[0m"; }

# ── 1. Swap ──────────────────────────────────────────────
if ! swapon --show | grep -q /swapfile; then
  log "Criando swap de 2 GB"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ── 2. Docker ────────────────────────────────────────────
if ! command -v docker >/dev/null; then
  log "Instalando Docker"
  if ! curl -fsSL https://get.docker.com | sh; then
    echo "Script oficial falhou; instalando pelos pacotes do Ubuntu"
    apt-get update
    apt-get install -y docker.io docker-compose-v2
  fi
  systemctl enable --now docker
fi
apt-get install -y apache2-utils >/dev/null 2>&1 || true

# ── 3. Usuário deploy ────────────────────────────────────
if ! id deploy >/dev/null 2>&1; then
  log "Criando usuário deploy"
  useradd -m -s /bin/bash deploy
fi
usermod -aG docker deploy
usermod -aG docker ubuntu || true
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
if [[ "$DEPLOY_PUBKEY" == ssh-* ]]; then
  grep -qF "$DEPLOY_PUBKEY" /home/deploy/.ssh/authorized_keys 2>/dev/null \
    || echo "$DEPLOY_PUBKEY" >> /home/deploy/.ssh/authorized_keys
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 600 /home/deploy/.ssh/authorized_keys
else
  echo "AVISO: DEPLOY_PUBKEY não preenchida; o pipeline não vai conseguir entrar ainda."
fi

# ── 4. Estrutura em /opt/seminario ───────────────────────
log "Copiando arquivos para $BASE"
mkdir -p "$BASE"
cp -r traefik observabilidade scripts "$BASE"/
mkdir -p "$BASE/clientes" "$BASE/traefik/letsencrypt"
touch "$BASE/traefik/letsencrypt/acme.json"
chmod 600 "$BASE/traefik/letsencrypt/acme.json"
chmod +x "$BASE"/scripts/*.sh

PAINEL_AUTH=$(htpasswd -nbB "$PAINEL_USER" "$PAINEL_SENHA" 2>/dev/null \
  || printf '%s:%s' "$PAINEL_USER" "$(openssl passwd -apr1 "$PAINEL_SENHA")")

# Aspas simples: o Compose não interpreta os "$" do hash
cat > "$BASE/traefik/.env" <<EOF
DOMINIO=$DOMINIO
ACME_EMAIL=$ACME_EMAIL
PAINEL_AUTH='$PAINEL_AUTH'
EOF

cat > "$BASE/observabilidade/.env" <<EOF
DOMINIO=$DOMINIO
GRAFANA_SENHA='$GRAFANA_SENHA'
EOF

for C in $CLIENTES; do
  mkdir -p "$BASE/clientes/$C"
  cp clientes/docker-compose.yml "$BASE/clientes/$C/docker-compose.yml"
  if [[ ! -f "$BASE/clientes/$C/.env" ]]; then
    VAR="COR_${C//-/_}"
    cat > "$BASE/clientes/$C/.env" <<EOF
CLIENTE=$C
DOMINIO=$DOMINIO
IMAGE=$DOCKERHUB_USERNAME/seminario-cicd-app
TAG=latest
COR=${!VAR:-#2563eb}
EOF
  fi
done

chown -R deploy:deploy "$BASE"

# ── 5. Rede e serviços base ──────────────────────────────
log "Subindo Traefik e Dozzle"
docker network inspect proxy >/dev/null 2>&1 || docker network create proxy
docker compose -f "$BASE/traefik/docker-compose.yml" --project-directory "$BASE/traefik" up -d
docker compose -f "$BASE/observabilidade/docker-compose.yml" --project-directory "$BASE/observabilidade" up -d

log "Pronto!"
cat <<EOF

  Painel Traefik:  https://traefik.$DOMINIO   (usuário: $PAINEL_USER)
  Logs (Dozzle):   https://logs.$DOMINIO
  Clientes:        $(for C in $CLIENTES; do printf 'https://%s.%s  ' "$C" "$DOMINIO"; done)
                   (sobem no primeiro deploy do pipeline)

  Prometheus + Grafana + cAdvisor (opcional, usa mais memória):
    cd $BASE/observabilidade && sudo docker compose --profile completo up -d

  Teste o usuário deploy a partir da sua máquina:
    ssh -i ~/.ssh/github_deploy deploy@<ELASTIC_IP> "docker ps"
EOF
