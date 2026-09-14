#!/usr/bin/env bash
# Builds radioglobe-<version>.plasmoid (a zip with metadata.json at the root).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
version=$(python3 -c "import json;print(json.load(open('$root/metadata.json'))['KPlugin']['Version'])")
"$root/scripts/build-translations.sh"
out="$root/dist/radioglobe-$version.plasmoid"
mkdir -p "$root/dist"
rm -f "$out"
(cd "$root" && zip -qr "$out" metadata.json contents LICENSE README.md)
echo "built $out"
