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

    function i18np(singular, plural, count, b) {
        return String(count === 1 ? singular : plural).replace("%1", count).replace("%2", b);
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
        property var listFilters: ({
                sort: "popularity",
                codec: "",
                minBitrate: 0
            })
        readonly property var shownStations: root.listStations
        property bool filtersActive: false
        property string notice: ""
        property string listSource: "world"
        property int currentTab: 0
        property var currentCountry: null
        property string searchText: ""
        property bool loadingCountry: false
        property var favorites: []
        property bool approximateLocations: false
        property bool showDayNight: true
        property bool expanded: true
        property bool isOnDesktop: false
        property bool pinned: false
        property var missingModules: []
        property string distroFamily: ""
        property string installCommand: ""
        property var calls: []

        function setPinned(value) {
            root.pinned = value;
            root.calls.push("pinned:" + value);
        }

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

        function openConfiguration() {
            root.calls.push("configure");
        }

        function openStationEditor(station) {
            root.calls.push("edit:" + station.uuid);
        }

        function setListFilter(key, value) {
            root.calls.push("filter:" + key + "=" + value);
        }

        function voteFor(station) {
            root.calls.push("vote:" + station.uuid);
        }

        function resetListFilters() {
            root.calls.push("resetFilters");
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

    // A missing QML module shows a banner with the packages to install,
    // instead of the widget failing to load.
    function test_missing_modules_banner() {
        const banner = findChild(loader.item, "requirementsBanner");
        compare(banner.visible, false);
        root.missingModules = [
            {
                name: "QtQuick.Dialogs",
                required: true,
                deb: "qml6-module-qtquick-dialogs",
                arch: "qt6-declarative",
                fedora: "qt6-qtdeclarative"
            }
        ];
        compare(banner.visible, true);
        verify(banner.text.indexOf("QtQuick.Dialogs") >= 0, banner.text);
        verify(banner.text.indexOf("qml6-module-qtquick-dialogs") >= 0, banner.text);
        // unknown distribution: the three commands
        verify(banner.text.indexOf("pacman") >= 0, banner.text);
        // known one: a single command, and the copy action puts it on the clipboard
        root.distroFamily = "deb";
        root.installCommand = "sudo apt install qml6-module-qtquick-dialogs";
        verify(banner.text.indexOf("pacman") < 0, banner.text);
        verify(banner.text.indexOf("sudo apt install qml6-module-qtquick-dialogs") >= 0, banner.text);
        compare(banner.actions.length, 1);
        banner.actions[0].trigger();
        compare(findChild(loader.item, "copyHelper").text, "sudo apt install qml6-module-qtquick-dialogs");
        root.distroFamily = "";
        root.installCommand = "";
        root.missingModules = [];
        compare(banner.visible, false);
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

    function test_locating_the_current_station_frames_it_on_the_globe() {
        const playerBar = findChild(loader.item, "playerBar");
        const globe = findChild(loader.item, "globe");
        globe.globeScale = 1;
        player.station = {
            uuid: "far",
            name: "Far",
            latitude: -33.9,
            longitude: 151.2
        };
        playerBar.locateRequested();
        fuzzyCompare(globe.centreLatitude, -33.9, 0.01);
        fuzzyCompare(globe.centreLongitude, 151.2, 0.01);
        verify(globe.globeScale >= 8, "zooms in to city level, got " + globe.globeScale);
        // A playing station missing from the world list still shows up.
        verify(globe.stations.some(s => s.uuid === "far"), "current station added to the globe");
        globe.globeScale = 12;
        playerBar.locateRequested();
        compare(globe.globeScale, 12, "an existing closer zoom is kept");
        player.station = null;
    }

    function loadCountries() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../../contents/data/countries.json"), false);
        xhr.send();
        return JSON.parse(xhr.responseText).features;
    }

    // No coordinates: the globe centres on the station's country instead,
    // both when it starts playing and on a locate request.
    function test_station_without_coordinates_centres_its_country() {
        const playerBar = findChild(loader.item, "playerBar");
        const globe = findChild(loader.item, "globe");
        root.countries = loadCountries();
        globe.globeScale = 1;
        globe.centreLatitude = 0;
        globe.centreLongitude = 0;
        const somewhereInJapan = {
            uuid: "jp",
            name: "Somewhere in Japan",
            countryCode: "JP",
            latitude: null,
            longitude: null
        };
        player.playingStarted(somewhereInJapan);
        verify(globe.centreLatitude > 30 && globe.centreLatitude < 45, "latitude " + globe.centreLatitude);
        verify(globe.centreLongitude > 125 && globe.centreLongitude < 150, "longitude " + globe.centreLongitude);
        globe.centreLatitude = 0;
        globe.centreLongitude = 0;
        player.station = somewhereInJapan;
        playerBar.locateRequested();
        verify(globe.centreLongitude > 125 && globe.centreLongitude < 150, "longitude " + globe.centreLongitude);
        compare(globe.globeScale, 1, "a country is not a city: no zoom");
        player.station = null;
        root.countries = [];
    }

    function test_located_favourites_are_on_the_globe() {
        const globe = findChild(loader.item, "globe");
        root.favorites = [
            {
                uuid: "local-1",
                name: "Mine",
                latitude: 2,
                longitude: 2
            },
            {
                uuid: "nowhere",
                name: "No coords",
                latitude: null,
                longitude: null
            }
        ];
        verify(globe.stations.some(s => s.uuid === "local-1"), "a located favourite gets a dot");
        verify(!globe.stations.some(s => s.uuid === "nowhere"), "no coordinates, no dot");
        root.favorites = [];
        verify(!globe.stations.some(s => s.uuid === "local-1"));
    }

    // During a search, or in a country, the globe shows the list (plus the
    // playing station), not the world and not the favourites; the World tab
    // brings the world back.
    function test_search_filters_the_globe() {
        const globe = findChild(loader.item, "globe");
        root.favorites = [
            {
                uuid: "fav",
                name: "Mine",
                latitude: 2,
                longitude: 2
            }
        ];
        player.station = {
            uuid: "playing",
            name: "On air",
            latitude: 5,
            longitude: 5
        };
        root.listStations = [
            {
                uuid: "hit",
                name: "Jazz FM",
                latitude: 10,
                longitude: 10
            }
        ];
        root.listSource = "search";
        compare(globe.stations.map(s => s.uuid).sort().join(","), "hit,playing");
        compare(loader.item.statusLine, "1 match on the globe");
        // Searching inside a country: the status says where.
        root.currentCountry = {
            code: "FR",
            name: "France"
        };
        compare(loader.item.statusLine, "1 match in France");
        root.currentCountry = null;
        // A country is a filter too: its stations only, favourites aside.
        root.currentCountry = {
            code: "FR",
            name: "France"
        };
        root.listStations = [
            {
                uuid: "fr1",
                name: "Radio Nova",
                latitude: 48,
                longitude: 2
            }
        ];
        root.listSource = "country";
        compare(globe.stations.map(s => s.uuid).sort().join(","), "fr1,playing");
        compare(loader.item.statusLine, "France · click another country to browse");
        root.currentCountry = null;
        root.listStations = root.worldStations;
        root.listSource = "world";
        verify(globe.stations.some(s => s.uuid === "a"), "the world is back");
        verify(globe.stations.some(s => s.uuid === "fav"), "and so are the favourites");
        compare(loader.item.statusLine, "2 signals");
        root.favorites = [];
        player.station = null;
    }

    function test_list_shows_the_country_loading_state() {
        const list = findChild(loader.item, "stationList");
        compare(list.loading, false);
        root.loadingCountry = true;
        compare(list.loading, true);
        root.loadingCountry = false;
    }

    // The station menu: opened by the list, its entries reach root, the
    // clipboard, or the properties panel.
    function test_station_menu_and_properties() {
        const list = findChild(loader.item, "stationList");
        const menu = findChild(loader.item, "stationMenu");
        verify(menu !== null, "stationMenu not found");
        const station = {
            uuid: "prop",
            name: "Radio Props",
            url: "https://s/props.mp3",
            homepage: "https://props.example",
            countryCode: "FR",
            country: "France",
            state: "Lyon",
            language: "french",
            tags: "jazz,soul",
            codec: "AAC",
            bitrate: 96,
            hls: false,
            clicks: 42,
            votes: 7,
            latitude: 45.75,
            longitude: 4.85
        };
        list.menuRequested(station);
        tryCompare(menu, "visible", true);
        compare(menu.station.uuid, "prop");
        function item(name) {
            for (let i = 0; i < menu.count; i++)
                if (menu.itemAt(i).objectName === name)
                    return menu.itemAt(i);
            return null;
        }
        item("menuCopyUrl").triggered();
        compare(findChild(loader.item, "copyHelper").text, "https://s/props.mp3");
        item("menuPlay").triggered();
        compare(root.calls.indexOf("play:prop") >= 0, true, JSON.stringify(root.calls));
        item("menuFavorite").triggered();
        compare(root.calls.indexOf("fav:prop") >= 0, true, JSON.stringify(root.calls));
        item("menuVote").triggered();
        compare(root.calls.indexOf("vote:prop") >= 0, true, JSON.stringify(root.calls));
        item("menuProperties").triggered();
        const properties = findChild(loader.item, "stationProperties");
        verify(properties !== null, "stationProperties not found");
        tryCompare(properties, "visible", true);
        const text = findChild(properties, "propertiesText").text;
        for (const expected of ["Radio Props", "https://s/props.mp3", "AAC", "96 kbps", "France", "Lyon", "french", "jazz,soul", "https://props.example", "42", "Votes on Radio Browser", "45.75", "prop"])
            verify(text.indexOf(expected) >= 0, "properties miss " + expected + ": " + text);
        properties.close();
        tryCompare(properties, "visible", false);
    }

    function test_edit_button_sends_the_current_station_to_root() {
        const playerBar = findChild(loader.item, "playerBar");
        player.station = {
            uuid: "cur",
            name: "Current"
        };
        playerBar.editRequested();
        compare(root.calls.indexOf("edit:cur") >= 0, true, JSON.stringify(root.calls));
        player.station = null;
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
        // The clear button does the same, and only that: no search, and not
        // the selected row either.
        const field = findChild(searchBar, "searchField");
        const clear = field.rightActions[0];
        compare(clear.visible, false);
        searchBar.text = "rock";
        compare(clear.visible, true);
        findChild(loader.item, "stationList").selectedIndex = 0;
        const before = root.calls.length;
        clear.trigger();
        compare(searchBar.text, "");
        compare(root.calls.slice(before), ["clearSearch"]);
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

    function test_modifier_combinations_are_not_shortcuts() {
        loader.item.forceActiveFocus();
        keyClick(Qt.Key_M, Qt.ControlModifier);
        compare(player.calls.indexOf("toggleMute"), -1, JSON.stringify(player.calls));
        keyClick(Qt.Key_R, Qt.AltModifier);
        compare(root.calls.indexOf("random"), -1, JSON.stringify(root.calls));
        // The same keys alone still work.
        keyClick(Qt.Key_M);
        compare(player.calls.indexOf("toggleMute") >= 0, true, JSON.stringify(player.calls));
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

    function test_filter_menu_reaches_root_and_the_status_line_says_so() {
        const searchBar = findChild(loader.item, "searchBar");
        const menu = findChild(searchBar, "filterMenu");
        verify(menu !== null, "filterMenu not found");
        function item(name) {
            return findChild(searchBar, name);
        }
        verify(item("sort-popularity").checked, "default sort is popularity");
        verify(item("codec-any").checked);
        verify(item("minBitrate-any").checked);
        item("sort-votes").triggered();
        item("codec-aac").triggered();
        item("minBitrate-128").triggered();
        for (const expected of ["filter:sort=votes", "filter:codec=aac", "filter:minBitrate=128"])
            compare(root.calls.indexOf(expected) >= 0, true, JSON.stringify(root.calls));
        // Codecs add up: a second one joins the set, "Any" empties it.
        root.listFilters = ({
                sort: "popularity",
                codec: "aac",
                minBitrate: 0
            });
        verify(item("codec-aac").checked);
        verify(!item("codec-any").checked);
        item("codec-mp3").triggered();
        compare(root.calls[root.calls.length - 1], "filter:codec=mp3,aac");
        root.listFilters = ({
                sort: "popularity",
                codec: "mp3,aac",
                minBitrate: 0
            });
        verify(item("codec-mp3").checked && item("codec-aac").checked);
        item("codec-aac").triggered();
        compare(root.calls[root.calls.length - 1], "filter:codec=mp3");
        item("codec-any").triggered();
        compare(root.calls[root.calls.length - 1], "filter:codec=");
        // The owner applied them: the menu and the button follow.
        root.listFilters = ({
                sort: "votes",
                codec: "aac",
                minBitrate: 128
            });
        root.filtersActive = true;
        root.listStations = [root.worldStations[0]];
        verify(item("sort-votes").checked);
        verify(!item("sort-popularity").checked);
        verify(item("codec-aac").checked);
        verify(item("minBitrate-128").checked);
        compare(findChild(searchBar, "filterButton").highlighted, true);
        compare(loader.item.statusLine, "2 signals · 1 station after filters");
        // The filtered list is what the globe maps.
        compare(loader.item.globeStations.length, 1);
        root.filtersActive = false;
        root.listStations = root.worldStations;
        root.listFilters = ({
                sort: "popularity",
                codec: "",
                minBitrate: 0
            });
        compare(loader.item.statusLine, "2 signals");
    }

    // The button toggles the menu, the widget's popup closing closes it and
    // it does not come back with the popup, Reset asks for the defaults.
    function test_filter_menu_opens_closes_and_stays_closed() {
        const searchBar = findChild(loader.item, "searchBar");
        const button = findChild(searchBar, "filterButton");
        const menu = findChild(searchBar, "filterMenu");
        root.expanded = true;
        mouseClick(button);
        tryCompare(menu, "visible", true);
        mouseClick(button);
        tryCompare(menu, "visible", false);
        mouseClick(button);
        tryCompare(menu, "visible", true);
        root.expanded = false;
        tryCompare(menu, "visible", false);
        root.expanded = true;
        wait(50);
        compare(menu.visible, false);
        // Escape closes it too.
        mouseClick(button);
        tryCompare(menu, "visible", true);
        keyClick(Qt.Key_Escape);
        tryCompare(menu, "visible", false);
        const reset = findChild(searchBar, "filterReset");
        compare(reset.enabled, false, "nothing to reset by default");
        root.filtersActive = true;
        compare(reset.enabled, true);
        reset.triggered();
        compare(root.calls.indexOf("resetFilters") >= 0, true, JSON.stringify(root.calls));
        root.filtersActive = false;
    }

    // Picking an entry leaves the menu open; the pointer leaving it for a
    // moment closes it.
    function test_filter_menu_stays_open_on_a_choice_and_closes_when_the_pointer_leaves() {
        const searchBar = findChild(loader.item, "searchBar");
        const button = findChild(searchBar, "filterButton");
        const menu = findChild(searchBar, "filterMenu");
        menu.leaveDelayMs = 60;
        root.expanded = true;
        mouseClick(button);
        tryCompare(menu, "visible", true);
        const entry = findChild(searchBar, "sort-name");
        mouseMove(entry, 5, 5);
        wait(20);
        mouseClick(entry, 5, 5);
        compare(root.calls.indexOf("filter:sort=name") >= 0, true, JSON.stringify(root.calls));
        wait(150);
        compare(menu.visible, true, "still open after a choice");
        // Pointer far away: closed after the grace period.
        mouseMove(loader.item, 5, loader.item.height - 5);
        tryCompare(menu, "visible", false);
        menu.leaveDelayMs = 400;
    }

    function test_station_menu_closes_with_the_widget() {
        const list = findChild(loader.item, "stationList");
        const menu = findChild(loader.item, "stationMenu");
        root.expanded = true;
        list.menuRequested({
            uuid: "m",
            name: "M",
            url: "https://s/m.mp3"
        });
        tryCompare(menu, "visible", true);
        root.expanded = false;
        tryCompare(menu, "visible", false);
        root.expanded = true;
        wait(50);
        compare(menu.visible, false);
    }

    function test_notice_takes_over_the_status_line() {
        root.notice = "Vote counted for Radio A";
        compare(loader.item.statusLine, "Vote counted for Radio A");
        root.notice = "";
        compare(loader.item.statusLine, "2 signals");
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

    function test_pin_button_routes_through_root() {
        const button = findChild(loader.item, "pinButton");
        verify(button !== null, "pinButton not found");
        compare(button.visible, true);
        compare(button.checked, false);
        mouseClick(button);
        compare(root.calls.indexOf("pinned:true") >= 0, true, JSON.stringify(root.calls));
        compare(root.pinned, true);
        // On the desktop there is no popup to keep open.
        root.isOnDesktop = true;
        compare(button.visible, false);
        root.isOnDesktop = false;
        root.pinned = false;
    }

    function test_add_station_button_opens_the_configuration() {
        const button = findChild(loader.item, "addStationButton");
        verify(button !== null, "addStationButton not found");
        mouseClick(button);
        compare(root.calls.indexOf("configure") >= 0, true, JSON.stringify(root.calls));
    }

    function test_zoom_buttons_drive_the_globe() {
        const globe = findChild(loader.item, "globe");
        const zoomIn = findChild(loader.item, "zoomInButton");
        const zoomOut = findChild(loader.item, "zoomOutButton");
        verify(zoomIn !== null && zoomOut !== null, "zoom buttons not found");
        globe.globeScale = 1;
        mouseClick(zoomIn);
        tryCompare(globe, "globeScale", 2);
        mouseClick(zoomOut);
        tryCompare(globe, "globeScale", 1);
        // Disabled at the limits.
        globe.globeScale = globe.maximumScale;
        compare(zoomIn.enabled, false);
        compare(zoomOut.enabled, true);
        globe.globeScale = 1;
    }

    function test_day_night_shading_follows_the_setting() {
        const globe = findChild(loader.item, "globe");
        compare(globe.showDayNight, true);
        root.showDayNight = false;
        compare(globe.showDayNight, false);
        root.showDayNight = true;
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
