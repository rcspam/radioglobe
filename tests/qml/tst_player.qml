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
            position: 0,
            // Set by a test to say whether mpv is really decoding: only then
            // does a position poll come back with a fresher value.
            streaming: false,
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
            // Real containers only refresh position when asked: MPRIS never
            // signals it on its own.
            updatePosition: function () {
                this.calls.push("updatePosition");
                if (this.streaming)
                    this.position += 500000;
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
        // "kill" is fire-and-forget in Player.qml: no test ever answers it, so
        // keeping its callback would desynchronise the reply queue.
        if (cmd.indexOf("kill ") !== 0)
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
        // Tests that need room to load raise it; put it back so a failure
        // mid-test cannot carry its timing over to the next one.
        player.loadTimeoutMs = 60;
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

    // The last station restored at startup sits in the player, idle, with no
    // mpv around: Play launches it.
    function test_restored_station_starts_on_play() {
        player.adoptStation(fip);
        compare(player.state, "idle");
        compare(player.station.uuid, fip.uuid);
        player.togglePause();
        compare(player.state, "starting");
        compare(execLog[execLog.length - 1], "command -v 'mpv'");
    }

    // And so does startIfIdle(), the autoplay at startup.
    function test_restored_station_autoplays() {
        player.adoptStation(fip);
        player.startIfIdle();
        compare(player.state, "starting");
    }

    // Autoplay with an mpv that outlived plasmashell already playing: no-op.
    function test_autoplay_leaves_a_playing_mpv_alone() {
        const c = startAndAttach(1);
        c.setTrack("fip-midfi.mp3");
        compare(player.state, "playing");
        const before = c.calls.length;
        player.startIfIdle();
        compare(c.calls.length, before);
        compare(player.state, "playing");
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

    // Fresh container: no title at OpenUri time, so the first one that shows up
    // is necessarily the new stream's, even without a trackChanged signal.
    function test_probe_accepts_load_without_track_change() {
        // The probe (30 ms) must win against the load timeout: with the suite's
        // 60 ms both can be due in the same stalled event loop turn, in either
        // order, so this test alone gives the timeout real room.
        player.loadTimeoutMs = 500;
        const c = startAndAttach(2);
        c.track = "fip-midfi.mp3";
        tryCompare(player, "state", "playing", 1000);
        player.loadTimeoutMs = 60;
    }

    function test_probe_ignores_the_previous_station_title() {
        player.loadTimeoutMs = 5000;
        const c = startAndAttach(2);
        c.setTrack("Klangstein - Closer");
        compare(player.state, "playing");
        // Second station: mpv keeps showing the first one's title until the
        // new stream sends its own, and emits no signal in between.
        const other = {
            uuid: "other",
            name: "Other",
            url: "https://s/other.mp3"
        };
        player.play(other);
        compare(player.state, "loading");
        wait(4 * player.probeMs);
        compare(player.state, "loading");
        // Same open, this time the stream publishes its own title before the
        // probe runs: a title that differs does count as loaded.
        player.play(other);
        c.track = "Another - Song";
        tryCompare(player, "state", "playing", 1000);
        player.loadTimeoutMs = 60;
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

    // A stream cut by the server: mpv reports Stopped. One silent retry first,
    // the error only shows when the retried stream drops as well.
    function test_stopped_status_while_playing_retries_once_then_errors() {
        const c = startAndAttach(2);
        c.setTrack("fip-midfi.mp3");
        const opens = () => c.calls.filter(x => x.indexOf("OpenUri") === 0).length;
        compare(opens(), 1);
        c.setStatus(1);
        compare(player.state, "loading");
        compare(opens(), 2);
        // the retry loads fine: the counter is armed again for the next cut
        c.setStatus(2);
        c.setTrack("fip-midfi.mp3 2");
        tryCompare(player, "state", "playing", 1000);
        c.setStatus(1);
        compare(player.state, "loading");
        compare(opens(), 3);
        // second consecutive drop without a successful load: error
        c.setStatus(2);
        c.setTrack("fip-midfi.mp3 3");
        tryCompare(player, "state", "playing", 1000);
        player.resetRetriesForTests(1);
        c.setStatus(1);
        compare(player.state, "error");
        compare(player.errorKind, "stream");
    }

    // Stations without ICY metadata keep the title mpv derived from the URL,
    // so reopening one emits no trackChanged and the probe cannot tell the
    // reload from the leftover title. A position that moves is the only proof
    // the stream came back, and mpv-mpris keeps claiming Stopped until the
    // Pause/Play workaround runs.
    function test_reopening_a_titleless_station_is_detected_by_position() {
        const c = startAndAttach(2);
        c.streaming = true;
        c.setTrack("stream");
        tryCompare(player, "state", "playing", 1000);
        // Two probe ticks are needed to compare positions, so the reopen gets
        // more room than the 60 ms the other tests run with.
        player.loadTimeoutMs = 800;
        // The server cuts the stream: one silent retry reopens the same URL.
        c.setStatus(1);
        compare(player.state, "loading");
        compare(c.calls.filter(x => x.indexOf("OpenUri") === 0).length, 2);
        // mpv reloads and plays again, with the very same title and a status
        // still stuck on Stopped. Only the position gives it away.
        tryCompare(player, "state", "playing", 2000);
        compare(player.errorKind, "");
        verify(c.calls.indexOf("updatePosition") >= 0);
    }

    // The mirror case: a position that never moves must still end in an error,
    // otherwise a dead stream would look alive.
    function test_a_frozen_position_still_times_out() {
        const c = startAndAttach(2);
        c.streaming = false;
        tryCompare(player, "state", "error", 1000);
        compare(player.errorKind, "stream");
    }

    function test_launch_command_buffers_before_playing() {
        player.play(fip);
        replyExec(0, "/usr/bin/mpv\n");
        const launch = execLog[execLog.length - 1];
        verify(launch.indexOf("'--cache-pause-initial=yes'") > 0, launch);
        verify(launch.indexOf("'--cache-pause-wait=2'") > 0, launch);
        verify(launch.indexOf("'--demuxer-readahead-secs=10'") > 0, launch);
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

    function test_relaunch_during_pending_check_kills_the_first_mpv() {
        player.play(fip);
        replyExec(0, "/usr/bin/mpv\n");
        const first = execLog.length;
        player.stop();
        player.play(fip);
        compare(player.state, "starting");
        compare(execLog.length, first + 1);
        // The first launch answers late: same state, older epoch.
        replyExec(0, "111\n");
        compare(execLog[execLog.length - 1], "kill 111");
        compare(player.state, "starting");
        compare(cfg.mpvPid, 0);
        replyExec(0, "/usr/bin/mpv\n");
        replyExec(0, "222\n");
        compare(cfg.mpvPid, 222);
    }

    function test_quit_before_attach_kills_the_launched_mpv() {
        player.play(fip);
        replyExec(0, "/usr/bin/mpv\n");
        replyExec(0, "333\n");
        compare(cfg.mpvPid, 333);
        player.quit();
        compare(execLog[execLog.length - 1], "kill 333");
        compare(cfg.mpvPid, 0);
        compare(player.state, "idle");
    }

    function test_status_echoes_after_forced_stop_do_not_flip_state() {
        const c = startAndAttach(1);
        c.setTrack("fip-midfi.mp3");
        c.setStatus(1);
        player.resetErrorForTests();
        player.stop();
        compare(player.state, "stopped");
        // Echoes of the Pause/Play we sent to make Stop() land.
        c.setStatus(3);
        compare(player.state, "stopped");
        c.setStatus(2);
        compare(player.state, "stopped");
        c.setStatus(1);
        compare(player.state, "stopped");
        // Genuine external start, once the container really reported Stopped.
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
