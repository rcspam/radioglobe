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
    property string iconName: "map-globe"
    // "#rrggbb" or empty for the theme colour.
    property string iconColor: ""
    property string badgeColor: ""
    readonly property bool badgeVisible: compact.playing
    property real _wheelAccumulator: 0

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small

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
