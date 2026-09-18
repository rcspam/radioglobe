import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Panel / tray icon. Left click opens the popup, middle click tunes a random
// station, wheel adjusts the volume. Right click is left to Plasma, which
// shows the widget menu and the actions main.qml publishes there.
Item {
    id: compact

    property var actions: ({
            toggle: () => {
                root.expanded = !root.expanded;
            },
            random: () => root.playRandom(),
            volumeStep: delta => player.setVolume(player.volume + delta)
        })
    property bool playing: typeof player !== "undefined" && player.state === "playing"
    property bool invertWheel: false
    // Milliseconds of hover before the tooltip opens. Plasma's ToolTipArea
    // has its own delay (700 ms, plasmarc) and no property for it, but a
    // public showToolTip(): the icon calls it itself, sooner.
    property int toolTipDelay: 300
    // False when the user turned Plasma tooltips off (plasmarc Delay <= 0):
    // showToolTip() does not check that itself, hoverEnterEvent does.
    property bool plasmaToolTipsEnabled: true
    property string iconName: "map-globe"
    // "#rrggbb" or empty for the theme colour.
    property string iconColor: ""
    property string badgeColor: ""
    readonly property bool badgeVisible: compact.playing
    property real _wheelAccumulator: 0

    // True in a vertical panel (main.qml binds it to the form factor).
    property bool vertical: false

    // The shell hosts this icon inside its ToolTipArea, which shows our
    // toolTipItem but is not interactive by default (it closes as soon as
    // the pointer leaves the icon). Walk up to it and turn that on, so the
    // tooltip's buttons can be clicked. Anything up the chain with the two
    // ToolTipArea properties counts; nothing found means a plain tooltip.
    property var _toolTipArea: null
    function makeToolTipAreaInteractive() {
        let item = compact.parent;
        for (let depth = 0; item && depth < 8; depth++) {
            if ("interactive" in item && "mainItem" in item) {
                item.interactive = true;
                compact._toolTipArea = item;
                return;
            }
            item = item.parent;
        }
        compact._toolTipArea = null;
    }

    Timer {
        id: toolTipTimer
        interval: compact.toolTipDelay
        onTriggered: {
            const area = compact._toolTipArea;
            if (area && typeof area.showToolTip === "function")
                area.showToolTip();
        }
    }
    onParentChanged: compact.makeToolTipAreaInteractive()
    Component.onCompleted: compact.makeToolTipAreaInteractive()

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    // The panel fixes one side; the other follows so the icon is a square of
    // the panel thickness instead of staying at the minimum width.
    Layout.preferredWidth: vertical ? -1 : height
    Layout.preferredHeight: vertical ? width : -1

    Kirigami.Icon {
        id: icon
        objectName: "icon"
        anchors.fill: parent
        source: compact.iconName || "map-globe"
        // Kirigami.Icon recolours monochrome icons only; a coloured icon
        // keeps its own colours whatever is set here.
        color: compact.iconColor ? compact.iconColor : Kirigami.Theme.textColor
        active: mouseArea.containsMouse
    }

    Rectangle {
        objectName: "badge"
        visible: compact.badgeVisible
        width: Math.max(6, parent.width * 0.3)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: compact.badgeColor ? compact.badgeColor : Kirigami.Theme.highlightColor
        border.color: Kirigami.Theme.backgroundColor
        border.width: 1
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        // At 700 ms or more Plasma opens the tooltip itself.
        onEntered: if (compact.plasmaToolTipsEnabled && compact.toolTipDelay < 700)
            toolTipTimer.restart()
        onExited: toolTipTimer.stop()
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                compact.actions.random();
            else
                compact.actions.toggle();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y === 0) {
                wheel.accepted = false;
                return;
            }
            compact._wheelAccumulator += wheel.angleDelta.y * (compact.invertWheel ? -1 : 1);
            while (Math.abs(compact._wheelAccumulator) >= 120) {
                const step = compact._wheelAccumulator > 0 ? 0.05 : -0.05;
                compact.actions.volumeStep(step);
                compact._wheelAccumulator -= compact._wheelAccumulator > 0 ? 120 : -120;
            }
            wheel.accepted = true;
        }
    }
}
