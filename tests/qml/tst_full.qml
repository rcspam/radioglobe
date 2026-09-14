import QtQuick
import QtTest
import "../../contents/ui" as Ui

// Harness for the FullRepresentation wiring. The fake context objects carry the
// same ids as main.qml (root, player, radioBrowser) so the component resolves
// them through the context chain exactly as it does inside the plasmoid.
TestCase {
    name: "FullRepresentation"
    when: windowShown
    width: 900
    height: 600
    visible: true

    function i18n(text, a, b) {
        return String(text).replace("%1", a).replace("%2", b);
    }

    function i18np(singular, plural, count) {
        return String(count === 1 ? singular : plural).replace("%1", count);
    }

    QtObject {
        id: root

        property var countries: []
        property var worldStations: [
            {
                uuid: "a",
                name: "Alpha",
                url: "https://s/a.mp3",
                countryCode: "FR",
                codec: "MP3",
                bitrate: 128,
                latitude: 48.85,
                longitude: 2.35
            },
            {
                uuid: "b",
                name: "Bravo",
                url: "https://s/b.mp3",
                countryCode: "DE",
                codec: "AAC",
                bitrate: 64,
                latitude: 52.52,
                longitude: 13.4
            }
        ]
        property var listStations: root.worldStations
        property string listSource: "world"
        property int currentTab: 0
        property var currentCountry: null
        property string searchText: ""
        property var favorites: []
        property bool expanded: true
        property var calls: []

        function isFavorite(uuid) {
            return false;
        }

        function playFrom(stations, station) {
            root.calls.push("play:" + station.uuid);
        }

        function openCountry(code, name) {
            root.calls.push("country:" + code);
        }

        function runSearch(text) {
            root.calls.push("search:" + text);
        }

        function clearSearch() {
            root.calls.push("clearSearch");
        }

        function playRandom() {
            root.calls.push("random");
        }

        function toggleFavorite(station) {
            root.calls.push("fav:" + station.uuid);
        }

        function next() {
            root.calls.push("next");
        }

        function previous() {
            root.calls.push("previous");
        }

        function clearCountry() {
            root.calls.push("clearCountry");
        }
    }

    QtObject {
        id: player

        property string state: "idle"
        property var station: null
        property string track: ""
        property real volume: 0.5
        property bool muted: false
        property string errorKind: ""
        property var calls: []

        signal playingStarted(var station)

        function togglePause() {
            player.calls.push("togglePause");
        }

        function stop() {
            player.calls.push("stop");
        }

        function quit() {
            player.calls.push("quit");
        }

        function retry() {
            player.calls.push("retry");
        }

        function setVolume(value) {
            player.calls.push("volume:" + value);
        }

        function toggleMute() {
            player.calls.push("toggleMute");
        }
    }

    QtObject {
        id: radioBrowser

        property string lastError: ""
    }

    Loader {
        id: loader
        width: 700
        height: 500
        sourceComponent: Component {
            Ui.FullRepresentation {}
        }
    }

    function init() {
        root.calls = [];
        player.calls = [];
    }

    function test_loads_without_errors() {
        compare(loader.status, Loader.Ready);
        verify(loader.item !== null);
        compare(loader.item.mediaPlayer, player);
    }

    function test_station_list_activation_reaches_root() {
        const list = findChild(loader.item, "stationList");
        verify(list !== null, "stationList not found");
        compare(list.stations.length, 2);
        list.selectedIndex = -1;
        list.moveSelection(1);
        compare(list.selectedIndex, 0);
        list.activateSelected();
        compare(root.calls.indexOf("play:a") >= 0, true, JSON.stringify(root.calls));
    }

    function test_player_bar_buttons_reach_player() {
        const playerBar = findChild(loader.item, "playerBar");
        verify(playerBar !== null, "playerBar not found");
        compare(playerBar.player, player);
        playerBar.playPauseRequested();
        playerBar.volumeRequested(0.3);
        playerBar.nextRequested();
        playerBar.previousRequested();
        playerBar.muteRequested();
        playerBar.stopRequested();
        compare(player.calls.indexOf("togglePause") >= 0, true, JSON.stringify(player.calls));
        compare(player.calls.indexOf("volume:0.3") >= 0, true, JSON.stringify(player.calls));
        compare(player.calls.indexOf("toggleMute") >= 0, true, JSON.stringify(player.calls));
        compare(player.calls.indexOf("stop") >= 0, true, JSON.stringify(player.calls));
        compare(root.calls.indexOf("next") >= 0, true, JSON.stringify(root.calls));
        compare(root.calls.indexOf("previous") >= 0, true, JSON.stringify(root.calls));
    }

    function test_search_bar_reaches_root() {
        const searchBar = findChild(loader.item, "searchBar");
        verify(searchBar !== null, "searchBar not found");
        searchBar.text = "jazz";
        searchBar.searchRequested("jazz");
        searchBar.randomRequested();
        compare(root.calls.indexOf("search:jazz") >= 0, true, JSON.stringify(root.calls));
        compare(root.calls.indexOf("random") >= 0, true, JSON.stringify(root.calls));
        // Emptying the field asks the plasmoid to drop the search.
        searchBar.text = "";
        compare(root.calls.indexOf("clearSearch") >= 0, true, JSON.stringify(root.calls));
    }

    function test_globe_country_click_reaches_root() {
        const globe = findChild(loader.item, "globe");
        verify(globe !== null, "globe not found");
        globe.countryActivated("FR", "France");
        globe.stationActivated(root.worldStations[1]);
        compare(root.calls.indexOf("country:FR") >= 0, true, JSON.stringify(root.calls));
        compare(root.calls.indexOf("play:b") >= 0, true, JSON.stringify(root.calls));
    }

    function test_status_line_follows_context() {
        compare(loader.item.statusLine, "2 signals");
        root.currentCountry = {
            code: "FR",
            name: "France"
        };
        compare(loader.item.statusLine, "France · click another country to browse");
        root.currentCountry = null;
        radioBrowser.lastError = "offline";
        compare(loader.item.statusLine, "Radio Browser unreachable, showing cached data");
        radioBrowser.lastError = "";
    }
}
