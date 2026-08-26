#!/usr/bin/env bash
# Prüft alle Swift-Quellen auf Syntaxfehler — auch die SwiftUI-Ansichten.
#
# Löst tools/swift-sanity.py ab. Jenes zählte Klammern mit einem
# selbstgeschriebenen Zerteiler, weil auf dem Homeserver kein Compiler lag.
# Der liegt jetzt da: `swiftc -parse` prüft die vollständige Grammatik und
# braucht dafür kein SDK — es löst keine Importe auf, `import SwiftUI` stört
# also nicht. Damit fällt auf, was eine Klammernzählung nie sah: fehlende
# Kommas, verrutschte `where`-Klauseln, ungültige Attribute, kaputte
# Ergebniserbauer.
#
# Läuft überall: auf macOS mit dem systemeigenen swiftc, sonst im Container.
#
#   ./tools/swift-lint.sh            # App/ prüfen
#   ./tools/swift-lint.sh App/Core   # nur einen Teil
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
TARGET="${1:-App}"

mapfile -t FILES < <(find "$TARGET" -name '*.swift' | sort)
if [ ${#FILES[@]} -eq 0 ]; then
    echo "Keine Swift-Dateien unter $TARGET" >&2
    exit 1
fi

# Auf Codemagic (macOS) steht swiftc bereit; auf dem Server nimmt der Wrapper
# den Container. Beide Wege prüfen dieselbe Grammatik.
if command -v swiftc >/dev/null 2>&1; then
    OUT=$(swiftc -parse "${FILES[@]}" 2>&1) && STATUS=0 || STATUS=$?
else
    OUT=$("$ROOT/tools/swift.sh" -- swiftc -parse "${FILES[@]}" 2>&1) && STATUS=0 || STATUS=$?
fi

if [ "$STATUS" -ne 0 ]; then
    echo "$OUT"
    echo
    echo "✘ Syntaxfehler in ${#FILES[@]} geprüften Dateien — Build würde scheitern." >&2
    exit 1
fi

# Warnungen sind kein Abbruchgrund, aber sie sollen sichtbar sein.
if echo "$OUT" | grep -q 'warning:'; then
    echo "$OUT" | grep 'warning:' | sort -u
    echo
fi
echo "✔ ${#FILES[@]} Dateien syntaktisch in Ordnung."
