import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    id: testCase
    name: "SleepTimer"

    // 23 September 2026, 22:30 local time.
    readonly property real evening: new Date(2026, 8, 23, 22, 30).getTime()
    readonly property real minute: 60000

    // Stands for Player.qml: its state, its volume and the calls the timer
    // makes, in order. setTransientVolume() only records the level.
    QtObject {
        id: fakePlayer

        property string state: "playing"
        property real volume: 0.6
        property bool muted: false
        property var levels: []
        property var calls: []

        function stop() {
            fakePlayer.calls.push("stop");
            fakePlayer.state = "stopped";
        }

        function setTransientVolume(value) {
            fakePlayer.levels.push(value);
        }

        function endTransientVolume() {
            fakePlayer.calls.push("endTransient");
        }
    }

    property var config: ({
            sleepUntil: 0,
            sleepPersist: true
        })

    Ui.SleepTimer {
        id: timer
        mediaPlayer: fakePlayer
        cfg: testCase.config
        fixedNowMs: testCase.evening
        fadeMs: 100
        fadeStepMs: 10
        tickMs: 20
    }

    // Bound here rather than handed to createObject(), which would copy the
    // config object and leave the test reading the original.
    Component {
        id: timerComponent
        Ui.SleepTimer {
            mediaPlayer: fakePlayer
            cfg: testCase.config
            fixedNowMs: testCase.evening
            fadeMs: 100
            fadeStepMs: 10
            tickMs: 20
            startupGraceMs: 100
        }
    }

    function init() {
        timer.cancel();
        timer.fixedNowMs = evening;
        config.sleepUntil = 0;
        config.sleepPersist = true;
        fakePlayer.state = "playing";
        fakePlayer.volume = 0.6;
        fakePlayer.muted = false;
        fakePlayer.levels = [];
        fakePlayer.calls = [];
    }

    // A timer made the way main.qml's is at startup, reading the config.
    function startTimer() {
        const created = timerComponent.createObject(testCase);
        verify(created !== null);
        return created;
    }

    function passTime(minutes) {
        timer.fixedNowMs = evening + minutes * minute;
        timer.check();
    }

    function test_arming_for_a_duration() {
        compare(timer.active, false);
        timer.armFor(30);
        compare(timer.active, true);
        compare(timer.deadline, evening + 30 * minute);
        compare(timer.remainingMs, 30 * minute);
        compare(config.sleepUntil, evening + 30 * minute);
        passTime(10);
        compare(timer.remainingMs, 20 * minute);
        compare(fakePlayer.calls, []);
    }

    function test_arming_until_a_time_later_today() {
        timer.armUntil(23, 15);
        compare(timer.deadline, new Date(2026, 8, 23, 23, 15).getTime());
    }

    // An hour already gone today (or this very minute) means tomorrow.
    function test_a_time_already_past_means_tomorrow() {
        timer.armUntil(1, 0);
        compare(timer.deadline, new Date(2026, 8, 24, 1, 0).getTime());
        timer.armUntil(22, 30);
        compare(timer.deadline, new Date(2026, 8, 24, 22, 30).getTime());
    }

    function test_cancel_forgets_the_deadline() {
        timer.armFor(15);
        timer.cancel();
        compare(timer.active, false);
        compare(timer.deadline, 0);
        compare(config.sleepUntil, 0);
        passTime(20);
        compare(fakePlayer.calls, []);
    }

    function test_without_persistence_the_deadline_stays_out_of_the_config() {
        config.sleepPersist = false;
        timer.armFor(15);
        compare(timer.active, true);
        compare(config.sleepUntil, 0);
    }

    // Another station in the meantime does not disarm it.
    function test_changing_station_keeps_the_timer() {
        timer.armFor(15);
        fakePlayer.state = "loading";
        fakePlayer.state = "playing";
        passTime(5);
        compare(timer.active, true);
    }

    function test_the_deadline_fades_out_then_stops_and_restores_the_volume() {
        timer.armFor(15);
        passTime(15);
        compare(timer.fading, true);
        compare(timer.active, true);
        tryCompare(timer, "active", false);
        compare(timer.fading, false);
        compare(fakePlayer.calls, ["stop", "endTransient"]);
        compare(config.sleepUntil, 0);
        const levels = fakePlayer.levels;
        verify(levels.length >= 5, JSON.stringify(levels));
        verify(levels[0] < 0.6 && levels[0] > 0.4, JSON.stringify(levels));
        for (let i = 1; i < levels.length; i++)
            verify(levels[i] < levels[i - 1], JSON.stringify(levels));
        verify(levels[levels.length - 1] < 0.1, JSON.stringify(levels));
    }

    function test_nothing_playing_at_the_deadline_just_ends_the_timer() {
        fakePlayer.state = "paused";
        timer.armFor(15);
        passTime(15);
        compare(timer.active, false);
        compare(fakePlayer.calls, []);
        compare(fakePlayer.levels, []);
    }

    // A station still loading, or an error mpv may recover from, would
    // turn into sound after the deadline: stopped at once, nothing to fade.
    function test_a_station_about_to_play_is_stopped_at_once() {
        for (const state of ["starting", "loading", "error"]) {
            timer.fixedNowMs = evening;
            fakePlayer.calls = [];
            fakePlayer.state = state;
            timer.armFor(15);
            passTime(15);
            compare(timer.active, false, state);
            compare(fakePlayer.calls, ["stop"], state);
            compare(fakePlayer.levels, [], state);
        }
    }

    // Raising the volume of a muted player would make it heard again.
    function test_a_muted_player_is_stopped_without_a_fade() {
        fakePlayer.muted = true;
        timer.armFor(15);
        passTime(15);
        compare(timer.active, false);
        compare(fakePlayer.calls, ["stop"]);
        compare(fakePlayer.levels, []);
    }

    function test_cancelling_during_the_fade_gives_the_volume_back() {
        timer.armFor(15);
        passTime(15);
        compare(timer.fading, true);
        timer.cancel();
        compare(timer.fading, false);
        compare(timer.active, false);
        compare(fakePlayer.calls, ["endTransient"]);
        wait(50);
        compare(fakePlayer.calls, ["endTransient"]);
    }

    // The user stopping or pausing during the fade ends it: volume back,
    // nothing more to stop.
    function test_a_stop_during_the_fade_ends_it() {
        timer.armFor(15);
        passTime(15);
        fakePlayer.state = "paused";
        tryCompare(timer, "active", false);
        compare(fakePlayer.calls, ["endTransient"]);
    }

    function test_rearming_during_the_fade_gives_the_volume_back() {
        timer.armFor(15);
        passTime(15);
        timer.armFor(30);
        compare(timer.fading, false);
        compare(timer.active, true);
        compare(fakePlayer.calls, ["endTransient"]);
    }

    function test_a_deadline_still_ahead_resumes_at_startup() {
        config.sleepUntil = evening + 40 * minute;
        const started = startTimer();
        compare(started.active, true);
        compare(started.deadline, evening + 40 * minute);
        compare(started.remainingMs, 40 * minute);
        started.destroy();
    }

    function test_without_persistence_nothing_resumes() {
        config.sleepPersist = false;
        config.sleepUntil = evening + 40 * minute;
        const started = startTimer();
        compare(started.active, false);
        compare(config.sleepUntil, 0);
        started.destroy();
    }

    // plasmashell crashed in the night and mpv went on playing: the deadline
    // is behind us, and the mpv found again on the bus is stopped at once.
    function test_a_deadline_gone_by_at_startup_stops_the_mpv_still_playing() {
        config.sleepUntil = evening - 60 * minute;
        fakePlayer.state = "idle";
        const started = startTimer();
        compare(started.active, false);
        compare(config.sleepUntil, 0);
        compare(fakePlayer.calls, []);
        fakePlayer.state = "playing";
        compare(fakePlayer.calls, ["stop"]);
        compare(fakePlayer.levels, []);
        started.destroy();
    }

    function test_a_deadline_gone_by_stops_an_mpv_already_found() {
        config.sleepUntil = evening - 60 * minute;
        fakePlayer.state = "playing";
        const started = startTimer();
        compare(fakePlayer.calls, ["stop"]);
        started.destroy();
    }

    // The next morning, autoplay starts the last station through a fresh
    // mpv: that goes through "starting", and is none of the timer's business.
    function test_a_deadline_gone_by_leaves_autoplay_alone() {
        config.sleepUntil = evening - 60 * minute;
        fakePlayer.state = "idle";
        const started = startTimer();
        fakePlayer.state = "starting";
        fakePlayer.state = "loading";
        fakePlayer.state = "playing";
        compare(fakePlayer.calls, []);
        started.destroy();
    }

    // Past the startup grace period, a later play is the user's.
    function test_a_deadline_gone_by_is_forgotten_after_startup() {
        config.sleepUntil = evening - 60 * minute;
        fakePlayer.state = "idle";
        const started = startTimer();
        wait(200);
        fakePlayer.state = "playing";
        compare(fakePlayer.calls, []);
        started.destroy();
    }

    function test_parsing_an_end_time() {
        compare(timer.parseTime("23:30"), {
            hour: 23,
            minute: 30
        });
        compare(timer.parseTime(" 7h05 "), {
            hour: 7,
            minute: 5
        });
        compare(timer.parseTime("23h"), {
            hour: 23,
            minute: 0
        });
        compare(timer.parseTime("7"), {
            hour: 7,
            minute: 0
        });
        compare(timer.parseTime("0.45"), {
            hour: 0,
            minute: 45
        });
        compare(timer.parseTime("24:00"), null);
        compare(timer.parseTime("12:60"), null);
        compare(timer.parseTime("12:5"), null);
        compare(timer.parseTime("soon"), null);
        compare(timer.parseTime(""), null);
    }
}
