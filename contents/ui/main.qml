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
    // Set while openCountry / runSearch move back to the world tab themselves.
    property bool _switchingTab: false

    // Playback queue: the list displayed when the user picked a station.
    property var queue: []
    // Favourites edited by hand (localEdit) replace their Radio Browser row,
    // so a corrected location moves the dot instead of adding a second one.
    property var worldStations: RadioModel.applyLocalEdits(radioBrowser.worldStations, root.favorites)
    property var countries: []
    readonly property bool mprisAvailable: mprisLoader.status === Loader.Ready
    // The country whose stations are always on the globe: the configured one,
    // or the one of the user's locale ("fr_FR" -> "FR") when it is empty.
    readonly property string homeCountry: (Plasmoid.configuration.homeCountry || (Qt.locale().name.split("_")[1] || "")).toUpperCase()
    // Planar means the widget sits on the desktop or in a panel-less layout:
    // there is no popup to keep open, so the pin button hides itself.
    readonly property bool isOnDesktop: Plasmoid.formFactor === PlasmaCore.Types.Planar
    // Read and written through root so the views never touch
    // Plasmoid.configuration directly, which lets the tests fake it.
    readonly property bool pinned: Plasmoid.configuration.pinned
    readonly property bool approximateLocations: Plasmoid.configuration.approximateLocations
    readonly property bool showDayNight: Plasmoid.configuration.showDayNight

    function setPinned(value) {
        Plasmoid.configuration.pinned = value;
    }

    // Opens the configuration dialog on the "Add a station" page. Plasma
    // opens on the first visible category, so config.qml lists that page
    // first only while configStartPage says so; the page clears the flag
    // once it is up, and the sidebar falls back to its normal order.
    function openConfiguration() {
        Plasmoid.configuration.configStartPage = "addStation";
        Plasmoid.internalAction("configure").trigger();
    }

    // Same page, prefilled with an existing station: saving stores a local
    // copy in the favourites (same uuid, localEdit flag).
    function openStationEditor(station) {
        Plasmoid.configuration.editStation = JSON.stringify(station);
        root.openConfiguration();
    }

    // Pinned: the popup survives losing focus, which is what lets the user
    // click around while the station list stays on screen.
    hideOnWindowDeactivate: !root.pinned

    switchWidth: Kirigami.Units.gridUnit * 30
    switchHeight: Kirigami.Units.gridUnit * 20

    // The widget's own icon (desktop form, tooltips) follows the setting too.
    Plasmoid.icon: Plasmoid.configuration.icon || "map-globe"

    // The station name and the ICY title both come from the broadcaster: never
    // let them be interpreted as rich text.
    toolTipTextFormat: Text.PlainText
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
    // The same texts with the transport buttons under them; the plain texts
    // above stay as the fallback the shell reads when it ignores the item.
    toolTipItem: CompactToolTip {
        player: player
        onPlayPauseRequested: player.togglePause()
        onNextRequested: root.next()
        onPreviousRequested: root.previous()
        onStopRequested: player.stop()
    }
    // A launcher, not a notifier: staying passive would hide the icon in the
    // system tray whenever nothing is playing, which is exactly when the user
    // needs it to pick a station.
    Plasmoid.status: PlasmaCore.Types.ActiveStatus

    // qmllint disable missing-property
    // Plasmoid.contextualActions is declared on the attached Plasmoid object,
    // which qmllint resolves to the applet type without it.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Random station")
            icon.name: "media-playlist-shuffle"
            onTriggered: root.playRandom()
        },
        PlasmaCore.Action {
            text: i18n("Stop and quit mpv")
            icon.name: "media-playback-stop"
            enabled: player.state !== "idle"
            onTriggered: root.stopAll()
        }
    ]
    // qmllint enable missing-property

    function playFrom(list, station) {
        // A country list or a search result carries the Radio Browser row;
        // a local edit of the same station wins, so the player, the globe
        // and "locate" all agree on where it is.
        const current = RadioModel.applyLocalEdits([station], root.favorites)[0];
        root.queue = Array.isArray(list) && list.length > 0 ? list.slice() : [current];
        player.play(current);
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

    function removeFromHistory(station) {
        if (!station || !station.uuid)
            return;
        root.history = RadioModel.removeByUuid(root.history, station.uuid);
        Plasmoid.configuration.history = JSON.stringify(root.history);
        if (root.currentTab === 2)
            root._refreshList();
    }

    function renameFavorite(station, name) {
        if (!station || !station.uuid)
            return;
        root.favorites = RadioModel.renameFavorite(root.favorites, station.uuid, name);
        Plasmoid.configuration.favorites = JSON.stringify(root.favorites);
        if (root.currentTab === 1)
            root._refreshList();
    }

    function isFavorite(uuid) {
        return RadioModel.indexByUuid(root.favorites, uuid) >= 0;
    }

    // True between the click on a country and its stations arriving: the
    // list is emptied meanwhile and says "Loading…", so the country lands
    // in one go instead of replacing the previous list a second later.
    property bool loadingCountry: false

    function openCountry(code, name) {
        root._selectWorldTab();
        root.currentCountry = {
            code: code,
            name: name
        };
        // With text in the search field, a country click means "the same
        // search, in that country", not the whole country.
        if (root.searchText.trim()) {
            root.runSearch(root.searchText);
            return;
        }
        // Claim the source before the request goes out, so a world refresh
        // arriving meanwhile does not send _refreshList back through here.
        root.listSource = "country";
        root.listStations = [];
        root.loadingCountry = true;
        radioBrowser.loadCountry(code, (stations, source) => {
            if (root.currentTab === 0 && root.currentCountry && root.currentCountry.code === code) {
                root.listStations = stations;
                root.listSource = "country";
                root.loadingCountry = false;
            }
        });
    }

    function clearCountry() {
        root.currentCountry = null;
        root.loadingCountry = false;
        root._refreshList();
    }

    function runSearch(text) {
        root.searchText = text;
        if (!text.trim()) {
            root._refreshList();
            return;
        }
        root._selectWorldTab();
        root.listSource = "search";
        // Inside an open country, the search is limited to it.
        radioBrowser.search(text, (stations, isFinal) => {
            if (root.currentTab === 0 && root.searchText === text) {
                root.listStations = stations;
                root.listSource = "search";
            }
        }, root.currentCountry ? root.currentCountry.code : "");
    }

    function clearSearch() {
        root.searchText = "";
        root._refreshList();
    }

    function stopAll() {
        player.quit();
    }

    // Going back to the world tab because a country or a search was opened
    // from another tab must not run _refreshList: the caller is on its way to
    // fill the list itself, and the re-entry would send the same request twice.
    function _selectWorldTab() {
        if (root.currentTab === 0)
            return;
        root._switchingTab = true;
        root.currentTab = 0;
        root._switchingTab = false;
    }

    function _refreshList() {
        root.loadingCountry = false;
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

    onCurrentTabChanged: if (!root._switchingTab)
        root._refreshList()
    onWorldStationsChanged: {
        if (root.listSource !== "world")
            return;
        // A cold start grows the world in 500-station rounds. The globe takes
        // each of them, but rebuilding the list every time costs more than it
        // shows, so the refresh waits for the rounds to settle.
        // The very first batch goes straight through, otherwise the list sits
        // empty next to a globe that is already filling up.
        if (radioBrowser.expanding && root.listStations.length > 0) {
            listRefreshTimer.restart();
            return;
        }
        listRefreshTimer.stop();
        root._refreshList();
    }
    onExpandedChanged: {
        if (!root.expanded)
            return;
        // Opening the popup is the natural moment to try again after an outage.
        if (radioBrowser.lastError === "offline")
            radioBrowser.refresh();
        else
            radioBrowser.expandWorld();
    }

    Loader {
        id: mprisLoader
        source: "MprisSource.qml"
        onStatusChanged: if (status === Loader.Error)
            console.warn("[RadioGlobe] org.kde.plasma.private.mpris is not available")
    }

    // What the host is missing (see Requirements.qml); the popup shows it.
    readonly property var missingModules: requirements.missingRequired.concat(requirements.missingOptional)
    // "deb", "arch", "fedora" or "" when /etc/os-release names none of them.
    property string distroFamily: ""
    readonly property string installCommand: requirements.installCommand(root.distroFamily)

    Requirements {
        id: requirements
    }

    // Exec needs org.kde.plasma.plasma5support. Through a Loader the widget
    // still comes up without it, with the banner saying what to install;
    // commands then fail with exit code 127 instead of never answering.
    Loader {
        id: execLoader
        source: "Exec.qml"
        onLoaded: root.detectDistro()
    }
    readonly property var exec: execLoader.item ? execLoader.item : ({
            run: (cmd, callback) => callback(127, "")
        })

    Http {
        id: http
        userAgent: root.userAgent
    }

    // The cache needs QtQuick.LocalStorage, which stock Kubuntu does not ship
    // (qml6-module-qtquick-localstorage). A Loader keeps the widget alive
    // without it: stations are simply fetched again at every start.
    Loader {
        id: cacheLoader
        source: "Cache.qml"
    }

    // The "Add a station" and "Backup" config pages write favourites and
    // history of their own. Our own writes in toggleFavorite and pushHistory
    // come back through here too, hence the comparison: they are already in
    // root.favorites / root.history.
    Connections {
        target: Plasmoid.configuration
        function onFavoritesChanged() {
            const parsed = root._parseList(Plasmoid.configuration.favorites);
            if (JSON.stringify(parsed) === JSON.stringify(root.favorites))
                return;
            root.favorites = parsed;
            if (root.currentTab === 1)
                root._refreshList();
        }
        function onHistoryChanged() {
            const parsed = root._parseList(Plasmoid.configuration.history);
            if (JSON.stringify(parsed) === JSON.stringify(root.history))
                return;
            root.history = parsed;
            if (root.currentTab === 2)
                root._refreshList();
        }
    }

    Timer {
        id: listRefreshTimer
        interval: 250
        onTriggered: if (root.listSource === "world")
            root._refreshList()
    }

    RadioBrowser {
        id: radioBrowser
        request: http.request
        cache: cacheLoader.item
        countries: root.countries
        worldLimit: Plasmoid.configuration.maxWorldStations
        countryStationLimit: Plasmoid.configuration.maxCountryStations
        searchStationLimit: Plasmoid.configuration.maxSearchStations
        homeCountry: root.homeCountry
        approximateLocations: Plasmoid.configuration.approximateLocations
        sendClicks: Plasmoid.configuration.sendClicks
        userAgentVersion: root.appVersion
    }

    Player {
        id: player
        mpris: mprisLoader.item
        exec: root.exec.run
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

    // Runs once Exec is loaded and something is missing; the order in which
    // Component.onCompleted handlers fire is undefined, hence the two triggers.
    property bool _distroAsked: false
    function detectDistro() {
        if (root._distroAsked || !execLoader.item || root.missingModules.length === 0)
            return;
        root._distroAsked = true;
        // Through root.exec: the linter only knows the Loader item as a QObject.
        root.exec.run(". /etc/os-release 2>/dev/null; echo \"$ID $ID_LIKE\"", (code, out) => {
            if (code === 0)
                root.distroFamily = requirements.familyFromOsRelease(out);
        });
    }
    onMissingModulesChanged: root.detectDistro()

    // The last station played, parsed from the configuration, or null.
    function lastStation() {
        try {
            const last = JSON.parse(Plasmoid.configuration.lastStation || "null");
            return last && last.url ? last : null;
        } catch (error) {
            return null;
        }
    }

    // Autoplay waits for the MPRIS model to report an mpv that outlived
    // plasmashell: if one is playing, the restored station is left alone.
    Timer {
        id: autoplayTimer
        interval: 2500
        onTriggered: player.startIfIdle()
    }

    Component.onCompleted: {
        root.detectDistro();
        if (Plasmoid.configuration.restoreLastStation) {
            const last = root.lastStation();
            if (last) {
                player.adoptStation(last);
                if (Plasmoid.configuration.autoplayLastStation)
                    autoplayTimer.start();
            }
        }
        // First launch: give the popup its intended size before it ever opens
        // (see popupWidth in main.xml). Later resizes by the user win: Plasma
        // rewrites these two keys every time the popup closes.
        if (!Plasmoid.configuration.popupWidth && !Plasmoid.configuration.popupHeight) {
            Plasmoid.configuration.popupWidth = Kirigami.Units.gridUnit * 45;
            Plasmoid.configuration.popupHeight = Kirigami.Units.gridUnit * 30;
        }
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
            if (root.isOnDesktop || root.expanded)
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
            const last = root.lastStation();
            if (last)
                player.adoptStation(last);
        }
    }

    compactRepresentation: CompactRepresentation {
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        invertWheel: Plasmoid.configuration.invertWheel
        iconName: Plasmoid.configuration.icon
        iconColor: Plasmoid.configuration.iconColor
        badgeColor: Plasmoid.configuration.badgeColor
    }

    fullRepresentation: FullRepresentation {}
}
