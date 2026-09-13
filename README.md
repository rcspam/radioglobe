# RadioGlobe

A KDE Plasma 6 widget for exploring live radio stations on a rotatable globe and playing them through mpv.

## Requirements

- mpv
- mpv-mpris

## Install

```bash
kpackagetool6 --type Plasma/Applet --install .
```

## Development

```bash
tests/run
plasmoidviewer -a .
```
