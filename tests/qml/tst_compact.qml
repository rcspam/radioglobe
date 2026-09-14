import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Compact"
    when: windowShown
    width: 200
    height: 200
    visible: true

    property var log: []

    Ui.CompactRepresentation {
        id: compact
        width: 48
        height: 48
        actions: ({
                toggle: () => log.push("toggle"),
                random: () => log.push("random"),
                volumeStep: delta => log.push("volume:" + delta)
            })
    }

    function init() {
        log = [];
        compact._wheelAccumulator = 0;
    }

    function test_buttons_dispatch_actions() {
        mouseClick(compact, 24, 24, Qt.LeftButton);
        mouseClick(compact, 24, 24, Qt.MiddleButton);
        compare(log, ["toggle", "random"]);
    }

    // Right click belongs to Plasma: it opens the widget menu, which carries
    // the random / stop actions main.qml publishes.
    function test_right_click_is_left_to_plasma() {
        mouseClick(compact, 24, 24, Qt.RightButton);
        compare(log, []);
    }

    function test_wheel_changes_volume() {
        mouseWheel(compact, 24, 24, 0, 120);
        mouseWheel(compact, 24, 24, 0, -120);
        compare(log, ["volume:0.05", "volume:-0.05"]);
    }

    function test_horizontal_wheel_is_ignored() {
        mouseWheel(compact, 24, 24, 120, 0);
        compare(log, []);
    }

    function test_touchpad_micro_deltas_accumulate() {
        mouseWheel(compact, 24, 24, 0, 40);
        mouseWheel(compact, 24, 24, 0, 40);
        mouseWheel(compact, 24, 24, 0, 40);
        compare(log, ["volume:0.05"]);
        mouseWheel(compact, 24, 24, 0, -40);
        compare(log, ["volume:0.05"]);
    }

    function test_badge_follows_playing() {
        compact.playing = false;
        compare(compact.badgeVisible, false);
        compact.playing = true;
        compare(compact.badgeVisible, true);
    }
}
