import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "KeyMap.js" as KeyMap

// Globe on the left, list + player on the right; stacks vertically when narrow.
// Reads shared state from `root` (main.qml's PlasmoidItem) and `player`.
Item {
    id: full

    focus: true
    activeFocusOnTab: true

    Layout.preferredWidth: Kirigami.Units.gridUnit * 45
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30
    Layout.minimumWidth: Kirigami.Units.gridUnit * 20
    Layout.minimumHeight: Kirigami.Units.gridUnit * 18

    // `player` is an id from main.qml's context. Inside a PlayerBar block the
    // component's own `player` property shadows that id, so the bindings there
    // reach the real player through this alias.
    readonly property var mediaPlayer: player

    // Pure key -> action mapping (KeyMap.js) driven by these callbacks, so the
    // dispatch logic can be unit-tested without instantiating the component.
    readonly property var keyTargets: ({
            focusSearch: () => searchBar.focusInput(),
            moveSelection: delta => stationList.moveSelection(delta),
            activateSelected: () => stationList.activateSelected(),
            togglePause: () => full.mediaPlayer.togglePause(),
            random: () => root.playRandom(),
            favorite: () => {
                const index = stationList.selectedIndex;
                const target = index >= 0 ? root.listStations[index] : full.mediaPlayer.station;
                if (target)
                    root.toggleFavorite(target);
            },
            volumeStep: delta => full.mediaPlayer.setVolume(full.mediaPlayer.volume + delta),
            mute: () => full.mediaPlayer.toggleMute(),
            escape: () => {
                if (searchBar.text !== "") {
                    searchBar.text = "";
                } else if (root.currentCountry) {
                    root.clearCountry();
                } else {
                    root.expanded = false;
                }
            }
        })

    Keys.onPressed: event => {
        if (searchBar.text !== "" && event.key !== Qt.Key_Escape && event.key !== Qt.Key_Down && event.key !== Qt.Key_Up && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
            return;
        event.accepted = KeyMap.handle(full.keyTargets, event.key, event.text);
    }

    readonly property bool narrow: width < Kirigami.Units.gridUnit * 32
    readonly property string statusLine: {
        if (radioBrowser.lastError === "offline")
            return i18n("Radio Browser unreachable, showing cached data");
        if (root.currentCountry)
            return i18n("%1 · click another country to browse", root.currentCountry.name);
        return i18np("%1 signal", "%1 signals", root.worldStations.length);
    }

    function focusSearch() {
        searchBar.focusInput();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        SearchBar {
            id: searchBar
            objectName: "searchBar"
            Layout.fillWidth: true
            onSearchRequested: text => root.runSearch(text)
            onCleared: root.clearSearch()
            onRandomRequested: root.playRandom()
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: full.narrow ? 1 : 2
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: full.narrow ? -1 : full.width * 0.6
                spacing: 0

                Globe {
                    id: globe
                    objectName: "globe"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    countries: root.countries
                    stations: root.worldStations
                    selectedStation: player.station
                    activeCountryCode: root.currentCountry ? root.currentCountry.code : (player.station ? player.station.countryCode : "")
                    backgroundColor: Kirigami.Theme.backgroundColor
                    sphereColor: Qt.darker(Kirigami.Theme.backgroundColor, 1.25)
                    landColor: Kirigami.Theme.alternateBackgroundColor
                    gridColor: Kirigami.Theme.disabledTextColor
                    outlineColor: Kirigami.Theme.textColor
                    signalColor: Kirigami.Theme.textColor
                    accentColor: Kirigami.Theme.highlightColor
                    textColor: Kirigami.Theme.textColor
                    fontFamily: Kirigami.Theme.defaultFont.family
                    onStationActivated: station => root.playFrom(root.listStations, station)
                    onCountryActivated: (code, name) => root.openCountry(code, name)
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: full.statusLine
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    opacity: 0.7
                    font: Kirigami.Theme.smallFont
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: full.narrow ? -1 : full.width * 0.4
                spacing: Kirigami.Units.smallSpacing

                StationList {
                    id: stationList
                    objectName: "stationList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    stations: root.listStations
                    currentUuid: player.station ? player.station.uuid : ""
                    favoriteCheck: uuid => root.isFavorite(uuid)
                    currentTab: root.currentTab
                    onTabSelected: index => {
                        root.currentCountry = null;
                        root.currentTab = index;
                    }
                    onActivated: station => root.playFrom(root.listStations, station)
                    onFavoriteToggled: station => root.toggleFavorite(station)
                }

                PlayerBar {
                    objectName: "playerBar"
                    Layout.fillWidth: true
                    player: full.mediaPlayer
                    favorite: full.mediaPlayer.station ? root.isFavorite(full.mediaPlayer.station.uuid) : false
                    onPlayPauseRequested: full.mediaPlayer.togglePause()
                    onStopRequested: full.mediaPlayer.stop()
                    onQuitRequested: full.mediaPlayer.quit()
                    onNextRequested: root.next()
                    onPreviousRequested: root.previous()
                    onRetryRequested: full.mediaPlayer.retry()
                    onVolumeRequested: value => full.mediaPlayer.setVolume(value)
                    onMuteRequested: full.mediaPlayer.toggleMute()
                    onFavoriteRequested: if (full.mediaPlayer.station)
                        root.toggleFavorite(full.mediaPlayer.station)
                }
            }
        }
    }

    Connections {
        target: player
        function onPlayingStarted(station) {
            if (station && station.latitude !== null && station.longitude !== null)
                globe.focusCoordinate(station.latitude, station.longitude);
        }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded)
                full.forceActiveFocus();
        }
    }
}
