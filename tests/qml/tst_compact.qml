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
                stop: () => log.push("stop"),
                volumeStep: delta => log.push("volume:" + delta)
            })
    }

    function init() {
        log = [];
    }

    function test_buttons_dispatch_actions() {
        mouseClick(compact, 24, 24, Qt.LeftButton);
        mouseClick(compact, 24, 24, Qt.MiddleButton);
        mouseClick(compact, 24, 24, Qt.RightButton);
        compare(log, ["toggle", "random", "stop"]);
    }

    function test_wheel_changes_volume() {
        mouseWheel(compact, 24, 24, 0, 120);
        mouseWheel(compact, 24, 24, 0, -120);
        compare(log, ["volume:0.05", "volume:-0.05"]);
    }

    function test_badge_follows_playing() {
        compact.playing = false;
        compare(compact.badgeVisible, false);
        compact.playing = true;
        compare(compact.badgeVisible, true);
    }
}
