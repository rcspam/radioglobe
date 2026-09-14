import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes
import ".." as Ui
import "../RadioModel.js" as RadioModel

KCM.SimpleKCM {
    id: page

    property alias cfg_maxWorldStations: maxStations.value
    property alias cfg_homeCountry: homeCountry.text
    property alias cfg_mpvPath: mpvPath.text
    property alias cfg_sendClicks: sendClicks.checked
    property alias cfg_approximateLocations: approximateLocations.checked
    property alias cfg_invertWheel: invertWheel.checked
    property string cfg_icon: "radio"

    // A few icons that fit, one click each; the dialog opens the whole theme.
    readonly property var iconPresets: ["radio", "globe", "map-globe", "internet-services", "applications-multimedia"]

    // "fr_FR" -> "FR". What an empty home country setting falls back to.
    readonly property string localeCountry: Qt.locale().name.split("_")[1] || ""

    readonly property string checkingText: i18n("Checking…")
    readonly property string unknownText: i18n("Could not check (the command did not return). Try again.")

    property string mpvStatus: checkingText
    property string mprisStatus: checkingText

    Ui.Exec {
        id: exec
    }

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: iconName => {
            if (iconName)
                page.cfg_icon = iconName;
        }
    }

    Timer {
        id: probeTimeout
        interval: 5000
        onTriggered: {
            if (page.mpvStatus === page.checkingText)
                page.mpvStatus = page.unknownText;
            if (page.mprisStatus === page.checkingText)
                page.mprisStatus = page.unknownText;
        }
    }

    function probe() {
        page.mpvStatus = page.checkingText;
        page.mprisStatus = page.checkingText;
        probeTimeout.restart();
        const binary = mpvPath.text.trim() || "mpv";
        exec.run("command -v " + RadioModel.shellQuote(binary), (code, out) => {
            page.mpvStatus = code === 0 ? i18n("Found: %1", out.trim()) : i18n("Not found. Install the “mpv” package.");
        });
        exec.run("for f in /etc/mpv/scripts/mpris.so /usr/lib/mpv-mpris/mpris.so /usr/lib64/mpv-mpris/mpris.so /usr/lib/x86_64-linux-gnu/mpv-mpris/mpris.so \"$HOME/.config/mpv/scripts/mpris.so\"; do [ -e \"$f\" ] && echo \"$f\" && exit 0; done; exit 1", (code, out) => {
            page.mprisStatus = code === 0 ? i18n("Found: %1", out.trim()) : i18n("Not found. Install the “mpv-mpris” package (media keys and the Media Player widget need it).");
        });
    }

    Component.onCompleted: probe()

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: maxStations
            objectName: "maxStations"
            Kirigami.FormData.label: i18n("Maximum stations on the globe:")
            from: 500
            // RadioBrowser caps the merged world at 5500 rows internally:
            // asking for more only promises stations that never arrive.
            to: 5000
            stepSize: 500
        }
        QQC2.TextField {
            id: homeCountry
            objectName: "homeCountry"
            Kirigami.FormData.label: i18n("Home country:")
            placeholderText: i18n("Auto (%1 from your locale)", page.localeCountry)
            maximumLength: 2
            validator: RegularExpressionValidator {
                regularExpression: /[A-Za-z]{0,2}/
            }
            // Radio Browser only matches country codes in upper case.
            onEditingFinished: text = text.toUpperCase()
        }
        QQC2.Label {
            text: i18n("All geolocated stations of this country are always loaded on the globe and kept first.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        QQC2.CheckBox {
            id: approximateLocations
            text: i18n("Also show its stations without coordinates, at an approximate spot inside the country")
        }
        QQC2.Label {
            text: i18n("Radio Browser has no location for most stations. This places them at random inside their borders (the tooltip says “approximate location”), so the globe fills up but the dots do not mean much.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        QQC2.TextField {
            id: mpvPath
            Kirigami.FormData.label: i18n("mpv executable:")
            placeholderText: i18n("Absolute path, or leave empty to use mpv from PATH")
            onEditingFinished: page.probe()
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("mpv:")
            text: page.mpvStatus
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("mpv-mpris:")
            text: page.mprisStatus
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: i18n("Check again")
            icon.name: "view-refresh"
            onClicked: page.probe()
        }
        QQC2.CheckBox {
            id: sendClicks
            Kirigami.FormData.label: i18n("Radio Browser:")
            text: i18n("Report played stations to the click counter")
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Panel icon:")
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: page.iconPresets
                delegate: QQC2.Button {
                    required property string modelData
                    icon.name: modelData
                    icon.width: Kirigami.Units.iconSizes.smallMedium
                    icon.height: Kirigami.Units.iconSizes.smallMedium
                    checkable: true
                    checked: page.cfg_icon === modelData
                    onClicked: page.cfg_icon = modelData
                    Accessible.name: modelData
                    QQC2.ToolTip.text: modelData
                    QQC2.ToolTip.visible: hovered
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                icon.name: page.iconPresets.indexOf(page.cfg_icon) < 0 ? page.cfg_icon : "document-open"
                onClicked: iconDialog.open()
            }
        }
        QQC2.CheckBox {
            id: invertWheel
            text: i18n("Invert the mouse wheel direction for the volume")
        }
    }
}
