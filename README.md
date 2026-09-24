# RadioGlobe

A KDE Plasma 6 widget to explore live radio from all over the Earth.

After seeing [Radio Atlas](https://github.com/AksharP5/omarchy-radio-atlas) on Omarchy, I wanted the same idea as a Plasma widget. RadioGlobe is an independent plasmoid inspired by it (credited in [LICENSE](LICENSE)).

![RadioGlobe](screenshots/full.png)

## Features

Everything works as in Radio Atlas, the globe, the [Radio Browser](https://www.radio-browser.info/) directory, favorites, history, random tuning, volume and keyboard controls: see [its features](https://github.com/AksharP5/omarchy-radio-atlas#features). Its Omarchy-specific parts, such as the audio output picker, are not in the widget.

What RadioGlobe adds:

- A Plasma widget with a badge while playing, which you can even drive from its tooltip: the station, its title, the playback buttons and the volume. And of course a widget on the desktop.
- Sorting of the lists. The globe follows.
- During a search, or inside a country, the globe shows only those stations.
- A right-click menu on every station: copy the stream URL, open its homepage, vote for it on Radio Browser, show its properties.
- Night on Earth, shown on the globe.
- + / - zoom buttons, and wheel zoom on the point under the cursor.
- The local time where the station broadcasts, on a 12 or 24-hour clock.
- A sleep timer: stop playback in 15 minutes to 2 hours, or at a given time, after a 20-second fade out.
- The last station played is back in the player at startup, and can start on its own.
- Your own stations, placed on an OpenStreetMap view and optionally published to Radio Browser. Existing stations can be corrected locally.
- Favorites you can rename, and export and import of your favorites, history and settings.
- English and French, other languages welcome in `po/`.

## Requirements

- Plasma 6.1 or newer (developed and tested on Plasma 6.6 with Qt 6.10)
- [mpv](https://mpv.io/) and the [mpv-mpris](https://github.com/hoyon/mpv-mpris) script. Both are required: without mpv-mpris, mpv still plays but RadioGlobe has no way to drive it.

| | Debian / Ubuntu / Kubuntu | Arch Linux | Fedora |
|---|---|---|---|
| Player (required) | `mpv mpv-mpris` | `mpv mpv-mpris` | `mpv mpv-mpris` |
| Offline cache (recommended) | `qml6-module-qtquick-localstorage` | in `qt6-declarative` | in `qt6-qtdeclarative` |
| Map on the "Add a station" page (optional) | `qml6-module-qtlocation qt6-location-plugins` | `qt6-location` | `qt6-qtlocation` |

On openSUSE, the player packages are `mpv mpv-mpris` too.

**You do not have to check this by hand. At startup the widget looks for every module it uses and, if one is missing, shows a banner with the command to install it for your distribution.**

The settings page also says whether mpv and mpv-mpris were found. Without the offline cache, station lists are fetched again at every start. Without QtLocation, the "Add a station" page takes the latitude and longitude as numbers.

## Install

### From the KDE Store

In Plasma, open "Add Widgets…" from the panel or desktop menu, then "Get New Widgets…" and "Download New Plasma Widgets", and search for RadioGlobe.

### From a `.plasmoid` file

Download `radioglobe-<version>.plasmoid` from the [releases](https://github.com/rcspam/radioglobe/releases), then:

```bash
kpackagetool6 --type Plasma/Applet --install radioglobe-<version>.plasmoid
```

To upgrade, use `--upgrade` instead of `--install`.

### From the repository

```bash
scripts/package.sh
kpackagetool6 --type Plasma/Applet --install dist/radioglobe-<version>.plasmoid
```

`scripts/package.sh` compiles the translations and bundles only what the widget needs.

Then add RadioGlobe to a panel, the system tray or the desktop from Plasma's widget list.

## Controls

### Panel icon

| Mouse | Action |
|---|---|
| Left click | Open or close the popup |
| Middle click | Play a random station |
| Wheel | Change the volume (the direction can be inverted in the settings) |
| Right click | Plasma's widget menu, with "Random station" and "Stop and quit mpv" |

Hovering the icon shows the current station with previous / play-pause / next / stop / mute buttons and the volume.

### Keyboard (popup)

| Key | Action |
|---|---|
| `/` | Focus the search field |
| Up / Down | Move in the list |
| Enter | Play the selected station, or run the search if none is selected |
| Space | Play / pause |
| `R` | Play a random station |
| `F` | Add or remove the selected station from the favorites |
| `+` / `-` | Volume up / down |
| `M` | Mute |
| Escape | Clear the search, then leave the country, then close the popup |

### Good to know

- Holding down the stop button quits mpv, like "Stop and quit mpv".
- Double-clicking the station name in the player frames it on the globe.
- The mouse wheel zooms on the point under the cursor; the + / - buttons zoom about the centre.
- A click on the sea, the cross in the status line, Escape or the World tab leave the current country.
- The pin button ("Keep open") stops the popup from closing when it loses focus, so the list stays on screen while you work elsewhere.

## Sleep timer

The chronometer button opens the timer. Pick a duration, or type the time playback should stop: hours, then minutes, the colon comes by itself. A time already gone today means tomorrow. On a 12-hour clock, type "a" or "p" for AM or PM; without either, the timer takes the next time the clock shows that hour.

At the deadline the station fades out over 20 seconds and stops. While a timer runs, the button stays lit and its tooltip gives the stop time and what is left. The timer survives a Plasma restart; this can be turned off in the settings.

## Adding or fixing a station

The "+" button at the top of the popup opens the "Add a station" page of the settings. Give a name and a stream URL, and optionally a homepage, a country, tags and a location: search an address or a place, click the map, or type the coordinates. The station goes straight into your favorites.

The pencil button in the player opens the same page filled in with the playing station, to fix its details. Radio Browser does not allow editing an existing station, so your version stays in the widget: it replaces the Radio Browser one on the globe and in your favorites.

Tick "Also publish on Radio Browser" to share a new station with everyone. If a station with the same stream URL already exists there, nothing is published and the existing one goes into your favorites.

## Settings

- General: how many stations the globe loads, the zoom step, your home country (its located stations are always on the globe), approximate positions for stations without coordinates, the day and night shading, the list's sort and filters, what happens at startup, the sleep timer, the 12 or 24-hour clock, what next and previous walk through, the icon and its colours.
- Backup: Plasma forgets a widget's settings when the widget is removed from the panel. Export your favorites, history and options to a JSON file, and import them back later or on another computer.

## Data and privacy

- Station data comes from [Radio Browser](https://www.radio-browser.info/), a community-run, public-domain directory. RadioGlobe identifies itself to it with a `RadioGlobe/<version>` User-Agent, as its maintainers ask.
- Playing a station calls Radio Browser's click counter, which is how it ranks stations by popularity: it records that your IP address listened to that station. Turn "Report played stations to the click counter" off in the settings if you prefer.
- mpv fetches the audio streams directly from each broadcaster. Like any listener, the station sees your IP address.
- Country borders come from [Natural Earth](https://www.naturalearthdata.com/), public domain.
- Only while the "Add a station" page is open, its map loads tiles from [OpenStreetMap](https://www.openstreetmap.org/copyright) (© OpenStreetMap contributors), and an address search sends what you typed to [Nominatim](https://nominatim.org/). Publishing a station sends the form to Radio Browser.

## Troubleshooting

**mpv is not found**: the player shows a message with the install command for your distribution. Install mpv, or give the absolute path to it in the settings (for example `/usr/bin/mpv`, not `~/bin/mpv`).

**mpv-mpris is not found**: RadioGlobe starts mpv, waits a few seconds for it to show up on MPRIS, then stops it and shows how to install mpv-mpris. Once installed, `playerctl -l` should list `mpv` while a station plays.

**mpv keeps playing after Plasma restarts**: this is on purpose, so a Plasma crash or restart does not cut the radio. The widget finds mpv again on its own. To stop it for good, use "Stop and quit mpv" or hold down the stop button.

**Radio Browser is unreachable**: RadioGlobe shows the stations it cached last time, with a Retry button. Opening the popup again retries too.

**A station won't play**: some entries of the directory are dead even after Radio Browser's own checks. If no sound starts within about 15 seconds, the player shows an error with a retry button. A stream cut while playing is reopened once, silently, before an error shows.

## Development

```bash
tests/run                    # node unit tests, qmllint, qmlformat check, qmltestrunner
scripts/build-translations.sh
scripts/extract-messages.sh  # refresh po/ after changing texts
plasmoidviewer -a .          # live preview
scripts/package.sh           # builds dist/radioglobe-<version>.plasmoid
```

Install the `.plasmoid` built by `scripts/package.sh` rather than the checkout itself: `kpackagetool6 --install .` would copy the tests, the docs and `.git` into your widget directory.

## Credits

- [Radio Atlas](https://github.com/AksharP5/omarchy-radio-atlas) by Akshar Patel (MIT), for the globe rendering and the station model this project started from
- [Radio Browser](https://www.radio-browser.info/), for the station data
- [Natural Earth](https://www.naturalearthdata.com/), for the country borders

## License

MIT, with the copyright shared between Akshar Patel (the Radio Atlas code reused here) and rcspam (RadioGlobe). See [LICENSE](LICENSE).
