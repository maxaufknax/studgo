#!/usr/bin/env bash
# Richtet den Codemagic-Zugang ein. Einzige Eingabe: der API-Schlüssel.
#
# Den Schlüssel gibt es unter https://codemagic.io/teams  →  Personal Account
#   →  Integrations  →  Codemagic API  →  Show/Generate token
#
# Das Skript prüft ihn gegen die API, sucht die StudGo-Anwendung selbst
# heraus, liest die Workflow-Kennungen aus codemagic.yaml und legt alles in
# .secrets/codemagic.json ab (von .gitignore erfasst, Rechte 600).
#
#   ./tools/codemagic-setup.sh              # fragt interaktiv nach dem Key
#   CM_TOKEN=xxx ./tools/codemagic-setup.sh # oder aus der Umgebung
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONF="$ROOT/.secrets/codemagic.json"
API="https://api.codemagic.io"

for tool in curl jq; do
    command -v "$tool" >/dev/null || { echo "FEHLER: $tool wird gebraucht." >&2; exit 1; }
done

# --- 1. Schlüssel einlesen -------------------------------------------------
TOKEN="${CM_TOKEN:-}"
if [ -z "$TOKEN" ]; then
    echo "Codemagic-API-Schlüssel einfügen (Eingabe bleibt unsichtbar):"
    echo "  zu finden unter https://codemagic.io/teams → Integrations → Codemagic API"
    read -rsp "  Schlüssel: " TOKEN
    echo
fi
TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
[ -n "$TOKEN" ] || { echo "FEHLER: kein Schlüssel eingegeben." >&2; exit 1; }

# --- 2. Gegen die API prüfen ----------------------------------------------
echo "Prüfe Schlüssel …"
BODY=$(mktemp); trap 'rm -f "$BODY"' EXIT
CODE=$(curl -sS -o "$BODY" -w '%{http_code}' -H "x-auth-token: $TOKEN" "$API/apps")

case "$CODE" in
    200) ;;
    401|403) echo "FEHLER: Schlüssel abgelehnt (HTTP $CODE). Neu erzeugen und erneut versuchen." >&2; exit 1 ;;
    *)   echo "FEHLER: unerwartete Antwort HTTP $CODE:" >&2; head -c 400 "$BODY" >&2; echo >&2; exit 1 ;;
esac

# Codemagic liefert {"applications":[…]}. Sollte sich das je ändern, fällt es
# hier auf, statt später beim Bauen.
if ! jq -e '.applications' "$BODY" >/dev/null 2>&1; then
    echo "FEHLER: unerwartetes Antwortformat — hier die rohe Antwort:" >&2
    head -c 600 "$BODY" >&2; echo >&2; exit 1
fi

COUNT=$(jq '.applications | length' "$BODY")
echo "✔ Schlüssel gültig — $COUNT Anwendung(en) sichtbar."

# --- 3. StudGo heraussuchen ------------------------------------------------
# Erst über den Git-Remote (eindeutig), sonst über den Namen.
REMOTE=$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo "")
SLUG=$(printf '%s' "$REMOTE" | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')

APP=$(jq --arg slug "$SLUG" '
    [ .applications[]
      | select( ((.repository.htmlUrl // "") | ascii_downcase | contains($slug | ascii_downcase))
                or ((.appName // "") | ascii_downcase | contains("studgo")) ) ] | first // empty
' "$BODY")

if [ -z "$APP" ]; then
    echo "Keine Anwendung passte zu \"$SLUG\" oder \"studgo\". Vorhanden sind:" >&2
    jq -r '.applications[] | "  \(._id)  \(.appName)"' "$BODY" >&2
    read -rp "  Anwendungs-Kennung von oben einfügen: " APP_ID
    APP_NAME="(manuell gewählt)"
else
    APP_ID=$(printf '%s' "$APP" | jq -r '._id')
    APP_NAME=$(printf '%s' "$APP" | jq -r '.appName')
    echo "✔ Anwendung gefunden: $APP_NAME  ($APP_ID)"
fi
[ -n "${APP_ID:-}" ] || { echo "FEHLER: keine Anwendungs-Kennung." >&2; exit 1; }

# --- 4. Workflows aus codemagic.yaml lesen ---------------------------------
# Die Kennungen sind dort schlicht die Schlüssel unter `workflows:`.
WORKFLOWS=$(python3 - <<'PY'
import re, json, pathlib
text = pathlib.Path("codemagic.yaml").read_text(encoding="utf-8")
body = text.split("\nworkflows:", 1)[1] if "\nworkflows:" in text else ""
names = re.findall(r"^  ([A-Za-z0-9_-]+):\s*$", body, re.M)
print(json.dumps(names))
PY
)
echo "✔ Workflows aus codemagic.yaml: $(printf '%s' "$WORKFLOWS" | jq -r 'join(", ")')"

BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)

# --- 5. Ablegen ------------------------------------------------------------
mkdir -p "$(dirname "$CONF")"
umask 077
jq -n --arg token "$TOKEN" --arg appId "$APP_ID" --arg appName "$APP_NAME" \
      --arg branch "$BRANCH" --argjson workflows "$WORKFLOWS" \
   '{token: $token, appId: $appId, appName: $appName,
     defaultWorkflow: ($workflows[0] // "check"), defaultBranch: $branch,
     workflows: $workflows}' > "$CONF"
chmod 600 "$CONF"

echo
echo "✔ Fertig. Zugang liegt in .secrets/codemagic.json (Rechte 600, nicht im Git)."
echo
echo "  Ab jetzt:"
echo "    ./tools/codemagic.sh build          # Build anstoßen und mitverfolgen"
echo "    ./tools/codemagic.sh status         # letzten Build zeigen"
echo "    ./tools/codemagic.sh errors         # Compilerfehler des letzten Builds"
