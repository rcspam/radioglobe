import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// A one-line label for text that may be wider than the space it gets. Three
// modes, the Appearance setting picks one: "loop" (a pause, then the text
// runs off to the left with a second copy following, like a ticker),
// "bounce" (a pause, a glide to the end, a pause, a glide back) and "none"
// (the text is elided). Text that fits never moves in any mode.
Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property string mode: "loop"
    property int pauseMs: 2000
    property real pixelsPerSecond: 30

    readonly property bool overflowing: label.implicitWidth > root.width + 0.5
    readonly property bool scrolling: bounce.running || loop.running
    readonly property real textX: strip.x

    implicitHeight: label.implicitHeight
    implicitWidth: label.implicitWidth
    clip: true

    readonly property bool _eliding: root.mode === "none"
    readonly property bool _animating: root.overflowing && root.visible && root._windowShown && !root._eliding

    onTextChanged: {
        strip.x = 0;
        if (bounce.running)
            bounce.restart();
        if (loop.running)
            loop.restart();
    }
    onOverflowingChanged: if (!root.overflowing)
        strip.x = 0
    onModeChanged: strip.x = 0

    Item {
        id: strip
        height: label.implicitHeight
        width: label.implicitWidth

        PlasmaComponents3.Label {
            id: label
            textFormat: Text.PlainText
            width: root._eliding ? root.width : label.implicitWidth
            elide: root._eliding ? Text.ElideRight : Text.ElideNone
        }
        // The copy that follows the text around in loop mode.
        PlasmaComponents3.Label {
            id: echo
            visible: root.mode === "loop" && root.overflowing
            x: label.implicitWidth + root._gap
            text: label.text
            font: label.font
            color: label.color
            textFormat: Text.PlainText
        }
    }

    // The distances change with the text and the width; NumberAnimation
    // reads `to` and `duration` each time it starts, so bindings are enough.
    readonly property real _overflow: Math.max(0, label.implicitWidth - root.width)
    readonly property int _glideMs: Math.max(1, Math.round(root._overflow / root.pixelsPerSecond * 1000))
    readonly property real _gap: root.width / 2
    readonly property real _cycle: label.implicitWidth + root._gap
    readonly property int _cycleMs: Math.max(1, Math.round(root._cycle / root.pixelsPerSecond * 1000))

    // The popup and the panel tooltip keep their items alive while hidden;
    // no point animating text nobody sees.
    readonly property bool _windowShown: root.Window.visibility !== Window.Hidden

    SequentialAnimation {
        id: bounce
        running: root._animating && root.mode === "bounce"
        loops: Animation.Infinite
        // Hidden mid-glide (popup closed), the text would reappear shifted.
        onRunningChanged: if (!running)
            strip.x = 0
        PauseAnimation {
            duration: root.pauseMs
        }
        NumberAnimation {
            target: strip
            property: "x"
            to: -root._overflow
            duration: root._glideMs
        }
        PauseAnimation {
            duration: root.pauseMs
        }
        NumberAnimation {
            target: strip
            property: "x"
            to: 0
            duration: root._glideMs
        }
    }

    SequentialAnimation {
        id: loop
        running: root._animating && root.mode === "loop"
        loops: Animation.Infinite
        onRunningChanged: if (!running)
            strip.x = 0
        PauseAnimation {
            duration: root.pauseMs
        }
        // One full cycle: once the copy sits where the text started, the
        // jump back to 0 is invisible.
        NumberAnimation {
            target: strip
            property: "x"
            from: 0
            to: -root._cycle
            duration: root._cycleMs
        }
        PropertyAction {
            target: strip
            property: "x"
            value: 0
        }
    }
}
