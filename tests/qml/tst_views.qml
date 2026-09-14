import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Views"
    when: windowShown
    width: 900
    height: 600
    visible: true

    function i18n(text, a, b) {
        return text.replace("%1", a).replace("%2", b);
    }

    property var fakePlayer: ({
            state: "idle",
            station: null,
            track: "",
            volume: 0.5,
            muted: false,
            errorKind: ""
        })

    Ui.PlayerBar {
        id: bar
        width: 400
        player: fakePlayer
    }

    function test_double_click_on_the_station_asks_to_locate_it() {
        let asked = 0;
        bar.locateRequested.connect(() => asked++);
        const text = findChild(bar, "stationText");
        verify(text !== null, "stationText not found");
        mouseDoubleClickSequence(text, 10, 10);
        compare(asked, 0, "no station, nothing to locate");
        // Outside the double-click interval of the first sequence.
        wait(600);
        bar.player = ({
                state: "playing",
                station: {
                    uuid: "a",
                    name: "FIP",
                    latitude: 48.85,
                    longitude: 2.35
                },
                track: "",
                errorKind: ""
            });
        mouseDoubleClickSequence(text, 10, 10);
        compare(asked, 1);
        bar.player = fakePlayer;
    }

    function test_edit_button_needs_a_station() {
        let asked = 0;
        bar.editRequested.connect(() => asked++);
        const button = findChild(bar, "editButton");
        verify(button !== null, "editButton not found");
        compare(button.enabled, false);
        bar.player = ({
                state: "playing",
                station: {
                    uuid: "a",
                    name: "FIP"
                },
                track: "",
                errorKind: ""
            });
        compare(button.enabled, true);
        mouseClick(button);
        compare(asked, 1);
        bar.player = fakePlayer;
    }

    function test_player_bar_idle_and_playing_texts() {
        compare(bar.primaryText, "No station selected");
        fakePlayer = ({
                state: "playing",
                station: {
                    uuid: "a",
                    name: "FIP",
                    url: "https://s/a.mp3"
                },
                track: "",
                volume: 0.5,
                muted: false,
                errorKind: ""
            });
        bar.player = fakePlayer;
        compare(bar.primaryText, "FIP");
        compare(bar.secondaryText, "Live");
        fakePlayer = ({
                state: "playing",
                station: {
                    uuid: "a",
                    name: "FIP",
                    url: "https://s/a.mp3"
                },
                track: "Song - Artist",
                volume: 0.5,
                muted: false,
                errorKind: ""
            });
        bar.player = fakePlayer;
        compare(bar.secondaryText, "Song - Artist");
        compare(bar.errorText, "");
    }

    function test_player_bar_error_messages() {
        bar.player = ({
                state: "error",
                station: {
                    uuid: "a",
                    name: "FIP",
                    url: "u"
                },
                track: "",
                volume: 0.5,
                muted: false,
                errorKind: "stream"
            });
        verify(bar.errorText.indexOf("could not be played") >= 0, bar.errorText);
        bar.player = ({
                state: "error",
                station: null,
                track: "",
                volume: 0.5,
                muted: false,
                errorKind: "mpv-missing"
            });
        verify(bar.errorText.indexOf("mpv") >= 0);
        bar.player = ({
                state: "error",
                station: null,
                track: "",
                volume: 0.5,
                muted: false,
                errorKind: "mpris-missing"
            });
        verify(bar.errorText.indexOf("mpv-mpris") >= 0);
        bar.player = ({
                state: "error",
                station: null,
                track: "",
                volume: 0.5,
                muted: false,
                errorKind: "mpris-module-missing"
            });
        verify(bar.errorText.indexOf("org.kde.plasma.private.mpris") >= 0, bar.errorText);
    }

    // The percent label used to be three different widths, and the spacer in
    // the transport row absorbed the difference: the slider moved sideways
    // under the cursor while it was being dragged.
    function test_volume_label_keeps_one_width() {
        const label = findChild(bar, "volumeLabel");
        verify(label !== null, "volumeLabel not found");
        bar.player = ({
                state: "playing",
                station: null,
                track: "",
                volume: 0.05,
                muted: false,
                errorKind: ""
            });
        compare(label.text, "5%");
        // Layout width is settled in a polish pass, not on assignment.
        wait(50);
        const narrow = label.width;
        bar.player = ({
                state: "playing",
                station: null,
                track: "",
                volume: 1,
                muted: false,
                errorKind: ""
            });
        compare(label.text, "100%");
        wait(50);
        compare(label.width, narrow);
        verify(narrow > 0, "label has no width");
    }

    // Favourites held as data, like main.qml does: the delegate binding reads
    // them through favoriteCheck, so reassigning the set has to refresh it.
    property var favSet: ({
            b: true
        })

    // Below the player bar, so the two never overlap for mouse tests.
    Ui.StationList {
        id: list
        y: 200
        width: 300
        height: 300
        favoriteCheck: uuid => favSet[uuid] === true
    }

    SignalSpy {
        id: activations
        target: list
        signalName: "activated"
    }

    SignalSpy {
        id: favorites
        target: list
        signalName: "favoriteToggled"
    }

    SignalSpy {
        id: tabs
        target: list
        signalName: "tabSelected"
    }

    function test_station_list_selection_and_activation() {
        activations.clear();
        list.stations = [
            {
                uuid: "a",
                name: "A",
                countryCode: "FR",
                codec: "MP3",
                bitrate: 128
            },
            {
                uuid: "b",
                name: "B",
                countryCode: "DE",
                codec: "AAC",
                bitrate: 64
            }
        ];
        list.selectedIndex = -1;
        list.moveSelection(1);
        compare(list.selectedIndex, 0);
        list.moveSelection(1);
        compare(list.selectedIndex, 1);
        list.moveSelection(1);
        compare(list.selectedIndex, 1);
        list.activateSelected();
        compare(activations.count, 1);
        compare(activations.signalArguments[0][0].uuid, "b");
    }

    // The delegate is a plain anchored Item, not an ItemDelegate: highlight,
    // activation and the favourite star are all wired by hand now.
    function test_station_list_row_highlight_activation_and_star() {
        activations.clear();
        favorites.clear();
        list.stations = [
            {
                uuid: "a",
                name: "A",
                countryCode: "FR",
                codec: "MP3",
                bitrate: 128
            },
            {
                uuid: "b",
                name: "B",
                countryCode: "DE",
                codec: "AAC",
                bitrate: 64,
                meta: "precomputed"
            }
        ];
        list.selectedIndex = -1;
        const view = findChild(list, "stationView");
        verify(view !== null, "stationView not found");
        wait(50);
        const first = view.itemAtIndex(0);
        verify(first !== null, "row 0 not created");
        compare(first.highlighted, false);
        list.selectedIndex = 0;
        compare(first.highlighted, true);

        // No meta field on the station: the delegate falls back to computing it.
        compare(findChild(first, "stationMeta").text, "FR · MP3 · 128 kbps");
        const second = view.itemAtIndex(1);
        verify(second !== null, "row 1 not created");
        compare(findChild(second, "stationMeta").text, "precomputed");
        // The playing station is the other highlight source.
        list.currentUuid = "b";
        compare(second.highlighted, true);
        list.currentUuid = "";

        mouseClick(first, 10, first.height / 2);
        compare(activations.count, 1);
        compare(activations.signalArguments[0][0].uuid, "a");

        const star = findChild(first, "favoriteButton");
        verify(star !== null, "favoriteButton not found");
        mouseClick(star);
        compare(favorites.count, 1);
        compare(favorites.signalArguments[0][0].uuid, "a");
    }

    // A favourite added elsewhere (the player bar, the F key) must repaint the
    // star of a row that is already on screen.
    function test_favorite_star_follows_the_favorites() {
        favSet = ({});
        list.stations = [
            {
                uuid: "a",
                name: "A",
                countryCode: "FR",
                codec: "MP3",
                bitrate: 128
            }
        ];
        const view = findChild(list, "stationView");
        verify(view !== null, "stationView not found");
        wait(50);
        const first = view.itemAtIndex(0);
        verify(first !== null, "row 0 not created");
        const icon = findChild(first, "favoriteIcon");
        verify(icon !== null, "favoriteIcon not found");
        compare(first.favorite, false);
        compare(String(icon.source), "non-starred-symbolic");

        favSet = ({
                a: true
            });
        compare(first.favorite, true);
        compare(String(icon.source), "starred-symbolic");

        favSet = ({});
        compare(first.favorite, false);
        compare(String(icon.source), "non-starred-symbolic");
        favSet = ({
                b: true
            });
    }

    // Leaving a country or a search means clicking World again, which changes
    // no tab index: without its own onClicked the bar would say nothing.
    function test_world_tab_emits_even_when_already_current() {
        list.currentTab = 0;
        tabs.clear();
        const worldTab = findChild(list, "worldTab");
        verify(worldTab !== null, "worldTab not found");
        mouseClick(worldTab);
        compare(tabs.count, 1);
        compare(tabs.signalArguments[0][0], 0);
    }

    function test_components_compile() {
        for (const file of ["SearchBar.qml", "FullRepresentation.qml", "CompactRepresentation.qml"]) {
            const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + file));
            verify(component.status === Component.Ready || component.status === Component.Error, file);
            if (component.status === Component.Error)
                verify(component.errorString().indexOf("is not a type") < 0, file + ": " + component.errorString());
        }
    }
}
