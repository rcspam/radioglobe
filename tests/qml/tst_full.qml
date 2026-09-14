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
        property var calls: []

        function refresh() {
            radioBrowser.calls.push("refresh");
        }
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
        radioBrowser.calls = [];
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

    function test_keys_reach_targets() {
        const targets = loader.item.keyTargets;
        targets.random();
        targets.mute();
        targets.volumeStep(0.05);
        compare(root.calls.indexOf("random") >= 0, true, JSON.stringify(root.calls));
        compare(player.calls.indexOf("toggleMute") >= 0, true, JSON.stringify(player.calls));
        compare(player.calls.indexOf("volume:0.55") >= 0, true, JSON.stringify(player.calls));
        root.currentCountry = null;
        const searchBar = findChild(loader.item, "searchBar");
        searchBar.text = "";
        root.expanded = true;
        targets.escape();
        compare(root.expanded, false);
    }

    function test_key_events_respect_search_focus() {
        loader.item.forceActiveFocus();
        keyClick(Qt.Key_R);
        compare(root.calls.indexOf("random") >= 0, true, JSON.stringify(root.calls));

        const field = findChild(loader.item, "searchField");
        verify(field !== null, "searchField not found");
        field.forceActiveFocus();
        field.text = "";
        const callsBeforeTyping = root.calls.length;
        keyClick(Qt.Key_R);
        compare(field.text, "r");
        compare(root.calls.length, callsBeforeTyping, JSON.stringify(root.calls));

        const list = findChild(loader.item, "stationList");
        verify(list !== null, "stationList not found");
        keyClick(Qt.Key_Down);
        compare(list.selectedIndex, 0);

        keyClick(Qt.Key_Return);
        compare(root.calls.indexOf("play:" + root.listStations[0].uuid) >= 0, true, JSON.stringify(root.calls));
        compare(root.calls.some(call => call.indexOf("search:") === 0), false, JSON.stringify(root.calls));

        field.text = "jazz";
        compare(list.selectedIndex, -1);
        keyClick(Qt.Key_Return);
        compare(root.calls.indexOf("search:jazz") >= 0, true, JSON.stringify(root.calls));
    }

    function test_escape_from_focused_empty_field_escalates() {
        const field = findChild(loader.item, "searchField");
        verify(field !== null, "searchField not found");
        field.forceActiveFocus();
        field.text = "";

        root.currentCountry = {
            code: "FR",
            name: "France"
        };
        keyClick(Qt.Key_Escape);
        compare(root.calls.indexOf("clearCountry") >= 0, true, JSON.stringify(root.calls));

        root.currentCountry = null;
        root.expanded = true;
        keyClick(Qt.Key_Escape);
        compare(root.expanded, false);

        field.forceActiveFocus();
        field.text = "abc";
        const clearCountryCallsBefore = root.calls.filter(call => call === "clearCountry").length;
        keyClick(Qt.Key_Escape);
        compare(field.text, "");
        compare(root.calls.filter(call => call === "clearCountry").length, clearCountryCallsBefore, JSON.stringify(root.calls));
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

    function test_world_tab_leaves_the_country_and_the_search() {
        const list = findChild(loader.item, "stationList");
        verify(list !== null, "stationList not found");
        const searchBar = findChild(loader.item, "searchBar");
        verify(searchBar !== null, "searchBar not found");
        root.currentCountry = {
            code: "FR",
            name: "France"
        };
        root.searchText = "jazz";
        searchBar.text = "jazz";
        root.calls = [];

        list.tabSelected(0);
        compare(root.calls.indexOf("clearCountry") >= 0, true, JSON.stringify(root.calls));
        compare(root.calls.indexOf("clearSearch") >= 0, true, JSON.stringify(root.calls));
        compare(searchBar.text, "");
        compare(root.currentTab, 0);

        root.currentCountry = null;
        root.searchText = "";
    }

    function test_other_tabs_still_drop_the_country() {
        const list = findChild(loader.item, "stationList");
        root.currentCountry = {
            code: "FR",
            name: "France"
        };
        list.tabSelected(1);
        compare(root.currentCountry, null);
        compare(root.currentTab, 1);
        root.currentTab = 0;
    }

    function test_retry_button_appears_offline_and_reaches_the_browser() {
        const button = findChild(loader.item, "retryButton");
        verify(button !== null, "retryButton not found");
        compare(button.visible, false);
        radioBrowser.lastError = "offline";
        compare(button.visible, true);
        button.clicked();
        compare(radioBrowser.calls.indexOf("refresh") >= 0, true, JSON.stringify(radioBrowser.calls));
        radioBrowser.lastError = "";
    }
}
