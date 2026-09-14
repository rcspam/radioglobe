import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "RadioModel.js" as RadioModel

PlasmoidItem {
    id: root

    // qmllint disable unresolved-type
    // KPluginMetaData is a C++ type Plasma does not expose declaratively.
    readonly property string appVersion: Plasmoid.metaData.version
    // qmllint enable unresolved-type
    readonly property string userAgent: "RadioGlobe/" + appVersion

    // Persisted JSON lists (Plasmoid.configuration holds strings). The binding
    // only seeds the initial value: the first write replaces it by a plain
    // assignment, config staying the persistence and root.* the live copy.
    property var favorites: root._parseList(Plasmoid.configuration.favorites)
    property var history: root._parseList(Plasmoid.configuration.history)

    // What the right-hand list shows and where it comes from.
    property var listStations: []
    property string listSource: "world"
    property int currentTab: 0
    property var currentCountry: null
    property string searchText: ""

    // Playback queue: the list displayed when the user picked a station.
    property var queue: []
    property var worldStations: radioBrowser.worldStations
    property var countries: []
    readonly property bool mprisAvailable: mprisLoader.status === Loader.Ready

    switchWidth: Kirigami.Units.gridUnit * 30
    switchHeight: Kirigami.Units.gridUnit * 20

    toolTipMainText: player.station ? player.station.name : i18n("RadioGlobe")
    toolTipSubText: {
        if (!player.station)
            return i18n("No station playing");
        if (player.state === "playing")
            return player.track || i18n("Playing");
        if (player.state === "paused")
            return i18n("Paused");
        if (player.state === "error")
            return i18n("Playback failed");
        return i18n("Stopped");
    }
    Plasmoid.status: player.state === "playing" ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    function playFrom(list, station) {
        root.queue = Array.isArray(list) && list.length > 0 ? list.slice() : [station];
        player.play(station);
    }

    function next() {
        const target = RadioModel.neighbourStation(root.queue, player.station ? player.station.uuid : "", 1);
        if (target)
            player.play(target);
    }

    function previous() {
        const target = RadioModel.neighbourStation(root.queue, player.station ? player.station.uuid : "", -1);
        if (target)
            player.play(target);
    }

    function playRandom() {
        const recent = root.history.map(entry => entry.uuid);
        const target = RadioModel.pickRandomStation(root.worldStations, recent);
        if (target)
            root.playFrom(root.worldStations, target);
    }

    function toggleFavorite(station) {
        root.favorites = RadioModel.toggleFavorite(root.favorites, station);
        Plasmoid.configuration.favorites = JSON.stringify(root.favorites);
        if (root.currentTab === 1)
            root._refreshList();
    }

    function isFavorite(uuid) {
        return RadioModel.indexByUuid(root.favorites, uuid) >= 0;
    }

    function openCountry(code, name) {
        root.currentCountry = {
            code: code,
            name: name
        };
        root.currentTab = 0;
        // Claim the source before the request goes out, so a world refresh
        // arriving meanwhile does not send _refreshList back through here.
        root.listSource = "country";
        radioBrowser.loadCountry(code, (stations, source) => {
            if (root.currentTab === 0 && root.currentCountry && root.currentCountry.code === code) {
                root.listStations = stations;
                root.listSource = "country";
            }
        });
    }

    function clearCountry() {
        root.currentCountry = null;
        root._refreshList();
    }

    function runSearch(text) {
        root.searchText = text;
        if (!text.trim()) {
            root._refreshList();
            return;
        }
        root.currentTab = 0;
        root.listSource = "search";
        radioBrowser.search(text, (stations, isFinal) => {
            if (root.currentTab === 0 && root.searchText === text) {
                root.listStations = stations;
                root.listSource = "search";
            }
        });
    }

    function clearSearch() {
        root.searchText = "";
        root._refreshList();
    }

    function stopAll() {
        player.quit();
    }

    function _refreshList() {
        if (root.currentTab === 1) {
            root.listStations = root.favorites;
            root.listSource = "favorites";
        } else if (root.currentTab === 2) {
            root.listStations = root.history;
            root.listSource = "history";
        } else if (root.currentCountry) {
            root.openCountry(root.currentCountry.code, root.currentCountry.name);
        } else if (root.searchText.trim()) {
            root.runSearch(root.searchText);
        } else {
            root.listStations = root.worldStations;
            root.listSource = "world";
        }
    }

    function _parseList(text) {
        try {
            const value = JSON.parse(String(text || "[]"));
            return Array.isArray(value) ? value : [];
        } catch (error) {
            return [];
        }
    }

    onCurrentTabChanged: root._refreshList()
    onWorldStationsChanged: if (root.listSource === "world")
        root._refreshList()
    onExpandedChanged: if (root.expanded)
        radioBrowser.expandWorld()

    Loader {
        id: mprisLoader
        source: "MprisSource.qml"
        onStatusChanged: if (status === Loader.Error)
            console.warn("[RadioGlobe] org.kde.plasma.private.mpris is not available")
    }

    Exec {
        id: exec
    }

    Http {
        id: http
        userAgent: root.userAgent
    }

    Cache {
        id: cache
    }

    RadioBrowser {
        id: radioBrowser
        request: http.request
        cache: cache
        countries: root.countries
        worldLimit: Plasmoid.configuration.maxWorldStations
        sendClicks: Plasmoid.configuration.sendClicks
        userAgentVersion: root.appVersion
    }

    Player {
        id: player
        mpris: mprisLoader.item
        exec: exec.run
        cfg: Plasmoid.configuration
        userAgent: root.userAgent
        onPlayingStarted: station => {
            radioBrowser.click(station.uuid);
            root.history = RadioModel.pushHistory(root.history, station, Date.now(), 20);
            Plasmoid.configuration.history = JSON.stringify(root.history);
            Plasmoid.configuration.lastStation = JSON.stringify(station);
            if (root.currentTab === 2)
                root._refreshList();
        }
    }

    Component.onCompleted: {
        // Qt refuses XMLHttpRequest on local files unless QML_XHR_ALLOW_FILE_READ
        // is set, which plasmashell does not do, so the bundled GeoJSON is read
        // through the same executable engine the player already relies on.
        const path = decodeURIComponent(String(Qt.resolvedUrl("../data/countries.json")).replace(/^file:\/\//, ""));
        exec.run("cat " + RadioModel.shellQuote(path), (exitCode, stdout) => {
            if (exitCode !== 0 || !stdout) {
                // No borders and no country centroids: stations without their own
                // coordinates simply never make it onto the globe.
                console.warn("[RadioGlobe] cannot read countries.json (exit " + exitCode + "), continuing without borders");
            } else {
                try {
                    const parsed = JSON.parse(stdout);
                    if (parsed && Array.isArray(parsed.features))
                        root.countries = parsed.features;
                    else
                        console.warn("[RadioGlobe] countries.json has no feature array");
                } catch (error) {
                    console.warn("[RadioGlobe] countries.json unreadable", error);
                }
            }
            radioBrowser.start();
            if (Plasmoid.formFactor === PlasmaCore.Types.Planar || root.expanded)
                radioBrowser.expandWorld();
        });
    }

    // Mpris2Model fills asynchronously, so the mpv that outlived plasmashell is
    // only found some time after startup: the station name is restored when the
    // player actually attaches, not in Component.onCompleted.
    Connections {
        target: player
        function onAttachedChanged() {
            if (!player.attached || player.station)
                return;
            try {
                const last = JSON.parse(Plasmoid.configuration.lastStation || "null");
                if (last && last.url)
                    player.adoptStation(last);
            } catch (error) {}
        }
    }

    // Placeholder until Task 10 provides the real compact representation.
    compactRepresentation: Kirigami.Icon {
        source: "radio"
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: FullRepresentation {}
}
