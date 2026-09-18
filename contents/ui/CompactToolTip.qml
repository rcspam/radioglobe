import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// The panel icon's tooltip: the station and its title, plus the transport
// buttons. Plasma shows it through PlasmoidItem.toolTipItem; the icon makes
// the hosting tooltip area interactive so the buttons can be clicked.
Item {
    id: tip

    property var player: null
    // Local time where the station broadcasts, after its name (LocalClock.qml).
    property string localTime: ""
    property string localTimeDescription: ""

    signal playPauseRequested
    signal nextRequested
    signal previousRequested
    signal stopRequested
    signal volumeRequested(real value)
    signal muteRequested

    readonly property bool hasStation: player && player.station ? true : false
    readonly property string mainText: hasStation ? String(player.station.name) : i18n("RadioGlobe")
    readonly property string subText: {
        if (!hasStation)
            return i18n("No station playing");
        if (player.state === "playing")
            return player.track || i18n("Playing");
        if (player.state === "paused")
            return i18n("Paused");
        if (player.state === "error")
            return i18n("Playback failed");
        return i18n("Stopped");
    }

    implicitWidth: Math.max(column.implicitWidth, Kirigami.Units.gridUnit * 16)
    implicitHeight: column.implicitHeight
    width: implicitWidth
    height: implicitHeight

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        // Same lines as the player bar: they slide when the text is wider
        // than the tooltip lets itself grow.
        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            spacing: Kirigami.Units.smallSpacing

            MarqueeLabel {
                objectName: "tipMain"
                Layout.fillWidth: true
                text: tip.mainText
                font.bold: true
            }
            PlasmaComponents3.Label {
                objectName: "tipClock"
                visible: tip.hasStation && tip.localTime !== ""
                text: tip.localTime
                textFormat: Text.PlainText
                opacity: 0.75
                PlasmaComponents3.ToolTip.text: tip.localTimeDescription
                PlasmaComponents3.ToolTip.visible: clockHover.hovered && tip.localTimeDescription !== ""
                PlasmaComponents3.ToolTip.delay: Kirigami.Units.toolTipDelay
                HoverHandler {
                    id: clockHover
                }
            }
        }
        MarqueeLabel {
            objectName: "tipSub"
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            text: tip.subText
            opacity: 0.75
        }
        // Transport, then mute, volume and its percentage, as in PlayerBar.
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.ToolButton {
                objectName: "tipPrevious"
                icon.name: "media-skip-backward"
                enabled: tip.hasStation
                onClicked: tip.previousRequested()
                Accessible.name: i18n("Previous")
            }
            PlasmaComponents3.ToolButton {
                objectName: "tipPlayPause"
                icon.name: tip.player && tip.player.state === "playing" ? "media-playback-pause" : "media-playback-start"
                enabled: tip.hasStation
                onClicked: tip.playPauseRequested()
                Accessible.name: i18n("Play or pause")
            }
            PlasmaComponents3.ToolButton {
                objectName: "tipNext"
                icon.name: "media-skip-forward"
                enabled: tip.hasStation
                onClicked: tip.nextRequested()
                Accessible.name: i18n("Next")
            }
            PlasmaComponents3.ToolButton {
                objectName: "tipStop"
                icon.name: "media-playback-stop"
                enabled: tip.player && (tip.player.state === "playing" || tip.player.state === "paused" || tip.player.state === "loading") ? true : false
                onClicked: tip.stopRequested()
                Accessible.name: i18n("Stop")
            }
            PlasmaComponents3.ToolButton {
                objectName: "tipMute"
                icon.name: tip.player && tip.player.muted ? "audio-volume-muted" : "audio-volume-high"
                onClicked: tip.muteRequested()
                Accessible.name: i18n("Mute")
            }
            PlasmaComponents3.Slider {
                objectName: "tipVolume"
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 4
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                from: 0
                to: 1
                stepSize: 0.01
                value: tip.player ? Number(tip.player.volume) || 0 : 0
                onMoved: tip.volumeRequested(value)
            }
            TextMetrics {
                id: percentMetrics
                font: percentLabel.font
                text: "100%"
            }
            PlasmaComponents3.Label {
                id: percentLabel
                objectName: "tipPercent"
                Layout.preferredWidth: percentMetrics.width
                Layout.minimumWidth: percentMetrics.width
                horizontalAlignment: Text.AlignRight
                text: tip.player ? Math.round((Number(tip.player.volume) || 0) * 100) + "%" : ""
                opacity: 0.75
            }
        }
    }
}
