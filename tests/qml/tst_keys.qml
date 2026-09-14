import QtQuick
import QtTest
import "../../contents/ui/KeyMap.js" as KeyMap

TestCase {
    name: "Keys"

    property var log: []
    property var targets: ({
            focusSearch: () => log.push("search"),
            moveSelection: d => log.push("move:" + d),
            activateSelected: () => log.push("activate"),
            togglePause: () => log.push("pause"),
            random: () => log.push("random"),
            favorite: () => log.push("favorite"),
            volumeStep: d => log.push("volume:" + d),
            mute: () => log.push("mute"),
            escape: () => log.push("escape")
        })

    function init() {
        log = [];
    }

    function test_mapping() {
        KeyMap.handle(targets, Qt.Key_Slash, "/");
        KeyMap.handle(targets, Qt.Key_Down, "");
        KeyMap.handle(targets, Qt.Key_Up, "");
        KeyMap.handle(targets, Qt.Key_Return, "");
        KeyMap.handle(targets, Qt.Key_Space, " ");
        KeyMap.handle(targets, Qt.Key_R, "r");
        KeyMap.handle(targets, Qt.Key_F, "F");
        KeyMap.handle(targets, Qt.Key_Plus, "+");
        KeyMap.handle(targets, Qt.Key_Minus, "-");
        KeyMap.handle(targets, Qt.Key_M, "m");
        KeyMap.handle(targets, Qt.Key_Escape, "");
        compare(log, ["search", "move:1", "move:-1", "activate", "pause", "random", "favorite", "volume:0.05", "volume:-0.05", "mute", "escape"]);
    }

    function test_unknown_key_is_not_handled() {
        compare(KeyMap.handle(targets, Qt.Key_Z, "z"), false);
        compare(log.length, 0);
    }
}
