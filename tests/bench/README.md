# Globe benchmark

Not part of `tests/run`. Two measurements:

- `bash tests/bench/run.sh`: CPU time of an offscreen process for each scene, 300 frames each; subtract the `nopaint` line. The `powersave` governor moves the figures by 30 %: compare the baseline and the candidate in turns, three rounds, never a single run.
- `bash tests/bench/drag.sh [cx cy]`: start `plasmoidviewer -a <checkout> -f planar -s 1600x1100`, find the centre of the globe on a full-screen capture (as fractions of the screen), and keep the mouse still during the measurement.
