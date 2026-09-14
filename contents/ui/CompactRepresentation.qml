import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Panel / tray icon. Left click opens the popup, middle click tunes a random
// station, right click stops mpv, wheel adjusts the volume.
Item {
    id: compact

    property var actions: ({
            toggle: () => {
                root.expanded = !root.expanded;
            },
            random: () => root.playRandom(),
            stop: () => root.stopAll(),
            volumeStep: delta => player.setVolume(player.volume + delta)
        })
    property bool playing: typeof player !== "undefined" && player.state === "playing"
    readonly property bool badgeVisible: compact.playing
    property real _wheelAccumulator: 0

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small

    Kirigami.Icon {
        id: icon
        anchors.fill: parent
        source: "radio"
        active: mouseArea.containsMouse
    }

    Rectangle {
        visible: compact.badgeVisible
        width: Math.max(6, parent.width * 0.3)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: Kirigami.Theme.highlightColor
        border.color: Kirigami.Theme.backgroundColor
        border.width: 1
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                compact.actions.random();
            else if (mouse.button === Qt.RightButton)
                compact.actions.stop();
            else
                compact.actions.toggle();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y === 0) {
                wheel.accepted = false;
                return;
            }
            compact._wheelAccumulator += wheel.angleDelta.y;
            while (Math.abs(compact._wheelAccumulator) >= 120) {
                const step = compact._wheelAccumulator > 0 ? 0.05 : -0.05;
                compact.actions.volumeStep(step);
                compact._wheelAccumulator -= compact._wheelAccumulator > 0 ? 120 : -120;
            }
            wheel.accepted = true;
        }
    }
}
