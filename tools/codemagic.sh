#!/usr/bin/env bash
# Codemagic von der Kommandozeile: Build anstoßen, Status verfolgen,
# Compilerfehler zurückholen — ohne die Weboberfläche.
#
# Der Zweck ist die geschlossene Schleife: committen, bauen lassen, Fehler
# lesen, nachbessern. Wer autonom entwickelt, soll den Fehlschlag selbst
# sehen, statt danach zu fragen.
#
# Voraussetzung: einmalig ./tools/codemagic-setup.sh
#
#   ./tools/codemagic.sh build [workflow] [branch]  # anstoßen + mitverfolgen
#   ./tools/codemagic.sh start [workflow] [branch]  # nur anstoßen
#   ./tools/codemagic.sh status [buildId]           # Zustand
#   ./tools/codemagic.sh watch  [buildId]           # bis zum Ende verfolgen
#   ./tools/codemagic.sh errors [buildId]           # nur die Fehlerzeilen
#   ./tools/codemagic.sh log    [buildId]           # ganzes xcodebuild-Log
#   ./tools/codemagic.sh list                       # letzte Builds
#
# Rückgabewert von build/watch: 0 wenn der Build durchlief, sonst 1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$ROOT/.secrets/codemagic.json"
API="https://api.codemagic.io"
POLL="${CM_POLL_SECONDS:-20}"

[ -f "$CONF" ] || { echo "FEHLER: $CONF fehlt — erst ./tools/codemagic-setup.sh laufen lassen." >&2; exit 1; }
TOKEN=$(jq -r .token "$CONF")
APP_ID=$(jq -r .appId "$CONF")

api() { curl -sS -H "x-auth-token: $TOKEN" "$@"; }

# Kennung des jüngsten Builds, falls keine angegeben wurde.
latest_id() {
    api "$API/builds?appId=$APP_ID&limit=1" | jq -r '.builds[0]._id // empty'
}

resolve_id() {
    if [ -n "${1:-}" ]; then printf '%s' "$1"; else
        local id; id=$(latest_id)
        [ -n "$id" ] || { echo "FEHLER: kein Build gefunden." >&2; exit 1; }
        printf '%s' "$id"
    fi
}

build_json() { api "$API/builds/$1"; }

# --- Build anstoßen --------------------------------------------------------
cmd_start() {
    local wf="${1:-$(jq -r .defaultWorkflow "$CONF")}"
    local br="${2:-$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)}"
    echo "Stoße an: workflow=$wf branch=$br" >&2
    local resp; resp=$(api -X POST -H 'Content-Type: application/json' \
        -d "$(jq -n --arg a "$APP_ID" --arg w "$wf" --arg b "$br" \
              '{appId:$a, workflowId:$w, branch:$b}')" "$API/builds")
    local id; id=$(printf '%s' "$resp" | jq -r '.buildId // empty')
    if [ -z "$id" ]; then
        echo "FEHLER: kein buildId in der Antwort:" >&2
        printf '%s\n' "$resp" | head -c 600 >&2; echo >&2; exit 1
    fi
    echo "$id"
}

# --- Zustand ---------------------------------------------------------------
cmd_status() {
    local id; id=$(resolve_id "${1:-}")
    build_json "$id" | jq -r '.build |
        "Build   \(._id)\nWorkflow \(.workflowId // "?")\nBranch  \(.branch // "?")\nStatus  \(.status)\nGestartet \(.startedAt // "—")\nURL     https://codemagic.io/app/\(.appId)/build/\(._id)"'
}

# --- Bis zum Ende verfolgen ------------------------------------------------
cmd_watch() {
    local id; id=$(resolve_id "${1:-}")
    echo "Verfolge Build $id (alle ${POLL}s) …" >&2
    local last=""
    while :; do
        local st; st=$(build_json "$id" | jq -r '.build.status // "unbekannt"')
        [ "$st" != "$last" ] && { echo "  [$(date +%H:%M:%S)] $st" >&2; last="$st"; }
        case "$st" in
            finished)                 echo "✔ Build durchgelaufen." >&2; return 0 ;;
            failed|timeout|canceled|skipped)
                                      echo "✘ Build: $st" >&2; cmd_errors "$id" || true; return 1 ;;
            unbekannt)                echo "FEHLER: Zustand nicht lesbar." >&2; return 1 ;;
        esac
        sleep "$POLL"
    done
}

# --- Log holen -------------------------------------------------------------
# Der check-Workflow legt build/logs/xcodebuild.log als Artefakt ab; von dort
# kommt das Log. Gibt es keins (Abbruch vor dem Bauen), sagt das Skript das.
fetch_log() {
    local id="$1"
    local url; url=$(build_json "$id" | jq -r '
        (.build.artefacts // []) | map(select(.name | test("\\.log$"))) | .[0].url // empty')
    if [ -z "$url" ]; then
        echo "Kein Log-Artefakt an Build $id — Lauf brach vermutlich vor dem Bauen ab." >&2
        echo "Weboberfläche: https://codemagic.io/app/$APP_ID/build/$id" >&2
        return 1
    fi
    api -L "$url"
}

cmd_log()    { fetch_log "$(resolve_id "${1:-}")"; }

cmd_errors() {
    local id; id=$(resolve_id "${1:-}")
    local log; log=$(fetch_log "$id") || return 1
    local errs; errs=$(printf '%s\n' "$log" | grep -E '(error|fehler):' | sed 's|/Users/builder/clone/||' | sort -u)
    if [ -z "$errs" ]; then
        echo "Keine Compilerfehler im Log — Ursache liegt woanders (Signatur, Upload, Skript)." >&2
        printf '%s\n' "$log" | tail -30
        return 1
    fi
    printf '%s\n' "$errs"
}

cmd_list() {
    api "$API/builds?appId=$APP_ID&limit=${1:-10}" \
      | jq -r '.builds[] | "\(.startedAt // "—")  \(.status)\t\(.workflowId // "?")\t\(.branch // "?")\t\(._id)"'
}

cmd_build() {
    local id; id=$(cmd_start "${1:-}" "${2:-}")
    echo "$id"
    cmd_watch "$id"
}

case "${1:-status}" in
    start)  shift; cmd_start  "${1:-}" "${2:-}" ;;
    build)  shift; cmd_build  "${1:-}" "${2:-}" ;;
    status) shift; cmd_status "${1:-}" ;;
    watch)  shift; cmd_watch  "${1:-}" ;;
    errors) shift; cmd_errors "${1:-}" ;;
    log)    shift; cmd_log    "${1:-}" ;;
    list)   shift; cmd_list   "${1:-}" ;;
    *)      sed -n '2,22p' "$0" | sed 's|^# \?||' ; exit 1 ;;
esac
