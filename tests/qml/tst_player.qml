import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Player"

    // Minimal Qt-signal look-alike so the same connect()/disconnect() code
    // works against a real PlayerContainer and against this fake.
    function makeSignal() {
        const listeners = [];
        return {
            connect: fn => listeners.push(fn),
            disconnect: fn => {
                const i = listeners.indexOf(fn);
                if (i >= 0)
                    listeners.splice(i, 1);
            },
            emit: () => listeners.slice().forEach(fn => fn())
        };
    }

    function makeContainer(pid, status) {
        const c = {
            identity: "mpv",
            instancePid: pid,
            playbackStatus: status,
            track: "",
            volume: 0.5,
            canPlay: true,
            canPause: true,
            canStop: status > 1,
            canQuit: true,
            calls: [],
            trackChanged: makeSignal(),
            playbackStatusChanged: makeSignal(),
            volumeChanged: makeSignal(),
            OpenUri: function (uri) {
                this.calls.push("OpenUri:" + uri);
            },
            Play: function () {
                this.calls.push("Play");
            },
            Pause: function () {
                this.calls.push("Pause");
            },
            PlayPause: function () {
                this.calls.push("PlayPause");
            },
            Stop: function () {
                this.calls.push("Stop");
            },
            Quit: function () {
                this.calls.push("Quit");
            },
            setStatus: function (s) {
                this.playbackStatus = s;
                this.canStop = s > 1;
                this.playbackStatusChanged.emit();
            },
            setTrack: function (t) {
                this.track = t;
                this.trackChanged.emit();
            }
        };
        return c;
    }

    property var containers: []
    property var model: ({
            rowCount: () => containers.length,
            index: (row, column) => row,
            data: (index, role) => role === 257 ? containers[index] : undefined,
            rowsInserted: makeSignal(),
            rowsRemoved: makeSignal()
        })

    function addContainer(c) {
        containers.push(c);
        model.rowsInserted.emit();
    }

    function removeContainer(c) {
        containers.splice(containers.indexOf(c), 1);
        model.rowsRemoved.emit();
    }

    property var execLog: []
    property var execReplies: []

    function fakeExec(cmd, callback) {
        execLog.push(cmd);
        execReplies.push(callback);
    }

    function replyExec(exitCode, stdout) {
        const cb = execReplies.shift();
        cb(exitCode, stdout);
    }

    property var cfg: ({
            mpvPid: 0,
            mpvPath: "",
            volume: 0.75
        })

    Ui.Player {
        id: player
        mpris: model
        exec: fakeExec
        cfg: cfg
        userAgent: "RadioGlobe/test"
        loadTimeoutMs: 60
        attachTimeoutMs: 60
        probeMs: 30
    }

    SignalSpy {
        id: started
        target: player
        signalName: "playingStarted"
    }

    readonly property var fip: ({
            uuid: "fip",
            name: "FIP",
            url: "https://s/fip-midfi.mp3"
        })

    function init() {
        containers = [];
        execLog = [];
        execReplies = [];
        cfg = ({
                mpvPid: 0,
                mpvPath: "",
                volume: 0.75
            });
        player.cfg = cfg;
        player.mpris = model;
        player.userAgent = "RadioGlobe/test";
        started.clear();
        player.resetForTests();
    }

    property int nextPid: 4000

    // Everything /bin/sh would still interpret: single-quoted spans are dropped,
    // and a backslash escape outside them protects the next character.
    function unquotedPart(command) {
        let out = "";
        let quoted = false;
        for (let i = 0; i < command.length; i++) {
            const ch = command.charAt(i);
            if (!quoted && ch === "\\") {
                i++;
                continue;
            }
            if (ch === "'") {
                quoted = !quoted;
                continue;
            }
            if (!quoted)
                out += ch;
        }
        return out;
    }

    // Drives a full happy-path start: play -> mpv check -> launch -> attach.
    // Each call launches a distinct fake PID, like a real relaunch would.
    function startAndAttach(status) {
        const pid = ++nextPid;
        player.play(fip);
        compare(player.state, "starting");
        compare(execLog[execLog.length - 1], "command -v 'mpv'");
        replyExec(0, "/usr/bin/mpv\n");
        const launch = execLog[execLog.length - 1];
        verify(launch.indexOf("sh -c ") === 0, launch);
        verify(launch.indexOf("setsid '") > 0, launch);
        verify(launch.indexOf("'mpv'") > 0, launch);
        verify(launch.indexOf("'--idle=yes'") > 0, launch);
        verify(launch.indexOf("'--no-video'") > 0, launch);
        verify(launch.indexOf("'--no-terminal'") > 0, launch);
        verify(launch.indexOf("'--user-agent=RadioGlobe/test'") > 0, launch);
        verify(launch.indexOf("'--audio-client-name=RadioGlobe'") > 0, launch);
        replyExec(0, pid + "\n");
        compare(cfg.mpvPid, pid);
        const c = makeContainer(pid, status === undefined ? 1 : status);
        addContainer(c);
        compare(player.attached, true);
        compare(player.state, "loading");
        compare(c.calls[c.calls.length - 1], "OpenUri:https://s/fip-midfi.mp3");
        return c;
    }

    function test_missing_mpv_reports_error() {
        player.play(fip);
        replyExec(1, "");
        compare(player.state, "error");
        compare(player.errorKind, "mpv-missing");
        compare(execLog.length, 1);
    }

    function test_missing_mpris_module_reports_error_without_launching() {
        player.mpris = null;
        player.play(fip);
        compare(player.state, "error");
        compare(player.errorKind, "mpris-module-missing");
        compare(execLog.length, 0);
    }

    function test_launch_attach_and_fix_status_on_load() {
        const c = startAndAttach(1);
        c.setTrack("fip-midfi.mp3");
        compare(c.calls.slice(-2), ["Pause", "Play"]);
        compare(player.state, "playing");
        compare(started.count, 1);
        compare(player.track, "");
        c.setTrack("Klangstein - Closer");
        compare(player.track, "Klangstein - Closer");
    }

    function test_no_status_fix_when_already_playing() {
        const c = startAndAttach(2);
        c.setTrack("fip-midfi.mp3");
        compare(c.calls.indexOf("Pause"), -1);
        compare(player.state, "playing");
    }

    function test_probe_accepts_load_without_track_change() {
        const c = startAndAttach(2);
        c.track = "fip-midfi.mp3";
        tryCompare(player, "state", "playing", 1000);
    }

    function test_mpris_missing_after_timeout() {
        player.play(fip);
        replyExec(0, "/usr/bin/mpv");
        replyExec(0, "77");
        tryCompare(player, "state", "error", 1000);
        compare(player.errorKind, "mpris-missing");
        compare(execLog[2], "kill 77");
        compare(cfg.mpvPid, 0);
    }

    function test_load_timeout_is_a_stream_error_and_retry_reopens() {
        const c = startAndAttach(1);
        tryCompare(player, "state", "error", 1000);
        compare(player.errorKind, "stream");
        compare(player.station.uuid, "fip");
        player.retry();
        compare(player.state, "loading");
        compare(c.calls.filter(x => x.indexOf("OpenUri") === 0).length, 2);
    }

    function test_stopped_status_while_playing_is_a_stream_error() {
        const c = startAndAttach(2);
        c.setTrack("fip-midfi.mp3");
        c.setStatus(1);
        compare(player.state, "error");
        compare(player.errorKind, "stream");
    }

    function test_reattaches_to_existing_mpv_from_cfg() {
        cfg.mpvPid = 900;
        const other = makeContainer(1, 2);
        const ours = makeContainer(900, 2);
        ours.track = "Some Song";
        containers = [other, ours];
        player.rescan();
        compare(player.attached, true);
        compare(player.currentPid(), 900);
        compare(player.state, "playing");
    }

    function test_stale_pid_is_cleared_only_after_grace_period() {
        cfg.mpvPid = 900;
        player.rescan();
        compare(player.attached, false);
        compare(cfg.mpvPid, 900);
        player.checkStalePid();
        compare(cfg.mpvPid, 0);
    }

    function test_stop_forces_status_fix_when_needed() {
        const c = startAndAttach(1);
        c.setTrack("fip-midfi.mp3");
        c.setStatus(1);
        player.resetErrorForTests();
        player.stop();
        compare(c.calls.slice(-3), ["Pause", "Play", "Stop"]);
        compare(player.state, "stopped");
    }

    function test_pause_resume_and_media_keys() {
        const c = startAndAttach(2);
        c.setTrack("fip-midfi.mp3");
        player.pause();
        compare(c.calls[c.calls.length - 1], "Pause");
        compare(player.state, "paused");
        player.resume();
        compare(c.calls[c.calls.length - 1], "Play");
        compare(player.state, "playing");
        c.setStatus(3);
        compare(player.state, "paused");
        c.setStatus(2);
        compare(player.state, "playing");
    }

    function test_volume_is_clamped_persisted_and_muted() {
        const c = startAndAttach(2);
        player.setVolume(1.7);
        compare(player.volume, 1);
        compare(c.volume, 1);
        compare(cfg.volume, 1);
        player.setVolume(0.4);
        player.toggleMute();
        compare(player.muted, true);
        compare(c.volume, 0);
        player.toggleMute();
        compare(player.volume, 0.4);
        compare(c.volume, 0.4);
    }

    function test_second_play_while_starting_does_not_relaunch() {
        const other = ({
                uuid: "b",
                name: "B",
                url: "https://s/other.mp3"
            });
        const pid = ++nextPid;
        player.play(fip);
        replyExec(0, "/usr/bin/mpv\n");
        compare(execLog.length, 2);
        player.play(other);
        compare(execLog.length, 2);
        compare(player.state, "starting");
        replyExec(0, pid + "\n");
        const c = makeContainer(pid, 1);
        addContainer(c);
        compare(player.state, "loading");
        compare(player.station.url, "https://s/other.mp3");
        compare(c.calls[c.calls.length - 1], "OpenUri:https://s/other.mp3");
    }

    function test_quit_during_launch_kills_the_late_mpv() {
        player.play(fip);
        replyExec(0, "/usr/bin/mpv\n");
        player.quit();
        replyExec(0, "555\n");
        compare(execLog[execLog.length - 1], "kill 555");
        compare(cfg.mpvPid, 0);
        compare(player.state, "idle");
    }

    function test_launch_command_quotes_user_agent_and_binary() {
        player.userAgent = "RadioGlobe/1.0 (+https://x)";
        cfg.mpvPath = "/opt/my mpv/bin/mpv";
        player.play(fip);
        compare(execLog[execLog.length - 1], "command -v '/opt/my mpv/bin/mpv'");
        replyExec(0, "/opt/my mpv/bin/mpv\n");
        const launch = execLog[execLog.length - 1];
        verify(launch.indexOf("'/opt/my mpv/bin/mpv'") > 0, launch);
        verify(launch.indexOf("'--user-agent=RadioGlobe/1.0 (+https://x)'") > 0, launch);
        verify(unquotedPart(launch).indexOf("(") < 0, launch);
        compare(unquotedPart(launch), "sh -c ");
    }

    function test_toggle_pause_switches_between_pause_and_resume() {
        const c = startAndAttach(2);
        c.setTrack("fip-midfi.mp3");
        player.togglePause();
        compare(c.calls[c.calls.length - 1], "Pause");
        compare(player.state, "paused");
        player.togglePause();
        compare(c.calls[c.calls.length - 1], "Play");
        compare(player.state, "playing");
    }

    function test_external_play_after_stop_returns_to_playing() {
        const c = startAndAttach(2);
        c.setTrack("fip-midfi.mp3");
        player.stop();
        compare(player.state, "stopped");
        c.setStatus(1);
        compare(player.state, "stopped");
        c.setStatus(2);
        compare(player.state, "playing");
    }

    function test_quit_and_external_disappearance() {
        const c = startAndAttach(2);
        c.setTrack("x");
        player.quit();
        compare(c.calls[c.calls.length - 1], "Quit");
        compare(player.state, "idle");
        compare(cfg.mpvPid, 0);
        removeContainer(c);
        const d = startAndAttach(2);
        d.setTrack("x");
        removeContainer(d);
        compare(player.attached, false);
        compare(player.state, "idle");
        compare(cfg.mpvPid, 0);
    }
}
