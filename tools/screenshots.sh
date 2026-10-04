#!/usr/bin/env bash
# Nimmt die Bildschirmfotos für den App Store im Simulator auf - im
# Demo-Modus, je Sprache und Gerät, ohne Hand am Gerät.
#
# Läuft auf Codemagic (Workflow `screenshots`), nachdem die App für den
# Simulator gebaut ist. Den Weg durch die App gehen keine UI-Tests, sondern
# zwei Bordmittel:
#   * Startargumente füllen UserDefaults (NSArgumentDomain): Demo an,
#     Nutzungsbedingungen angenommen, Einführung gesehen, Sprache gesetzt.
#   * `simctl openurl studgo://<reiter>` schaltet den Reiter um - dieselben
#     Adressen, die die Widgets benutzen (`NotificationRouter.route(url:)`).
#
#   ./tools/screenshots.sh [Sprachen…]     # Vorgabe: de en
#
# Ergebnis: build/screenshots/<sprache>/<gerät>/<nr>-<reiter>.png
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BUNDLE_ID="de.maxaufknax.studgo"
OUT="build/screenshots"
LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=(de en)

APP="$(find build/dd/Build/Products -path '*Debug-iphonesimulator/StudGo.app' -maxdepth 3 | head -1)"
[ -d "$APP" ] || { echo "StudGo.app für den Simulator fehlt - erst bauen." >&2; exit 1; }

# Neueste iOS-Laufzeit und die größten Geräte, die dieses Xcode kennt. Die
# Namen wechseln mit jeder Xcode-Fassung (iPhone 16 → 17 …), deshalb gesucht
# statt fest eingetragen.
RUNTIME="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rs = [r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and r["platform"] == "iOS"]
print(sorted(rs, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')"
pick() {
    xcrun simctl list devicetypes -j | python3 -c "
import json, sys, re
want = sys.argv[1]
types = [t for t in json.load(sys.stdin)['devicetypes'] if re.search(want, t['name'])]
print(types[-1]['identifier'] if types else '')" "$1"
}
IPHONE_TYPE="$(pick 'iPhone [0-9]+ Pro Max')"
IPAD_TYPE="$(pick 'iPad Pro 13-inch')"
echo "Laufzeit: $RUNTIME"
echo "Geräte:   $IPHONE_TYPE | $IPAD_TYPE"

shoot_device() {
    local type="$1" label="$2"
    [ -n "$type" ] || { echo "!! kein Gerätetyp für $label"; return 0; }
    local udid
    udid="$(xcrun simctl create "shot-$label" "$type" "$RUNTIME")"
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl ui "$udid" appearance light
    xcrun simctl status_bar "$udid" override --time "9:41" \
        --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 \
        --batteryState charged --batteryLevel 100
    xcrun simctl install "$udid" "$APP"

    for lang in "${LANGS[@]}"; do
        local locale="de_DE"
        [ "$lang" = "en" ] && locale="en_US"
        local dir="$OUT/$lang/$label"
        mkdir -p "$dir"
        xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
        xcrun simctl launch "$udid" "$BUNDLE_ID" \
            -AppleLanguages "($lang)" -AppleLocale "$locale" \
            -studgo.demo.active YES \
            -studgo.moderation.termsVersion 1 \
            -studgo.onboarding.seen.v1 YES >/dev/null
        # Die Demo lädt aus der App selbst, braucht aber einen Augenblick für
        # Zusammenführung und erste Darstellung.
        sleep 8
        xcrun simctl io "$udid" screenshot "$dir/1-heute.png" >/dev/null
        local n=2
        for tab in plan kurse postfach campus; do
            xcrun simctl openurl "$udid" "studgo://$tab"
            sleep 4
            xcrun simctl io "$udid" screenshot "$dir/$n-$tab.png" >/dev/null
            n=$((n + 1))
        done
        echo "✔ $label/$lang: $(ls "$dir" | wc -l | tr -d ' ') Aufnahmen"
    done

    xcrun simctl shutdown "$udid" || true
    xcrun simctl delete "$udid" || true
}

shoot_device "$IPHONE_TYPE" iphone
shoot_device "$IPAD_TYPE" ipad
find "$OUT" -name '*.png' | sort
