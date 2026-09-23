import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes
import org.kde.kquickcontrols as KQuickControls
import ".." as Ui
import "../RadioModel.js" as RadioModel

KCM.SimpleKCM {
    id: page

    ConfigWindowSize {}

    property alias cfg_maxWorldStations: maxStations.value
    property alias cfg_maxCountryStations: maxCountryStations.value
    property alias cfg_maxSearchStations: maxSearchStations.value
    property alias cfg_homeCountry: homeCountry.text
    property alias cfg_mpvPath: mpvPath.text
    property alias cfg_sendClicks: sendClicks.checked
    property alias cfg_approximateLocations: approximateLocations.checked
    property alias cfg_invertWheel: invertWheel.checked
    property alias cfg_toolTipDelay: toolTipDelay.value
    property alias cfg_showDayNight: showDayNight.checked
    property alias cfg_zoomStep: zoomStep.value
    property alias cfg_restoreLastStation: restoreLastStation.checked
    property alias cfg_autoplayLastStation: autoplayLastStation.checked
    property alias cfg_sleepPersist: sleepPersist.checked
    property string cfg_icon: "map-globe"
    property string cfg_nextPreviousSource: "queue"
    property string cfg_marqueeMode: "loop"
    // The list's sort and filters, also driven by the filter menu in the
    // popup; the dialog shows and saves the same keys.
    property string cfg_listSort: "popularity"
    property string cfg_codecFilter: ""
    property int cfg_minBitrate: 0
    readonly property var sortChoices: ["popularity", "votes", "name", "bitrate"]
    // The three families with the directory's station counts (0 offline).
    readonly property var codecRows: {
        const labels = {
            mp3: "MP3",
            aac: i18n("AAC (and AAC+)"),
            ogg: i18n("OGG (Vorbis)")
        };
        return radioBrowser.codecs.map(choice => ({
                    name: choice.name,
                    label: labels[choice.name] || choice.name,
                    count: choice.count
                }));
    }
    readonly property var bitrateChoices: [0, 64, 128, 192, 256]
    // Empty means "theme colour"; the check boxes drive that.
    property string cfg_iconColor: ""
    property string cfg_badgeColor: ""

    // A few icons that fit, one click each; the dialog opens the whole theme.
    readonly property var iconPresets: ["radio", "globe", "map-globe"]

    function hex(color) {
        return String(color).slice(0, 7);
    }

    // "fr_FR" -> "FR". What an empty home country setting falls back to.
    readonly property string localeCountry: Qt.locale().name.split("_")[1] || ""

    readonly property string checkingText: i18n("Checking…")
    readonly property string unknownText: i18n("Could not check (the command did not return). Try again.")

    property string mpvStatus: checkingText
    property string mprisStatus: checkingText
    // Whether QtQuick.LocalStorage loads here: same check as the widget's cache Loader.
    readonly property bool cacheAvailable: Qt.createComponent(Qt.resolvedUrl("../Cache.qml")).status === Component.Ready

    Ui.Http {
        id: http
        userAgent: "RadioGlobe (settings)"
    }

    // Only for the codec list: no world, no cache.
    Ui.RadioBrowser {
        id: radioBrowser
        request: http.request
        Component.onCompleted: radioBrowser.loadCodecs()
    }

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
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Globe")
        }
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
        QQC2.SpinBox {
            id: zoomStep
            objectName: "zoomStep"
            Kirigami.FormData.label: i18n("Zoom step (wheel notch, + and − buttons):")
            from: 5
            to: 100
            stepSize: 5
            textFromValue: (value, locale) => i18n("%1 %", value)
            valueFromText: (text, locale) => parseInt(text, 10) || 5
        }
        QQC2.SpinBox {
            id: maxCountryStations
            objectName: "maxCountryStations"
            Kirigami.FormData.label: i18n("Located stations per country:")
            from: 100
            to: 3000
            stepSize: 100
        }
        QQC2.Label {
            text: i18n("On top of the 300 most listened. Three times that for the largest countries (Russia, Canada, the United States, China, Brazil, Australia, India…).")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        QQC2.SpinBox {
            id: maxSearchStations
            objectName: "maxSearchStations"
            Kirigami.FormData.label: i18n("Located stations per search:")
            from: 100
            to: 3000
            stepSize: 100
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
        QQC2.CheckBox {
            id: showDayNight
            text: i18n("Shade the night side of the globe")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Station list")
        }
        QQC2.ComboBox {
            id: listSort
            objectName: "listSort"
            Kirigami.FormData.label: i18n("Sort by:")
            model: [i18n("Popularity"), i18n("Votes"), i18n("Name"), i18n("Bitrate")]
            currentIndex: Math.max(0, page.sortChoices.indexOf(page.cfg_listSort))
            onActivated: index => page.cfg_listSort = page.sortChoices[index]
        }
        // One line per family, with how many stations of the whole
        // directory it covers once /json/codecs has answered.
        ColumnLayout {
            objectName: "codecList"
            Kirigami.FormData.label: i18n("Codecs:")
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: page.codecRows
                delegate: QQC2.CheckBox {
                    required property var modelData
                    objectName: "codec-" + modelData.name
                    text: modelData.count > 0 ? i18n("%1 (%2 stations)", modelData.label, Number(modelData.count).toLocaleString(Qt.locale(), "f", 0)) : modelData.label
                    checked: RadioModel.codecSet(page.cfg_codecFilter).indexOf(modelData.name) >= 0
                    onToggled: page.cfg_codecFilter = RadioModel.toggleCodec(page.cfg_codecFilter, modelData.name, checked)
                }
            }
        }
        QQC2.Label {
            text: i18n("None checked: every codec. Counts are for the whole directory.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        QQC2.ComboBox {
            id: minBitrate
            objectName: "minBitrate"
            Kirigami.FormData.label: i18n("Minimum bitrate:")
            model: [i18n("Any bitrate"), i18n("%1 kbps", 64), i18n("%1 kbps", 128), i18n("%1 kbps", 192), i18n("%1 kbps", 256)]
            currentIndex: Math.max(0, page.bitrateChoices.indexOf(page.cfg_minBitrate))
            onActivated: index => page.cfg_minBitrate = page.bitrateChoices[index]
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Playback")
        }
        QQC2.CheckBox {
            id: restoreLastStation
            objectName: "restoreLastStation"
            Kirigami.FormData.label: i18n("At startup:")
            text: i18n("Show the last station played in the player")
        }
        QQC2.CheckBox {
            id: autoplayLastStation
            objectName: "autoplayLastStation"
            text: i18n("Start playing it")
            enabled: restoreLastStation.checked
        }
        QQC2.CheckBox {
            id: sleepPersist
            objectName: "sleepPersist"
            Kirigami.FormData.label: i18n("Sleep timer:")
            text: i18n("Keep it running when Plasma restarts")
        }
        QQC2.RadioButton {
            objectName: "nextFromQueue"
            Kirigami.FormData.label: i18n("Next and previous walk:")
            text: i18n("The list the station was played from")
            checked: page.cfg_nextPreviousSource !== "favorites"
            onClicked: page.cfg_nextPreviousSource = "queue"
        }
        QQC2.RadioButton {
            objectName: "nextFromFavorites"
            text: i18n("The favorites")
            checked: page.cfg_nextPreviousSource === "favorites"
            onClicked: page.cfg_nextPreviousSource = "favorites"
        }
        QQC2.CheckBox {
            id: invertWheel
            Kirigami.FormData.label: i18n("Mouse wheel on the icon:")
            text: i18n("Invert the direction for the volume")
        }
        QQC2.SpinBox {
            id: toolTipDelay
            objectName: "toolTipDelay"
            Kirigami.FormData.label: i18n("Icon tooltip appears after:")
            from: 0
            // Plasma opens it on its own at its usual 700 ms anyway.
            to: 700
            stepSize: 50
            textFromValue: (value, locale) => i18n("%1 ms", value)
            valueFromText: (text, locale) => parseInt(text, 10) || 0
        }
        QQC2.CheckBox {
            id: sendClicks
            Kirigami.FormData.label: i18n("Radio Browser:")
            text: i18n("Report played stations to the click counter")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Appearance")
        }
        QQC2.RadioButton {
            objectName: "marqueeLoop"
            Kirigami.FormData.label: i18n("Names and titles too long to fit:")
            text: i18n("Scroll in a loop")
            checked: page.cfg_marqueeMode !== "bounce" && page.cfg_marqueeMode !== "none"
            onClicked: page.cfg_marqueeMode = "loop"
        }
        QQC2.RadioButton {
            objectName: "marqueeBounce"
            text: i18n("Scroll back and forth")
            checked: page.cfg_marqueeMode === "bounce"
            onClicked: page.cfg_marqueeMode = "bounce"
        }
        QQC2.RadioButton {
            objectName: "marqueeNone"
            text: i18n("Cut with an ellipsis")
            checked: page.cfg_marqueeMode === "none"
            onClicked: page.cfg_marqueeMode = "none"
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
        RowLayout {
            Kirigami.FormData.label: i18n("Icon colour:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                id: customIconColor
                text: i18n("Custom")
                checked: page.cfg_iconColor !== ""
                onToggled: page.cfg_iconColor = checked ? page.hex(iconColorButton.color) : ""
            }
            KQuickControls.ColorButton {
                id: iconColorButton
                enabled: customIconColor.checked
                showAlphaChannel: false
                color: page.cfg_iconColor || Kirigami.Theme.textColor
                onAccepted: color => page.cfg_iconColor = page.hex(color)
            }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Playing badge colour:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.CheckBox {
                id: customBadgeColor
                text: i18n("Custom")
                checked: page.cfg_badgeColor !== ""
                onToggled: page.cfg_badgeColor = checked ? page.hex(badgeColorButton.color) : ""
            }
            KQuickControls.ColorButton {
                id: badgeColorButton
                enabled: customBadgeColor.checked
                showAlphaChannel: false
                color: page.cfg_badgeColor || Kirigami.Theme.highlightColor
                onAccepted: color => page.cfg_badgeColor = page.hex(color)
            }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("System")
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
        QQC2.Label {
            Kirigami.FormData.label: i18n("Offline cache:")
            text: page.cacheAvailable ? i18n("Available") : i18n("Not available: the QtQuick.LocalStorage module is missing (package “qml6-module-qtquick-localstorage” on Debian and Ubuntu). Stations are fetched again at every start.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: i18n("Check again")
            icon.name: "view-refresh"
            onClicked: page.probe()
        }
    }
}
