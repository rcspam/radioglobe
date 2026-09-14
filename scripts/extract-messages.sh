#!/usr/bin/env bash
# Regenerates po/template.pot from every i18n() call and merges it into the
# existing po files. Requires gettext (xgettext, msgmerge).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pot="$root/po/template.pot"
mkdir -p "$root/po"
find "$root/contents" \( -name '*.qml' -o -name '*.js' \) -print | sort > "$root/po/.files"
xgettext --from-code=UTF-8 --language=JavaScript \
  --package-name="RadioGlobe" --msgid-bugs-address="https://github.com/rcspam/radioglobe/issues" \
  --add-comments=TRANSLATORS --sort-output --no-wrap \
  --keyword=i18n --keyword=i18nc:1c,2 --keyword=i18np:1,2 --keyword=i18ncp:1c,2,3 \
  --files-from="$root/po/.files" --output="$pot"
rm -f "$root/po/.files"
for po in "$root"/po/*.po; do
  [ -f "$po" ] && msgmerge --update --backup=none --no-wrap "$po" "$pot"
done
echo "updated $pot"
