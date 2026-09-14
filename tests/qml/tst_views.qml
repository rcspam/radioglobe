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

    Ui.StationList {
        id: list
        width: 300
        height: 300
        favoriteCheck: uuid => uuid === "b"
    }

    SignalSpy {
        id: activations
        target: list
        signalName: "activated"
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

    function test_components_compile() {
        // CompactRepresentation.qml lands in Task 10.
        for (const file of ["SearchBar.qml", "FullRepresentation.qml"]) {
            const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/" + file));
            verify(component.status === Component.Ready || component.status === Component.Error, file);
            if (component.status === Component.Error)
                verify(component.errorString().indexOf("is not a type") < 0, file + ": " + component.errorString());
        }
    }
}
