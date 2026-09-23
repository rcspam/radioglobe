import QtQuick

// The sleep timer: stops playback at a deadline, after a fade. It owns the
// deadline and the fade; the player (Player.qml) stays the only one talking
// to mpv. The deadline is kept in cfg.sleepUntil (ms since the epoch) when
// cfg.sleepPersist is on, so it survives a plasmashell restart.
Item {
    id: root

    visible: false

    // Player.qml, or anything with state, volume, muted, stop(),
    // setTransientVolume() and endTransientVolume(). Not called `player`:
    // main.qml's id would resolve to this very property inside the block.
    property var mediaPlayer: null
    property var cfg: null
    property int fadeMs: 20000
    property int fadeStepMs: 250
    // How often the deadline is compared with the wall clock. A clock rather
    // than one long Timer, so a machine that slept through the deadline
    // still stops at wake-up.
    property int tickMs: 1000
    // After a restart with the deadline already gone by, how long an mpv
    // found again on the bus and still playing is stopped.
    property int startupGraceMs: 15000
    // Tests pin the clock; negative means Date.now().
    property real fixedNowMs: -1
    // The clock the user reads (the "timeFormat" setting, see main.qml): on
    // a 12-hour one, a time typed without am/pm can be either half.
    property bool twelveHour: false
    // Accepted after (or before) a typed time, next to am, pm, a.m., p.m.
    property string amText: Qt.locale().amText
    property string pmText: Qt.locale().pmText

    // ms since the epoch, 0 while nothing is armed.
    readonly property real deadline: root._deadline
    readonly property bool active: root._deadline > 0
    readonly property real remainingMs: root._deadline > 0 ? Math.max(0, root._deadline - root._nowMs) : 0
    readonly property bool fading: root._fading

    property real _deadline: 0
    property real _nowMs: 0
    property bool _fading: false
    property int _fadeStep: 0
    property real _fadeFrom: 0
    // The deadline went by while plasmashell was down (see _restore).
    property bool _overdue: false

    Component.onCompleted: root._restore()

    function armFor(minutes) {
        root._arm(root._now() + Number(minutes) * 60000);
    }

    // The next hour:minute to come, today or tomorrow. With eitherHalf, the
    // sooner of the morning and the evening one (11:30 on a 12-hour clock).
    function armUntil(hour, minute, eitherHalf) {
        if (!eitherHalf) {
            root._arm(root._next(hour, minute));
            return;
        }
        root._arm(Math.min(root._next(hour % 12, minute), root._next(hour % 12 + 12, minute)));
    }

    function cancel() {
        root._endFade();
        root._overdue = false;
        root._deadline = 0;
        root._save(0);
    }

    // "23:30", "23h30", "23h", "23", "0.45", "1:25 pm", "7p", "下午1:25"
    // -> {hour (0-23), minute, eitherHalf}; null otherwise. eitherHalf: a
    // 1 to 12 o'clock with no am/pm, typed on a 12-hour clock.
    function parseTime(text) {
        let rest = String(text || "").trim();
        let half = "";
        const markers = [[root.amText, "am"], [root.pmText, "pm"], ["a.m.", "am"], ["p.m.", "pm"], ["am", "am"], ["pm", "pm"], ["a", "am"], ["p", "pm"]];
        for (const [marker, meaning] of markers) {
            const word = String(marker || "").toLowerCase();
            if (word === "")
                continue;
            const lower = rest.toLowerCase();
            if (lower.endsWith(word)) {
                rest = rest.slice(0, rest.length - word.length).trim();
            } else if (lower.startsWith(word) && /^\D+$/.test(word)) {
                rest = rest.slice(word.length).trim();
            } else {
                continue;
            }
            half = meaning;
            break;
        }
        const match = /^(\d{1,2})\s*(?:[:hH.]\s*(\d{2})?)?$/.exec(rest);
        if (!match)
            return null;
        let hour = parseInt(match[1], 10);
        const minute = match[2] ? parseInt(match[2], 10) : 0;
        if (hour > 23 || minute > 59)
            return null;
        if (half !== "") {
            if (hour < 1 || hour > 12)
                return null;
            hour = hour % 12 + (half === "pm" ? 12 : 0);
        }
        return {
            hour: hour,
            minute: minute,
            eitherHalf: half === "" && root.twelveHour && hour >= 1 && hour <= 12
        };
    }

    // What the end time field shows after an edit from `before` to `after`:
    // the ":" goes in once the hour is complete, two digits or one that
    // cannot take a second (3 to 9, or 2 to 9 on a 12-hour clock), and a
    // separator typed over it is dropped. On a 12-hour clock a space follows
    // the minutes. "a" or "p" writes the locale's AM or PM, minutes included
    // when there were none, and the "m" typed after it is dropped. Erasing is
    // left alone, so any of it can be taken out.
    function completeTime(before, after) {
        const previous = String(before);
        let text = String(after);
        if (text.length <= previous.length)
            return text;
        if (text === previous + text.slice(-1) && /[mM]/.test(text.slice(-1)) && root._endsWithMarker(previous))
            return previous;
        const doubled = /^(\d{1,2}):[:hH.]$/.exec(text);
        if (doubled)
            return doubled[1] + ":";
        const half = /^(\d{1,2})(?::(\d{2})?)?\s*([aApP])$/.exec(text);
        if (half) {
            const marker = /[aA]/.test(half[3]) ? root.amText || "am" : root.pmText || "pm";
            return half[1] + ":" + (half[2] || "00") + " " + marker;
        }
        const hours = root.twelveHour ? /^(0\d|1[0-2]|[2-9])(\d{0,2})$/ : /^([01]\d|2[0-3]|[3-9])(\d{0,2})$/;
        const digits = hours.exec(text);
        if (digits)
            text = digits[1] + ":" + digits[2];
        if (root.twelveHour && /^\d{1,2}:\d{2}$/.test(text))
            text += " ";
        return text;
    }

    function _endsWithMarker(text) {
        const lower = String(text).toLowerCase();
        return [root.amText, root.pmText].some(marker => marker !== "" && lower.endsWith(String(marker).toLowerCase()));
    }

    function check() {
        if (root._deadline <= 0 || root._fading)
            return;
        root._nowMs = root._now();
        if (root._nowMs >= root._deadline)
            root._expire();
    }

    function _next(hour, minute) {
        const now = root._now();
        const target = new Date(now);
        target.setHours(hour, minute, 0, 0);
        if (target.getTime() <= now)
            target.setDate(target.getDate() + 1);
        return target.getTime();
    }

    function _arm(deadline) {
        root._endFade();
        root._overdue = false;
        root._nowMs = root._now();
        root._deadline = deadline;
        root._save(deadline);
    }

    // Playing: fade, then stop. About to play (a start, a load, an error mpv
    // may recover from): stop at once, there is nothing to fade. Idle,
    // stopped or paused: nothing to do.
    function _expire() {
        const state = root.mediaPlayer ? String(root.mediaPlayer.state) : "idle";
        if (state === "playing" && !root.mediaPlayer.muted && root.fadeMs > 0) {
            root._fading = true;
            root._fadeStep = 0;
            root._fadeFrom = Number(root.mediaPlayer.volume) || 0;
            fadeTimer.start();
            return;
        }
        if (["playing", "starting", "loading", "error"].indexOf(state) >= 0)
            root.mediaPlayer.stop();
        root._clear();
    }

    function _fadeTick() {
        const state = String(root.mediaPlayer.state);
        if (["playing", "starting", "loading"].indexOf(state) < 0) {
            // Stopped or paused by the user meanwhile.
            root._endFade();
            root._clear();
            return;
        }
        const steps = Math.max(1, Math.round(root.fadeMs / root.fadeStepMs));
        root._fadeStep += 1;
        if (root._fadeStep >= steps) {
            fadeTimer.stop();
            root._fading = false;
            // Stopped first, so the volume coming back is not heard.
            root.mediaPlayer.stop();
            root.mediaPlayer.endTransientVolume();
            root._clear();
            return;
        }
        if (!root.mediaPlayer.muted)
            root.mediaPlayer.setTransientVolume(root._fadeFrom * (1 - root._fadeStep / steps));
    }

    function _endFade() {
        if (!root._fading)
            return;
        fadeTimer.stop();
        root._fading = false;
        root.mediaPlayer.endTransientVolume();
    }

    function _clear() {
        root._deadline = 0;
        root._save(0);
    }

    function _restore() {
        if (!root.cfg)
            return;
        const until = Number(root.cfg.sleepUntil) || 0;
        if (until <= 0)
            return;
        if (!root.cfg.sleepPersist) {
            root._save(0);
            return;
        }
        const now = root._now();
        if (until > now) {
            root._nowMs = now;
            root._deadline = until;
            return;
        }
        root._save(0);
        root._overdue = true;
        overdueTimer.start();
        root._onPlayerState();
    }

    // Only while overdue. An mpv that outlived plasmashell comes back
    // straight as "playing"; one we launch (autoplay, a click) goes through
    // "starting" first, and that one is left alone.
    function _onPlayerState() {
        if (!root._overdue || !root.mediaPlayer)
            return;
        const state = String(root.mediaPlayer.state);
        if (state === "idle")
            return;
        root._overdue = false;
        overdueTimer.stop();
        if (state === "playing")
            root.mediaPlayer.stop();
    }

    function _save(value) {
        if (!root.cfg)
            return;
        const stored = root.cfg.sleepPersist ? value : 0;
        if (Number(root.cfg.sleepUntil) !== stored)
            root.cfg.sleepUntil = stored;
    }

    function _now() {
        return root.fixedNowMs >= 0 ? root.fixedNowMs : Date.now();
    }

    Connections {
        target: root.mediaPlayer
        function onStateChanged() {
            root._onPlayerState();
        }
    }

    Timer {
        interval: root.tickMs
        repeat: true
        running: root._deadline > 0 && !root._fading
        onTriggered: root.check()
    }

    Timer {
        id: fadeTimer
        interval: root.fadeStepMs
        repeat: true
        onTriggered: root._fadeTick()
    }

    Timer {
        id: overdueTimer
        interval: root.startupGraceMs
        onTriggered: root._overdue = false
    }
}
