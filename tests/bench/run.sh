#!/usr/bin/env bash
# Process CPU per situation, 300 painted frames each (5 x 60). The no-paint
# run is the baseline to subtract. Frequency scaling makes a single run
# meaningless: run it for the base and the candidate alternately, 3 times.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QML_XHR_ALLOW_FILE_READ=1
log=${BENCH_LOG:-/tmp/radioglobe-bench.log}
for fn in nopaint empty nostations nocountries full zoomed; do
  /usr/bin/time -f "$fn: cpu=%Us+%Ss" \
    dbus-run-session -- /usr/lib/qt6/bin/qmltestrunner -input "$root/tests/bench/tst_bench.qml" "Bench::test_$fn" > "$log" 2>&1 || true
  grep -h "cpu=" "$log"
  grep -h "BENCH" "$log" | sed 's/.*BENCH/  /'
done
