import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: bar

    property alias text: field.text

    signal searchRequested(string text)
    signal cleared
    signal randomRequested

    function focusInput() {
        field.forceActiveFocus();
        field.selectAll();
    }

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.TextField {
        id: field
        Layout.fillWidth: true
        placeholderText: i18n("Search stations, countries, tags…")
        onAccepted: bar.searchRequested(text)
        onTextChanged: if (text === "")
            bar.cleared()
        Keys.onEscapePressed: event => {
            if (text !== "")
                text = "";
            else
                event.accepted = false;
        }
    }

    PlasmaComponents3.ToolButton {
        icon.name: "media-playlist-shuffle"
        text: i18n("Random")
        display: PlasmaComponents3.AbstractButton.IconOnly
        onClicked: bar.randomRequested()
        PlasmaComponents3.ToolTip.text: i18n("Tune a random station (R)")
        PlasmaComponents3.ToolTip.visible: hovered
    }
}
