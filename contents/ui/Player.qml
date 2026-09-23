import QtQuick
import "RadioModel.js" as RadioModel

// Drives an external mpv through Plasma's MPRIS model. Owns the playback state
// machine: mpv-mpris 0.7.1 reports a wrong PlaybackStatus after OpenUri from
// idle, so `state` is authoritative and MPRIS status is only an input.
// Every dependency (mpris model, exec, cfg) is injected.
Item {
    id: root

    visible: false

    property var mpris: null
    property var exec: null
    property var cfg: null
    property string userAgent: "RadioGlobe"
    property int loadTimeoutMs: 15000
    // A cold mpv start (disk cache, audio device probing) regularly needs more
    // than 3 s before mpv-mpris registers on the bus.
    property int attachTimeoutMs: 8000
    property int probeMs: 1500
    property int staleTimeoutMs: 5000
    // How often a stream error is re-checked against mpv's own position.
    property int recoveryMs: 4000
    // After a transient volume ends, how long mpv's late echoes of the
    // lowered levels are still ignored.
    property int volumeHoldMs: 1000

    readonly property int statusStopped: 1
    readonly property int statusPlaying: 2
    readonly property int statusPaused: 3

    readonly property string state: root._state
    readonly property var station: root._station
    readonly property string track: root._track
    readonly property real volume: root._volume
    readonly property bool muted: root._muted
    readonly property string errorKind: root._errorKind
    readonly property bool attached: root._player !== null

    signal playingStarted(var station)

    property string _state: "idle"
    property var _station: null
    property string _track: ""
    property real _volume: 0.75
    property bool _muted: false
    property real _volumeBeforeMute: 0.75
    property string _errorKind: ""
    // Silent reopenings of the current station after an unexpected Stopped
    // since the last successful load. One is allowed: servers cut streams and
    // the HTTP reconnect does not catch every case (playlists, redirects).
    property int _streamRetries: 0
    readonly property int maxStreamRetries: 1
    property var _player: null
    property var _pendingStation: null
    property bool _userStopping: false
    // Title the container was showing when the current OpenUri went out: mpv
    // keeps the previous station's metadata until the new stream sends its own.
    property string _trackAtOpen: ""
    // Last position seen while loading, in microseconds. -1 until the first
    // poll answers, so the very first sample is never read as progress.
    property real _positionSample: -1
    // Set while the Pause/Play of _loaded() is in flight: the Paused mpv
    // echoes back is ours, and must not read as the user pausing.
    property bool _statusToggle: false
    // True while mpv plays at a level that is not the user's (sleep timer
    // fade), and for volumeHoldMs after: its volume echoes are not a setting.
    property bool _volumeHeld: false
    property var _connectedModel: null
    property int _launchEpoch: 0

    onMprisChanged: {
        root._watchModel();
        // A model that arrives after the player was created still needs a scan.
        root.rescan();
    }
    Component.onCompleted: {
        root._watchModel();
        if (root.cfg)
            root._volume = root._clamp(Number(root.cfg.volume));
        root.rescan();
        if (root.currentPid() > 0 && !root._player)
            staleTimer.start();
    }

    // Read on demand: cfg may be a plain object whose writes notify nothing.
    function currentPid() {
        return root.cfg ? Number(root.cfg.mpvPid) || 0 : 0;
    }

    function play(station) {
        if (!station || !station.url)
            return;
        loadTimer.stop();
        probeTimer.stop();
        root._station = station;
        root._track = "";
        root._errorKind = "";
        root._userStopping = false;
        root._streamRetries = 0;
        if (root._state === "starting") {
            // mpv is already being launched: the attach will open this station.
            root._pendingStation = station;
            return;
        }
        if (root._player) {
            root._openUri();
            return;
        }
        root._pendingStation = station;
        root._ensureMpv();
    }

    // Reattached to an mpv that outlived plasmashell: remember which station it
    // is playing without restarting anything.
    function adoptStation(station) {
        if (station && station.url && !root._station) {
            root._station = station;
            root._updateTrack();
        }
    }

    // Autoplay at startup: the restored station, unless an mpv that outlived
    // plasmashell is already playing something.
    function startIfIdle() {
        if (root._state === "idle" && root._station && !root._player)
            root.play(root._station);
    }

    function retry() {
        if (root._station)
            root.play(root._station);
    }

    function pause() {
        if (!root._player || root._state !== "playing")
            return;
        root._player.Pause();
        root._setState("paused");
    }

    function resume() {
        if (!root._player) {
            // The station restored at startup, with no mpv yet: Play starts it.
            if (root._station)
                root.play(root._station);
            return;
        }
        if (root._state === "paused") {
            root._player.Play();
            root._setState("playing");
        } else if (root._state === "stopped" || root._state === "error") {
            root.retry();
        }
    }

    function togglePause() {
        if (root._state === "playing")
            root.pause();
        else
            root.resume();
    }

    function stop() {
        loadTimer.stop();
        probeTimer.stop();
        root._userStopping = true;
        // A stop issued while mpv is still starting must not turn into a play
        // when the container finally shows up.
        root._pendingStation = null;
        if (root._player) {
            if (!root._player.canStop) {
                // Fake status: bring the container to Playing so Stop() is honoured.
                root._player.Pause();
                root._player.Play();
            }
            root._player.Stop();
        }
        root._setState("stopped");
    }

    function quit() {
        loadTimer.stop();
        probeTimer.stop();
        attachTimer.stop();
        staleTimer.stop();
        root._userStopping = true;
        root._pendingStation = null;
        if (root._player) {
            root._player.Quit();
        } else if (root.currentPid() > 0 && root.exec) {
            // Launched but never seen on the bus: only its PID can stop it.
            root.exec("kill " + root.currentPid(), function () {});
        }
        root._detach();
        root._setPid(0);
        root._setState("idle");
    }

    function setVolume(value) {
        const level = root._clamp(Number(value));
        root._volume = level;
        root._muted = false;
        if (root.cfg)
            root.cfg.volume = level;
        if (root._player)
            root._player.volume = level;
    }

    // A level for mpv alone: `volume` and cfg.volume keep the user's own.
    // endTransientVolume() puts that one back.
    function setTransientVolume(value) {
        root._volumeHeld = true;
        volumeHoldTimer.stop();
        if (root._player)
            root._player.volume = root._clamp(Number(value));
    }

    function endTransientVolume() {
        if (!root._volumeHeld)
            return;
        if (root._player)
            root._player.volume = root._muted ? 0 : root._volume;
        volumeHoldTimer.restart();
    }

    function toggleMute() {
        if (root._muted) {
            root.setVolume(root._volumeBeforeMute);
            return;
        }
        root._volumeBeforeMute = root._volume;
        root._muted = true;
        root._volume = 0;
        if (root._player)
            root._player.volume = 0;
    }

    // Looks for the PlayerContainer whose D-Bus peer PID is our mpv.
    function rescan() {
        const pid = root.currentPid();
        let found = null;
        if (root.mpris && pid > 0) {
            const count = root.mpris.rowCount();
            for (let row = 0; row < count; row++) {
                const container = root.mpris.data(root.mpris.index(row, 0), 257);
                if (container && Number(container.instancePid) === pid && String(container.identity) === "mpv") {
                    found = container;
                    break;
                }
            }
        }
        if (found === root._player)
            return;
        if (found) {
            root._attach(found);
        } else if (root._player) {
            // mpv went away under us: drop every pending timer with it.
            loadTimer.stop();
            probeTimer.stop();
            attachTimer.stop();
            root._detach();
            root._pendingStation = null;
            root._setPid(0);
            root._setState("idle");
        }
    // A saved PID with no matching row is NOT cleared here: at startup the
    // model fills asynchronously. staleTimer / checkStalePid() handle it.
    }

    // Called by staleTimer a few seconds after startup: if the remembered mpv
    // never showed up on the bus, forget it so the next play relaunches mpv.
    function checkStalePid() {
        if (!root._player && root._state !== "starting" && root.currentPid() > 0)
            root._setPid(0);
    }

    function _watchModel() {
        if (root._connectedModel === root.mpris)
            return;
        if (root._connectedModel) {
            root._connectedModel.rowsInserted.disconnect(root.rescan);
            root._connectedModel.rowsRemoved.disconnect(root.rescan);
        }
        root._connectedModel = root.mpris;
        if (root.mpris) {
            root.mpris.rowsInserted.connect(root.rescan);
            root.mpris.rowsRemoved.connect(root.rescan);
        }
    }

    function _ensureMpv() {
        if (!root.mpris) {
            // The private Plasma MPRIS module failed to load: nothing can be driven.
            root._fail("mpris-module-missing");
            return;
        }
        if (!root.exec) {
            root._fail("mpv-missing");
            return;
        }
        root._setState("starting");
        // Each start gets an epoch: a later start invalidates the replies of an
        // earlier one, which "starting" alone cannot tell apart.
        root._launchEpoch += 1;
        const epoch = root._launchEpoch;
        const binary = root._mpvBinary();
        root.exec("command -v " + RadioModel.shellQuote(binary), (exitCode, stdout) => {
            if (root._state !== "starting" || epoch !== root._launchEpoch)
                return;
            if (exitCode !== 0) {
                root._fail("mpv-missing");
                return;
            }
            root.exec(root._launchCommand(binary), (launchCode, output) => {
                const pid = parseInt(String(output).trim(), 10);
                if (root._state !== "starting" || epoch !== root._launchEpoch) {
                    // Stopped, quit or superseded by a newer start: kill the
                    // latecomer instead of leaving a process nobody knows about.
                    if (pid > 0)
                        root.exec("kill " + pid, function () {});
                    return;
                }
                if (launchCode !== 0 || !(pid > 0)) {
                    root._fail("mpv-missing");
                    return;
                }
                root._setPid(pid);
                attachTimer.restart();
                root.rescan();
            });
        });
    }

    function _mpvBinary() {
        const custom = root.cfg ? String(root.cfg.mpvPath || "").trim() : "";
        return custom ? custom : "mpv";
    }

    function _launchCommand(binary) {
        const options = ["--idle=yes", "--no-video", "--no-terminal", "--force-window=no", "--audio-display=no", "--ytdl=no", "--cache=yes", "--cache-pause-initial=yes", "--cache-pause-wait=2", "--demuxer-readahead-secs=10", "--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5", "--audio-client-name=RadioGlobe", "--user-agent=" + root.userAgent];
        const quoted = options.map(option => RadioModel.shellQuote(option)).join(" ");
        // Backgrounded from a non-interactive sh, the child is not a process-group
        // leader, so setsid execs mpv in place: $! is mpv's own PID.
        const script = "setsid " + RadioModel.shellQuote(binary) + " " + quoted + " >/dev/null 2>&1 & echo $!";
        return "sh -c " + RadioModel.shellQuote(script);
    }

    function _attach(container) {
        root._detach();
        root._player = container;
        container.trackChanged.connect(root._onTrackChanged);
        container.playbackStatusChanged.connect(root._onStatusChanged);
        container.volumeChanged.connect(root._onVolumeChanged);
        attachTimer.stop();
        staleTimer.stop();
        if (root._pendingStation) {
            root._pendingStation = null;
            container.volume = root._volume;
            root._openUri();
            return;
        }
        // Reattaching to an mpv that outlived plasmashell: adopt its state.
        loadTimer.stop();
        probeTimer.stop();
        const status = Number(container.playbackStatus);
        root._updateTrack();
        if (status === root.statusPlaying || (String(container.track || "") !== "" && status !== root.statusPaused))
            root._setState("playing");
        else if (status === root.statusPaused)
            root._setState("paused");
        else
            root._setState("stopped");
        root._volume = root._clamp(Number(container.volume));
    }

    function _detach() {
        const container = root._player;
        if (!container)
            return;
        // At plasmashell's exit the container is already half destroyed and
        // its signals are gone; there is nothing left to disconnect from.
        try {
            container.trackChanged.disconnect(root._onTrackChanged);
            container.playbackStatusChanged.disconnect(root._onStatusChanged);
            container.volumeChanged.disconnect(root._onVolumeChanged);
        } catch (error) {}
        root._player = null;
    }

    function _openUri() {
        if (!root._player || !root._station)
            return;
        root._setState("loading");
        root._track = "";
        root._trackAtOpen = String(root._player.track || "");
        root._positionSample = -1;
        loadTimer.restart();
        probeTimer.restart();
        root._player.OpenUri(root._station.url);
    }

    function _onTrackChanged() {
        if (!root._player)
            return;
        root._updateTrack();
        if (root._state === "loading" && String(root._player.track || "") !== "")
            root._loaded();
    }

    function _loaded() {
        loadTimer.stop();
        probeTimer.stop();
        root._streamRetries = 0;
        if (!root._player)
            return;
        root._shakeStatus();
        root._setState("playing");
        root.playingStarted(root._station);
    }

    // mpv went on playing behind an error: take the player back to playing
    // without announcing the station again, it never stopped being the one on.
    function _recovered() {
        if (!root._player)
            return;
        root._streamRetries = 0;
        root._shakeStatus();
        root._setState("playing");
    }

    function _shakeStatus() {
        if (Number(root._player.playbackStatus) === root.statusPlaying)
            return;
        // mpv-mpris 0.7.1 keeps "Stopped" after loadfile; a pause toggle
        // makes it emit the real status. Only valid once the file loaded.
        root._statusToggle = true;
        root._player.Pause();
        root._player.Play();
    }

    function _onStatusChanged() {
        if (!root._player)
            return;
        const status = Number(root._player.playbackStatus);
        // Anything but the Paused half of our own toggle disarms it, so a real
        // pause is never swallowed later on.
        if (root._statusToggle && status !== root.statusPaused)
            root._statusToggle = false;
        if (root._state === "playing" && status === root.statusPaused && root._statusToggle) {
            root._statusToggle = false;
            return;
        }
        if (root._state === "playing" && status === root.statusStopped && !root._userStopping) {
            if (root._streamRetries < root.maxStreamRetries) {
                root._streamRetries++;
                root._openUri();
            } else {
                root._fail("stream");
            }
        } else if (root._state === "playing" && status === root.statusPaused) {
            root._setState("paused");
        } else if (root._state === "paused" && status === root.statusPlaying) {
            root._setState("playing");
        } else if (root._state === "stopped" && status === root.statusStopped) {
            // Our own Stop() landed: later status changes come from elsewhere.
            root._userStopping = false;
        } else if (root._state === "stopped" && status === root.statusPlaying && !root._userStopping) {
            // Started from outside: media keys or another MPRIS client.
            root._setState("playing");
        }
    }

    function _onVolumeChanged() {
        if (!root._player || root._muted || root._volumeHeld)
            return;
        const level = root._clamp(Number(root._player.volume));
        if (Math.abs(level - root._volume) < 0.001)
            return;
        root._volume = level;
        if (root.cfg)
            root.cfg.volume = level;
    }

    function _updateTrack() {
        const raw = root._player ? String(root._player.track || "") : "";
        const url = root._station ? root._station.url : "";
        root._track = RadioModel.isRawTitle(raw, url) ? "" : raw;
    }

    function _fail(kind) {
        loadTimer.stop();
        probeTimer.stop();
        attachTimer.stop();
        root._pendingStation = null;
        root._errorKind = kind;
        root._setState("error");
    }

    function _setState(next) {
        if (next !== "error")
            root._errorKind = "";
        root._state = next;
    }

    function _setPid(pid) {
        if (root.cfg)
            root.cfg.mpvPid = pid;
    }

    function _clamp(value) {
        if (!isFinite(value))
            return 0.75;
        return Math.min(1, Math.max(0, value));
    }

    // Test hooks: reset without touching mpv, and clear an error state.
    function resetForTests() {
        loadTimer.stop();
        probeTimer.stop();
        attachTimer.stop();
        staleTimer.stop();
        volumeHoldTimer.stop();
        root._detach();
        root._state = "idle";
        root._station = null;
        root._track = "";
        root._errorKind = "";
        root._pendingStation = null;
        root._userStopping = false;
        root._trackAtOpen = "";
        root._positionSample = -1;
        root._statusToggle = false;
        root._volumeHeld = false;
        root._muted = false;
        root._volume = 0.75;
    }

    function resetRetriesForTests(count) {
        root._streamRetries = count;
    }

    function resetErrorForTests() {
        root._errorKind = "";
        root._state = "playing";
    }

    Timer {
        id: loadTimer
        interval: root.loadTimeoutMs
        onTriggered: {
            if (root._state === "loading")
                root._fail("stream");
        }
    }

    // Polls the container while loading. A title of its own settles it at once;
    // a title identical to the one showing before OpenUri is the previous
    // station's leftover, not a successful load. Reopening the station already
    // playing is exactly that case and emits no trackChanged either, so the
    // position is the only evidence left: it moves only when mpv decodes.
    Timer {
        id: probeTimer
        interval: root.probeMs
        repeat: true
        onTriggered: {
            if (root._state !== "loading" || !root._player) {
                probeTimer.stop();
                return;
            }
            const current = String(root._player.track || "");
            if (current !== "" && (root._trackAtOpen === "" || current !== root._trackAtOpen)) {
                root._loaded();
                return;
            }
            // A fresh stream restarts from zero, so only a rise counts: a drop
            // just means the new stream took the old one's place.
            const position = Number(root._player.position);
            if (isFinite(position)) {
                if (root._positionSample >= 0 && position > root._positionSample) {
                    root._loaded();
                    return;
                }
                root._positionSample = position;
            }
            // MPRIS never signals position on its own; ask for a fresh one so
            // the next tick has something to compare against.
            if (root._player.updatePosition)
                root._player.updatePosition();
        }
    }

    // mpv-mpris lies about the status often enough that a stream error can
    // land on a stream that is in fact playing, and mpv reconnects on its own
    // through the lavf options it was launched with. Keep watching the
    // position: if it moves, the error was wrong or is over.
    Timer {
        id: recoveryTimer
        interval: root.recoveryMs
        repeat: true
        running: root._state === "error" && root._errorKind === "stream" && root._player !== null
        onRunningChanged: root._positionSample = -1
        onTriggered: {
            const position = Number(root._player.position);
            if (isFinite(position)) {
                if (root._positionSample >= 0 && position > root._positionSample) {
                    root._recovered();
                    return;
                }
                root._positionSample = position;
            }
            if (root._player.updatePosition)
                root._player.updatePosition();
        }
    }

    Timer {
        id: volumeHoldTimer
        interval: root.volumeHoldMs
        onTriggered: root._volumeHeld = false
    }

    Timer {
        id: staleTimer
        interval: root.staleTimeoutMs
        onTriggered: root.checkStalePid()
    }

    Timer {
        id: attachTimer
        interval: root.attachTimeoutMs
        onTriggered: {
            if (root._state !== "starting" || root._player)
                return;
            const pid = root.currentPid();
            if (pid > 0 && root.exec)
                root.exec("kill " + pid, function () {});
            root._setPid(0);
            root._fail("mpris-missing");
        }
    }
}
