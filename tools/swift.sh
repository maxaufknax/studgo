#!/usr/bin/env bash
# Führt die Swift-Toolchain im Container aus.
#
# Auf dem Homeserver gibt es keinen Swift-Compiler, und es soll auch keiner
# installiert werden: ein Image ist in Sekunden ausgetauscht, eine
# Systeminstallation nicht. Gebaut wird damit `StudGoKit` — die Schicht aus
# App/Core und App/Models, die ohne Apple-Frameworks auskommt. Die Views
# bleiben Xcode vorbehalten, dafür gibt es tools/swift-lint.sh.
#
#   ./tools/swift.sh build            # StudGoKit übersetzen
#   ./tools/swift.sh test             # Tests laufen lassen
#   ./tools/swift.sh test --filter ICS
#   ./tools/swift.sh -- swiftc -parse App/Features/TimetableView.swift
#
# SWIFT_IMAGE überschreibt die Toolchain, etwa zum Prüfen einer neueren.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${SWIFT_IMAGE:-swift:6.2-noble}"

# SwiftPM legt Zwischenstände unter $HOME ab. Ohne eigenes HOME landen sie
# entweder im Container-Nirwana oder — schlimmer — als root im Arbeitsbaum.
CACHE="$ROOT/.swiftpm-home"
mkdir -p "$CACHE"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Toolchain $IMAGE fehlt, wird geholt …" >&2
    docker pull "$IMAGE"
fi

# --user: sonst gehört .build hinterher root und der nächste Lauf scheitert.
# TZ: ohne das läuft der Container auf UTC, und jeder Test, der Wochentage
#     oder Vorlesungszeiten prüft, kippt an der Zeitzone statt an der Logik.
run() {
    docker run --rm -i \
        --user "$(id -u):$(id -g)" \
        -e HOME=/w/.swiftpm-home \
        -e TZ="${TZ:-Europe/Berlin}" \
        -v "$ROOT":/w -w /w \
        "$IMAGE" "$@"
}

case "${1:-test}" in
    --)     shift; run "$@" ;;
    build)  shift; run swift build "$@" ;;
    test)   shift; run swift test "$@" ;;
    clean)  run rm -rf /w/.build ;;
    *)      run swift "$@" ;;
esac
