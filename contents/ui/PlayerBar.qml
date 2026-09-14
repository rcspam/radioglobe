import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: bar

    property var player: null
    property bool favorite: false

    signal playPauseRequested
    signal stopRequested
    signal quitRequested
    signal nextRequested
    signal previousRequested
    signal retryRequested
    signal volumeRequested(real value)
    signal muteRequested
    signal favoriteRequested
    // Double click on the station name: show it on the globe.
    signal locateRequested
    // Edit button: fix the station's details (its location above all)
    // locally, in the configuration dialog.
    signal editRequested

    // Deliberately shadows Item.state: this component has no QML states and
    // reads far better as the player state everywhere below.
    readonly property string state: bar.player ? String(bar.player.state) : "idle"
    readonly property string primaryText: bar.player && bar.player.station ? bar.player.station.name : i18n("No station selected")
    readonly property string secondaryText: {
        if (!bar.player || !bar.player.station)
            return i18n("Pick a signal on the globe or a station in the list");
        if (bar.player.track)
            return bar.player.track;
        switch (bar.state) {
        case "starting":
            return i18n("Starting mpv…");
        case "loading":
            return i18n("Connecting…");
        case "playing":
            return i18n("Live");
        case "paused":
            return i18n("Paused");
        case "error":
            return i18n("Playback failed");
        default:
            return i18n("Stopped");
        }
    }
    readonly property string errorText: {
        if (bar.state !== "error")
            return "";
        switch (bar.player.errorKind) {
        case "mpv-missing":
            return i18n("mpv is not installed. Install the “mpv” and “mpv-mpris” packages, then try again.");
        case "mpris-missing":
            return i18n("mpv started but did not appear on MPRIS. Install the “mpv-mpris” package.");
        case "mpris-module-missing":
            return i18n("This Plasma version does not provide the MPRIS module (org.kde.plasma.private.mpris) RadioGlobe needs to control mpv.");
        default:
            return i18n("This station could not be played. It may be offline; retry or pick another one.");
        }
    }

    spacing: Kirigami.Units.smallSpacing

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: bar.errorText !== ""
        type: Kirigami.MessageType.Warning
        text: bar.errorText
        actions: Kirigami.Action {
            text: i18n("Retry")
            icon.name: "view-refresh"
            visible: bar.player && bar.player.errorKind === "stream"
            onTriggered: bar.retryRequested()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Item {
            id: stationText
            objectName: "stationText"
            Layout.fillWidth: true
            implicitHeight: stationTextColumn.implicitHeight

            ColumnLayout {
                id: stationTextColumn
                anchors.fill: parent
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: bar.primaryText
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.bold: true
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: bar.secondaryText
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    opacity: 0.75
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onDoubleClicked: if (bar.player && bar.player.station)
                    bar.locateRequested()
            }
        }
        PlasmaComponents3.ToolButton {
            objectName: "editButton"
            icon.name: "document-edit"
            enabled: bar.player && bar.player.station ? true : false
            onClicked: bar.editRequested()
            Accessible.name: i18n("Edit this station…")
            PlasmaComponents3.ToolTip.text: i18n("Edit this station…")
            PlasmaComponents3.ToolTip.visible: hovered
        }
        PlasmaComponents3.ToolButton {
            icon.name: bar.favorite ? "starred-symbolic" : "non-starred-symbolic"
            enabled: bar.player && bar.player.station
            onClicked: bar.favoriteRequested()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.ToolButton {
            icon.name: "media-skip-backward"
            onClicked: bar.previousRequested()
        }
        PlasmaComponents3.ToolButton {
            icon.name: bar.state === "playing" || bar.state === "loading" ? "media-playback-pause" : "media-playback-start"
            enabled: bar.player && bar.player.station
            onClicked: bar.playPauseRequested()
        }
        PlasmaComponents3.ToolButton {
            icon.name: "media-skip-forward"
            onClicked: bar.nextRequested()
        }
        PlasmaComponents3.ToolButton {
            icon.name: "media-playback-stop"
            enabled: bar.state !== "idle"
            onClicked: bar.stopRequested()
            onPressAndHold: bar.quitRequested()
            PlasmaComponents3.ToolTip.text: i18n("Stop (hold to quit mpv)")
            PlasmaComponents3.ToolTip.visible: hovered
        }
        PlasmaComponents3.ToolButton {
            icon.name: bar.player && bar.player.muted ? "audio-volume-muted" : "audio-volume-high"
            onClicked: bar.muteRequested()
        }
        // The slider takes the width the buttons leave, down to 4 grid
        // units: that is what lets the whole bar fit a 40 % column.
        PlasmaComponents3.Slider {
            Layout.fillWidth: true
            Layout.minimumWidth: Kirigami.Units.gridUnit * 4
            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            from: 0
            to: 1
            stepSize: 0.01
            value: bar.player ? bar.player.volume : 0
            onMoved: bar.volumeRequested(value)
        }
        // Without a fixed width the label is 17 px wide at "5%" and 31 px at
        // "100%", and the spacer above absorbs the difference: the slider and
        // the mute button slide left under the cursor while it is dragged.
        TextMetrics {
            id: percentMetrics
            font: percentLabel.font
            text: "100%"
        }
        PlasmaComponents3.Label {
            id: percentLabel
            objectName: "volumeLabel"
            Layout.preferredWidth: percentMetrics.width
            Layout.minimumWidth: percentMetrics.width
            horizontalAlignment: Text.AlignRight
            text: bar.player ? Math.round(bar.player.volume * 100) + "%" : ""
            opacity: 0.75
        }
    }
}
