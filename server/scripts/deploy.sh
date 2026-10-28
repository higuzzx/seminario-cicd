#!/usr/bin/env bash
# Chamado pelo GitHub Actions via SSH:
#   /opt/seminario/scripts/deploy.sh <cliente> <tag>
#
# Atualiza SOMENTE o container do cliente informado.
# Se a nova versão não ficar saudável em 60s, volta para a tag anterior.

set -euo pipefail

CLIENTE="${1:-}"
TAG="${2:-}"
BASE=/opt/seminario
DIR="$BASE/clientes/$CLIENTE"
LOG="$BASE/deploys.log"

[[ "$CLIENTE" =~ ^[a-z0-9-]+$ ]]     || { echo "Uso: deploy.sh <cliente> <tag>"; exit 2; }
[[ "$TAG"     =~ ^[0-9A-Za-z.-]+$ ]] || { echo "Tag inválida: $TAG"; exit 2; }
[[ -f "$DIR/.env" ]]                 || { echo "Cliente '$CLIENTE' não existe em $DIR"; exit 2; }

cd "$DIR"
ANTERIOR=$(grep '^TAG=' .env | cut -d= -f2)
CONTAINER="$CLIENTE-app"

registrar() { echo "$(date -Is) cliente=$CLIENTE de=$ANTERIOR para=$TAG resultado=$1" >> "$LOG"; }

aplicar() {
  sed -i "s/^TAG=.*/TAG=$1/" .env
  docker compose pull app
  docker compose up -d --no-deps app
}

esperar_saudavel() {
  for _ in $(seq 1 30); do
    STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "inexistente")
    [[ "$STATUS" == "healthy" ]] && return 0
    sleep 2
  done
  return 1
}

echo ">> [$CLIENTE] $ANTERIOR → $TAG"
aplicar "$TAG"

if esperar_saudavel; then
  echo ">> [$CLIENTE] saudável rodando $TAG"
  registrar "ok"
  docker image prune -f >/dev/null
else
  echo ">> [$CLIENTE] $TAG não ficou saudável. Voltando para $ANTERIOR"
  docker logs --tail 30 "$CONTAINER" || true
  aplicar "$ANTERIOR"
  registrar "rollback"
  exit 1
fi
