#!/usr/bin/env bash
# Compiles po/*.po into contents/locale/<lang>/LC_MESSAGES/<domain>.mo
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
domain="plasma_applet_com.github.rcspam.radioglobe"
for po in "$root"/po/*.po; do
  [ -f "$po" ] || continue
  lang=$(basename "$po" .po)
  out="$root/contents/locale/$lang/LC_MESSAGES"
  mkdir -p "$out"
  msgfmt --check -o "$out/$domain.mo" "$po"
  echo "built $out/$domain.mo"
done
