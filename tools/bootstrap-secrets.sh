#!/usr/bin/env bash
# Erzeugt Config/Secrets.xcconfig aus .env. Vor jedem Build / in CI ausführen.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "FEHLER: .env fehlt"; exit 1; }
set -a; . ./.env; set +a
cat > Config/Secrets.xcconfig <<XC
// GENERIERT von tools/bootstrap-secrets.sh — nicht committen.
STUDIP_CLIENT_ID = ${STUDIP_CLIENT_ID}
XC
chmod 600 Config/Secrets.xcconfig
echo "Config/Secrets.xcconfig geschrieben (client_id=${STUDIP_CLIENT_ID})"
