#!/bin/sh
# Installs the `astromech` command as a compiled executable (~0.1 s start, vs ~0.7 s
# for `dart pub global activate`, which re-resolves on every run).
# Target: $ASTROMECH_BIN, default ~/.pub-cache/bin (already on PATH for Dart users).
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${ASTROMECH_BIN:-$HOME/.pub-cache/bin}"

# A pub-global shim with the same name would shadow or be replaced by this binary.
dart pub global deactivate astromech >/dev/null 2>&1 || true

mkdir -p "$BIN"
cd "$ROOT" && dart pub get >/dev/null
dart compile exe "$ROOT/packages/astromech/bin/astromech.dart" -o "$BIN/astromech" >/dev/null
echo "Installed $BIN/astromech ($("$BIN/astromech" --version))"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add $BIN to your PATH." ;; esac
