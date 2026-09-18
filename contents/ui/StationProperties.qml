import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// Everything Radio Browser knows about a station, as selectable text in a
// popup over the widget. Opened from the station menu.
QQC2.Popup {
    id: sheet

    property var station: null

    parent: QQC2.Overlay.overlay
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 28)
    modal: true
    focus: true
    closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside
    padding: Kirigami.Units.largeSpacing

    function open(target) {
        sheet.station = target;
        sheet.visible = true;
    }

    // One "Label: value" line per known field, empty ones left out.
    function describe(s) {
        if (!s)
            return "";
        const lines = [];
        const add = (label, value) => {
            if (value !== null && value !== undefined && String(value) !== "")
                lines.push(label + ": " + value);
        };
        add(i18n("Name"), s.name);
        add(i18n("Stream"), s.url);
        let format = String(s.codec || "");
        if (Number(s.bitrate) > 0)
            format += (format ? " · " : "") + i18n("%1 kbps", Number(s.bitrate));
        if (s.hls)
            format += (format ? " · " : "") + "HLS";
        add(i18n("Format"), format);
        add(i18n("Country"), s.country ? (s.countryCode ? s.country + " (" + s.countryCode + ")" : s.country) : s.countryCode);
        add(i18n("Region"), s.state);
        add(i18n("Language"), s.language);
        add(i18n("Tags"), s.tags);
        add(i18n("Homepage"), s.homepage);
        if (Number(s.clicks) > 0)
            add(i18n("Clicks on Radio Browser"), Number(s.clicks));
        if (Number(s.votes) > 0)
            add(i18n("Votes on Radio Browser"), Number(s.votes));
        if (s.latitude !== null && s.latitude !== undefined && s.longitude !== null && s.longitude !== undefined) {
            const where = Number(s.latitude).toFixed(4) + ", " + Number(s.longitude).toFixed(4);
            add(i18n("Location"), s.estimatedLocation ? i18n("%1 (approximate, inside the country)", where) : where);
        } else {
            add(i18n("Location"), i18n("unknown"));
        }
        add(i18n("Radio Browser id"), s.uuid);
        if (s.localEdit)
            lines.push(i18n("Edited locally: this is your version of the station."));
        return lines.join("\n");
    }

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 3
            text: sheet.station ? String(sheet.station.name || "") : ""
            elide: Text.ElideRight
        }
        Kirigami.SelectableLabel {
            objectName: "propertiesText"
            Layout.fillWidth: true
            text: sheet.describe(sheet.station)
            wrapMode: Text.Wrap
        }
        PlasmaComponents3.Button {
            Layout.alignment: Qt.AlignRight
            text: i18n("Close")
            icon.name: "dialog-close"
            onClicked: sheet.close()
        }
    }
}
