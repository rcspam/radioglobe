# Banc de mesure du globe

Hors de `tests/run`. Deux mesures :

- `bash tests/bench/run.sh` : CPU processus hors écran par situation, 300 frames chacune ; soustraire la ligne `nopaint`. Le gouverneur `powersave` fait varier les chiffres de 30 % : comparer base et candidat en alternance, trois tours, jamais une mesure seule.
- `bash tests/bench/drag.sh [cx cy]` : lancer `plasmoidviewer -a <racine> -f planar -s 1600x1100`, repérer le centre du globe sur une capture plein écran (fractions de l'écran), ne pas toucher la souris pendant la mesure.
