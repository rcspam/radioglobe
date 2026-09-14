import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import ".." as Ui
import "../RadioModel.js" as RadioModel

// "Add a station" page: a form, a map to place the station, and an optional
// submission to Radio Browser. The station lands in the favourites right
// away (Plasmoid.configuration is written directly, no Apply needed).
KCM.SimpleKCM {
    id: page

    // qmllint disable unresolved-type
    // KPluginMetaData is a C++ type Plasma does not expose declaratively.
    readonly property string userAgent: {
        try {
            return "RadioGlobe/" + Plasmoid.metaData.version;
        } catch (error) {
            return "RadioGlobe";
        }
    }
    // qmllint enable unresolved-type
    readonly property string homeCountry: {
        try {
            return String(Plasmoid.configuration.homeCountry || "");
        } catch (error) {
            return "";
        }
    }

    property var countries: []
    // The LocationPicker instance, or null without QtLocation. Typed var so
    // the page never names the QtLocation-backed type itself.
    readonly property var map: mapLoader.item
    property bool busy: false
    property string status: ""
    property bool searching: false
    property var searchResults: []
    property string searchStatus: ""

    function fields() {
        return {
            name: nameField.text,
            url: urlField.text,
            homepage: homepageField.text,
            countryCode: countryField.text,
            tags: tagsField.text,
            latitude: latitudeField.text,
            longitude: longitudeField.text
        };
    }

    function validationMessage(fields) {
        if (!RadioModel.cleanText(fields.name, 160))
            return i18n("Enter a station name.");
        if (!RadioModel.webUrlOrEmpty(fields.url))
            return i18n("Enter a valid http(s) stream URL.");
        return i18n("Enter both latitude and longitude, or leave both empty.");
    }

    function randomHex(length) {
        let out = "";
        for (let i = 0; i < length; i++)
            out += Math.floor(Math.random() * 16).toString(16);
        return out;
    }

    function add() {
        const form = page.fields();
        const local = RadioModel.stationFromForm(form, "local-" + page.randomHex(16));
        if (!local) {
            page.status = page.validationMessage(form);
            return;
        }
        if (!publish.checked) {
            page.store(local, i18n("Added to your favourites."));
            return;
        }
        page.busy = true;
        page.status = i18n("Checking Radio Browser…");
        radioBrowser.submit(form, result => {
            page.busy = false;
            if (result.status === "exists")
                page.store(result.station, i18n("Already on Radio Browser as “%1”: added that one to your favourites.", result.station.name));
            else if (result.status === "added")
                page.store(RadioModel.stationFromForm(form, result.uuid) || local, i18n("Published on Radio Browser. Added to your favourites."));
            else if (result.status === "error")
                page.store(local, i18n("Radio Browser refused the station: %1. Kept locally only.", result.message));
            else
                page.store(local, i18n("Radio Browser unreachable. Kept locally only."));
        });
    }

    function store(station, message) {
        let rows = [];
        try {
            rows = JSON.parse(String(Plasmoid.configuration.favorites || "[]"));
        } catch (error) {}
        if (!Array.isArray(rows))
            rows = [];
        Plasmoid.configuration.favorites = JSON.stringify(RadioModel.prioritizeStations([station], rows, 100000));
        page.clearForm();
        page.status = message;
    }

    function clearForm() {
        nameField.text = "";
        urlField.text = "";
        homepageField.text = "";
        tagsField.text = "";
        latitudeField.text = "";
        longitudeField.text = "";
        publish.checked = false;
    }

    // Address search through Nominatim, on Enter only (its usage policy
    // forbids autocomplete). One result goes straight to the map; several
    // are listed for the user to pick.
    function searchAddress() {
        const url = RadioModel.nominatimUrl(addressField.text);
        if (!url || page.searching)
            return;
        page.searching = true;
        page.searchResults = [];
        page.searchStatus = i18n("Searching…");
        http.request(url, (status, text) => {
            page.searching = false;
            if (status !== 200) {
                page.searchStatus = i18n("Address search unavailable (OpenStreetMap did not answer).");
                return;
            }
            const results = RadioModel.parseNominatim(text);
            if (results.length === 0) {
                page.searchStatus = i18n("No place found for “%1”.", addressField.text.trim());
            } else if (results.length === 1) {
                page.searchStatus = "";
                page.goTo(results[0]);
            } else {
                page.searchStatus = "";
                page.searchResults = results;
            }
        });
    }

    // Puts the marker on a search result and frames it on the map.
    function goTo(place) {
        page.searchResults = [];
        latitudeField.text = place.latitude.toFixed(4);
        longitudeField.text = place.longitude.toFixed(4);
        page.syncMarker();
        if (page.map)
            page.map.centreOn(place.latitude, place.longitude, place.zoom);
    }

    // Both fields typed by hand (or filled by the map): the marker follows.
    function syncMarker() {
        const latitude = RadioModel.finiteInRange(latitudeField.text.trim(), -90, 90);
        const longitude = RadioModel.finiteInRange(longitudeField.text.trim(), -180, 180);
        if (!page.map)
            return;
        page.map.hasMarker = latitude !== null && longitude !== null;
        if (latitude !== null && longitude !== null) {
            page.map.latitude = latitude;
            page.map.longitude = longitude;
        }
    }

    // The map opens on the country of the form, and follows it until a
    // marker is placed.
    function centreMapOnCountry() {
        if (!page.map || page.map.hasMarker)
            return;
        const centre = RadioModel.countryCentre(page.countries, countryField.text);
        if (centre)
            page.map.centreOn(centre.latitude, centre.longitude, 5);
        else
            page.map.centreOn(20, 0, 1);
    }

    Ui.Exec {
        id: exec
    }

    Ui.Http {
        id: http
        userAgent: page.userAgent
    }

    Ui.RadioBrowser {
        id: radioBrowser
        request: http.request
    }

    Component.onCompleted: {
        countryField.text = page.homeCountry || (Qt.locale().name.split("_")[1] || "");
        // Same route as main.qml: XMLHttpRequest cannot open local files in
        // plasmashell, so the bundled GeoJSON goes through `cat`.
        const path = decodeURIComponent(String(Qt.resolvedUrl("../../data/countries.json")).replace(/^file:\/\//, ""));
        exec.run("cat " + RadioModel.shellQuote(path), (exitCode, stdout) => {
            if (exitCode !== 0)
                return;
            try {
                const parsed = JSON.parse(stdout);
                if (parsed && Array.isArray(parsed.features))
                    page.countries = parsed.features;
            } catch (error) {}
            page.centreMapOnCountry();
        });
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.FormLayout {
            Layout.fillWidth: true

            QQC2.TextField {
                id: nameField
                Kirigami.FormData.label: i18n("Name:")
                maximumLength: 160
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: urlField
                Kirigami.FormData.label: i18n("Stream URL:")
                placeholderText: "https://…"
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: homepageField
                Kirigami.FormData.label: i18n("Homepage:")
                placeholderText: i18n("Optional")
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: countryField
                Kirigami.FormData.label: i18n("Country code:")
                maximumLength: 2
                validator: RegularExpressionValidator {
                    regularExpression: /[A-Za-z]{0,2}/
                }
                onEditingFinished: {
                    text = text.toUpperCase();
                    page.centreMapOnCountry();
                }
            }
            QQC2.TextField {
                id: tagsField
                Kirigami.FormData.label: i18n("Tags:")
                placeholderText: i18n("Comma separated, e.g. jazz,news")
                Layout.fillWidth: true
            }
            RowLayout {
                Kirigami.FormData.label: i18n("Location:")
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: latitudeField
                    placeholderText: i18n("Latitude")
                    onEditingFinished: page.syncMarker()
                }
                QQC2.TextField {
                    id: longitudeField
                    placeholderText: i18n("Longitude")
                    onEditingFinished: page.syncMarker()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: addressField
                objectName: "addressField"
                Layout.fillWidth: true
                placeholderText: i18n("Search an address or a place, then press Enter")
                enabled: !page.searching
                onAccepted: page.searchAddress()
            }
            QQC2.Button {
                icon.name: "search"
                text: i18n("Search")
                enabled: !page.searching && addressField.text.trim() !== ""
                onClicked: page.searchAddress()
            }
        }

        QQC2.Label {
            visible: page.searchStatus !== ""
            text: page.searchStatus
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        ColumnLayout {
            visible: page.searchResults.length > 0
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: page.searchResults
                delegate: QQC2.ItemDelegate {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.name
                    icon.name: "mark-location"
                    onClicked: page.goTo(modelData)
                }
            }
        }

        QQC2.Label {
            text: i18n("Click the map to place the station, scroll to zoom, drag to pan.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 18
            color: Kirigami.Theme.alternateBackgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1

            Loader {
                id: mapLoader
                anchors.fill: parent
                anchors.margins: 1
                source: "LocationPicker.qml"
                onLoaded: {
                    page.map.userAgent = page.userAgent;
                    page.map.picked.connect((latitude, longitude) => {
                        latitudeField.text = latitude.toFixed(4);
                        longitudeField.text = longitude.toFixed(4);
                        page.syncMarker();
                    });
                    page.centreMapOnCountry();
                }
            }

            // The page scrolls; the map must get the wheel and the drag.
            HoverHandler {
                enabled: mapLoader.status === Loader.Ready
                onHoveredChanged: page.flickable.interactive = !hovered
            }

            QQC2.Label {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.largeSpacing * 2
                visible: mapLoader.status === Loader.Error
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: i18n("Install the QtLocation QML module (qml6-module-qtlocation on Debian and Ubuntu) to pick the location on a map.")
            }
        }

        QQC2.Label {
            visible: mapLoader.status === Loader.Ready
            text: i18n("Map data © OpenStreetMap contributors")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        QQC2.CheckBox {
            id: publish
            text: i18n("Also publish on Radio Browser (public)")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            QQC2.Button {
                id: addButton
                text: i18n("Add")
                icon.name: "list-add"
                enabled: !page.busy
                onClicked: page.add()
            }
            QQC2.Label {
                text: page.status
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
}
