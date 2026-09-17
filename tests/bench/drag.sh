#!/usr/bin/env bash
# CPU of plasmoidviewer while the globe is dragged back and forth by dotool
# (dotoold must be running). Arguments: the globe centre as fractions of the
# screen, found on a full-screen screenshot. Do not touch the mouse meanwhile.
set -euo pipefail
cx=${1:-0.397}; cy=${2:-0.50}
pid=$(pgrep -x plasmoidviewer | tail -1)
t0=$(ps -o cputimes= -p "$pid"); w0=$(date +%s.%N)
echo "mouseto $cx $cy" | dotoolc; sleep 0.3
echo "buttondown left" | dotoolc; sleep 0.1
for round in 1 2 3; do
  for i in $(seq 0 40) $(seq 40 -1 0); do
    echo "mouseto $(python3 -c "print($cx + 0.0025 * $i)") $cy" | dotoolc; sleep 0.02
  done
done
echo "buttonup left" | dotoolc
t1=$(ps -o cputimes= -p "$pid"); w1=$(date +%s.%N)
python3 -c "print('drag: cpu=%ss wall=%.1fs -> %.0f%% of a core' % ($t1 - $t0, $w1 - $w0, 100 * ($t1 - $t0) / ($w1 - $w0)))"
