#!/usr/bin/env bash
# Creates the hermes-secrets Kubernetes Secret from local Hermes config files.
# Run this ONCE on a machine with kubectl access to the cluster.
# The Secret is intentionally NOT managed by Helm/ArgoCD to keep tokens out of git.
#
# Prerequisites:
#   - kubectl configured (e.g. ~/.kube/config points to the Pi5 cluster)
#   - ~/.hermes/.env exists with TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USERS
#   - ~/.hermes/auth/google_oauth.json exists (run `hermes setup model` first)
#
# Usage:
#   chmod +x setup-secrets.sh
#   ./setup-secrets.sh

set -euo pipefail

NAMESPACE="hermes"
SECRET_NAME="hermes-secrets"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

# ── Read values ────────────────────────────────────────────────────────────────

TELEGRAM_BOT_TOKEN=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$HERMES_HOME/.env" | cut -d= -f2-)
TELEGRAM_ALLOWED_USERS=$(grep -E '^TELEGRAM_ALLOWED_USERS=' "$HERMES_HOME/.env" | cut -d= -f2-)
GOOGLE_OAUTH_JSON=$(cat "$HERMES_HOME/auth/google_oauth.json")
DASHBOARD_TOKEN=$(grep -E '^HERMES_DASHBOARD_SESSION_TOKEN=' "$HERMES_HOME/.env" | cut -d= -f2- || true)
if [[ -z "$DASHBOARD_TOKEN" ]]; then
  DASHBOARD_TOKEN=$(python3 -c "import secrets; print(secrets.token_hex(32))")
  echo "HERMES_DASHBOARD_SESSION_TOKEN=$DASHBOARD_TOKEN" >> "$HERMES_HOME/.env"
  echo "Generated new dashboard token and saved to $HERMES_HOME/.env"
fi

if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN not found in $HERMES_HOME/.env" >&2
  exit 1
fi

if [[ ! -f "$HERMES_HOME/auth/google_oauth.json" ]]; then
  echo "ERROR: $HERMES_HOME/auth/google_oauth.json not found." >&2
  echo "       Run 'hermes setup model' and complete Google OAuth first." >&2
  exit 1
fi

# ── Create namespace if needed ─────────────────────────────────────────────────

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── Create / update the Secret ─────────────────────────────────────────────────

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal="TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" \
  --from-literal="TELEGRAM_ALLOWED_USERS=$TELEGRAM_ALLOWED_USERS" \
  --from-literal="HERMES_AUTH_JSON_BOOTSTRAP=$GOOGLE_OAUTH_JSON" \
  --from-literal="HERMES_DASHBOARD_SESSION_TOKEN=$DASHBOARD_TOKEN" \
  --save-config \
  --dry-run=client -o yaml \
  | kubectl apply -f -

echo ""
echo "Secret '$SECRET_NAME' created/updated in namespace '$NAMESPACE'."
echo "Google OAuth token expires: $(echo "$GOOGLE_OAUTH_JSON" | python3 -c "
import sys, json, datetime
d = json.load(sys.stdin)
exp = d.get('expires', 0)
dt = datetime.datetime.fromtimestamp(exp / 1000)
print(dt.strftime('%Y-%m-%d %H:%M UTC'))
" 2>/dev/null || echo 'unknown')"
echo ""
echo "NOTE: Re-run this script after refreshing the Google OAuth token"
echo "      (tokens expire ~1 hour; the refresh token lasts until revoked)."
