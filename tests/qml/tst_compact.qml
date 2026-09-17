import QtQuick
import QtTest
import QtQuick.Layouts
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

    // The shell hosts the icon inside its tooltip area, which is not
    // interactive by default: the icon turns that on so the tooltip's
    // buttons can be clicked. Anything up the parent chain that looks like
    // a ToolTipArea (interactive + mainItem) counts.
    Item {
        id: fakeToolTipArea
        objectName: "org.kde.desktop-CompactApplet"
        property bool interactive: false
        property var mainItem: null
        // Away from the icon under test, out of the way of its wheel events.
        x: 120
        y: 120
        width: 60
        height: 60

        Item {
            id: fakeCompactParent
            anchors.fill: parent
        }
    }

    function test_icon_makes_the_hosting_tooltip_area_interactive() {
        const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/CompactRepresentation.qml"));
        verify(component.status === Component.Ready, component.errorString());
        const icon = component.createObject(fakeCompactParent, {
            width: 32,
            height: 32
        });
        tryCompare(fakeToolTipArea, "interactive", true);
        icon.destroy();
    }

    // In a panel the containment fixes the thickness; the other side must
    // follow so the icon fills a square, whatever the panel size.
    function test_panel_icon_is_a_square_of_the_panel_thickness() {
        compact.vertical = false;
        compact.height = 40;
        compare(compact.Layout.preferredWidth, 40);
        compact.height = 64;
        compare(compact.Layout.preferredWidth, 64);
        compact.vertical = true;
        compact.width = 36;
        compare(compact.Layout.preferredHeight, 36);
        compact.vertical = false;
        compact.width = 48;
        compact.height = 48;
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

    function test_wheel_can_be_inverted() {
        compact.invertWheel = true;
        mouseWheel(compact, 24, 24, 0, 120);
        compare(log, ["volume:-0.05"]);
        compact.invertWheel = false;
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

    function test_icon_follows_the_setting() {
        const icon = findChild(compact, "icon");
        verify(icon !== null, "icon not found");
        compare(String(icon.source), "map-globe");
        compact.iconName = "globe";
        compare(String(icon.source), "globe");
        compact.iconName = "";
        compare(String(icon.source), "map-globe");
        compact.iconName = "map-globe";
    }

    function test_colours_follow_the_settings() {
        const icon = findChild(compact, "icon");
        const badge = findChild(compact, "badge");
        compact.iconColor = "#ff0000";
        compact.badgeColor = "#00ff00";
        compare(String(icon.color), "#ff0000");
        compare(String(badge.color), "#00ff00");
        compact.iconColor = "";
        compact.badgeColor = "";
        verify(String(icon.color) !== "#ff0000", "back to the theme colour");
        verify(String(badge.color) !== "#00ff00", "back to the theme colour");
    }

    function test_badge_follows_playing() {
        compact.playing = false;
        compare(compact.badgeVisible, false);
        compact.playing = true;
        compare(compact.badgeVisible, true);
    }
}
