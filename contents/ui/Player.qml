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
    property int attachTimeoutMs: 3000
    property int probeMs: 1500
    property int staleTimeoutMs: 5000

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
    property var _player: null
    property var _pendingStation: null
    property bool _userStopping: false
    property var _connectedModel: null

    onMprisChanged: root._watchModel()
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
        if (root._player) {
            root._openUri();
            return;
        }
        root._pendingStation = station;
        root._ensureMpv();
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
        if (!root._player)
            return;
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
        if (root._player)
            root._player.Quit();
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
        const binary = root._mpvBinary();
        root.exec("command -v " + binary, (exitCode, stdout) => {
            if (root._state !== "starting")
                return;
            if (exitCode !== 0) {
                root._fail("mpv-missing");
                return;
            }
            root.exec(root._launchCommand(binary), (launchCode, output) => {
                if (root._state !== "starting")
                    return;
                const pid = parseInt(String(output).trim(), 10);
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
        if (custom && custom.indexOf("'") < 0 && custom.indexOf(" ") < 0)
            return custom;
        return "mpv";
    }

    function _launchCommand(binary) {
        const options = ["--idle=yes", "--no-video", "--no-terminal", "--force-window=no", "--audio-display=no", "--ytdl=no", "--cache=yes", "--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_delay_max=5", "--audio-client-name=RadioGlobe", "--user-agent=" + root.userAgent.replace(/[^A-Za-z0-9./() -]/g, "")];
        return "sh -c 'setsid " + binary + " " + options.join(" ") + " >/dev/null 2>&1 & echo $!'";
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
        container.trackChanged.disconnect(root._onTrackChanged);
        container.playbackStatusChanged.disconnect(root._onStatusChanged);
        container.volumeChanged.disconnect(root._onVolumeChanged);
        root._player = null;
    }

    function _openUri() {
        if (!root._player || !root._station)
            return;
        root._setState("loading");
        root._track = "";
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
        if (!root._player)
            return;
        if (Number(root._player.playbackStatus) !== root.statusPlaying) {
            // mpv-mpris 0.7.1 keeps "Stopped" after loadfile; a pause toggle
            // makes it emit the real status. Only valid once the file loaded.
            root._player.Pause();
            root._player.Play();
        }
        root._setState("playing");
        root.playingStarted(root._station);
    }

    function _onStatusChanged() {
        if (!root._player)
            return;
        const status = Number(root._player.playbackStatus);
        if (root._state === "playing" && status === root.statusStopped && !root._userStopping) {
            root._fail("stream");
        } else if (root._state === "playing" && status === root.statusPaused) {
            root._setState("paused");
        } else if (root._state === "paused" && status === root.statusPlaying) {
            root._setState("playing");
        }
    }

    function _onVolumeChanged() {
        if (!root._player || root._muted)
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
        root._detach();
        root._state = "idle";
        root._station = null;
        root._track = "";
        root._errorKind = "";
        root._pendingStation = null;
        root._userStopping = false;
        root._muted = false;
        root._volume = 0.75;
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

    Timer {
        id: probeTimer
        interval: root.probeMs
        onTriggered: {
            if (root._state === "loading" && root._player && String(root._player.track || "") !== "")
                root._loaded();
        }
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
