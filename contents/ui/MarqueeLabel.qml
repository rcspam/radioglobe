import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// A one-line label that slides back and forth when its text is wider than
// the space it gets, instead of eliding it: a pause at the start, a glide to
// the end, a pause there, a glide back. Text that fits never moves.
Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property int pauseMs: 2000
    property real pixelsPerSecond: 30

    readonly property bool overflowing: label.implicitWidth > root.width + 0.5
    readonly property bool scrolling: animation.running
    readonly property real textX: label.x

    implicitHeight: label.implicitHeight
    implicitWidth: label.implicitWidth
    clip: true

    onTextChanged: {
        label.x = 0;
        if (animation.running)
            animation.restart();
    }
    onOverflowingChanged: if (!root.overflowing)
        label.x = 0

    PlasmaComponents3.Label {
        id: label
        textFormat: Text.PlainText
        elide: Text.ElideNone
    }

    // The distance changes with the text and the width; NumberAnimation reads
    // `to` and `duration` each time it starts, so bindings are enough.
    readonly property real _overflow: Math.max(0, label.implicitWidth - root.width)
    readonly property int _glideMs: Math.max(1, Math.round(root._overflow / root.pixelsPerSecond * 1000))

    // The popup and the panel tooltip keep their items alive while hidden;
    // no point animating text nobody sees.
    readonly property bool _windowShown: root.Window.visibility !== Window.Hidden

    SequentialAnimation {
        id: animation
        running: root.overflowing && root.visible && root._windowShown
        loops: Animation.Infinite
        PauseAnimation {
            duration: root.pauseMs
        }
        NumberAnimation {
            target: label
            property: "x"
            to: -root._overflow
            duration: root._glideMs
        }
        PauseAnimation {
            duration: root.pauseMs
        }
        NumberAnimation {
            target: label
            property: "x"
            to: 0
            duration: root._glideMs
        }
    }
}
