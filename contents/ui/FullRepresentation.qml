import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "KeyMap.js" as KeyMap
import "RadioModel.js" as RadioModel

// Globe on the left, list + player on the right; stacks vertically when narrow.
// Reads shared state from `root` (main.qml's PlasmoidItem) and `player`.
Item {
    id: full

    focus: true
    activeFocusOnTab: true

    Layout.preferredWidth: Kirigami.Units.gridUnit * 45
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30
    Layout.minimumWidth: Kirigami.Units.gridUnit * 22
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
                const target = index >= 0 ? root.shownStations[index] : full.mediaPlayer.station;
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
        // Ctrl / Alt / Meta combinations belong to the shell, to the text field
        // (Ctrl+A, Ctrl+V) or to a global shortcut: Ctrl+M is not a mute.
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) {
            event.accepted = false;
            return;
        }
        if (searchBar.inputFocused) {
            // Typing: only list navigation is intercepted; letters go to the field.
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                stationList.moveSelection(event.key === Qt.Key_Down ? 1 : -1);
                event.accepted = true;
                return;
            }
            // SearchBar clears its own text on Escape and only lets the event
            // bubble up here once the field is already empty, meaning it wants
            // us to clear the country / close the popup.
            if (event.key === Qt.Key_Escape) {
                event.accepted = KeyMap.handle(full.keyTargets, event.key, event.text);
                return;
            }
            event.accepted = false;
            return;
        }
        event.accepted = KeyMap.handle(full.keyTargets, event.key, event.text);
    }

    readonly property bool narrow: width < Kirigami.Units.gridUnit * 32
    readonly property string statusLine: {
        if (root.notice)
            return root.notice;
        if (radioBrowser.lastError === "offline")
            return i18n("Radio Browser unreachable, showing cached data");
        const line = full.contextLine;
        return root.filtersActive ? i18np("%2 · %1 station after filters", "%2 · %1 stations after filters", root.shownStations.length, line) : line;
    }
    readonly property string contextLine: {
        if (full.searching && root.currentCountry)
            return i18np("%1 match in %2", "%1 matches in %2", root.shownStations.length, root.currentCountry.name);
        if (root.currentCountry)
            return i18n("%1 · click another country to browse", root.currentCountry.name);
        if (full.searching)
            return i18np("%1 match on the globe", "%1 matches on the globe", root.shownStations.length);
        return i18np("%1 signal", "%1 signals", root.worldStations.length);
    }

    function focusSearch() {
        searchBar.focusInput();
    }

    function hasCoordinates(station) {
        return station && station.latitude !== null && station.longitude !== null && station.latitude !== undefined && station.longitude !== undefined;
    }

    // Centres the globe on a station: on its coordinates, or, when Radio
    // Browser has none, on its country (most stations have no location).
    function centreOn(station) {
        if (!station)
            return false;
        if (full.hasCoordinates(station)) {
            globe.focusCoordinate(station.latitude, station.longitude);
            return true;
        }
        if (station.countryCode) {
            globe.focusCountry(String(station.countryCode).toUpperCase());
            return false;
        }
        return false;
    }

    // Frames the playing station on the globe, zooming in to city level
    // unless the globe is already closer; a country stays at the current
    // zoom, it is not a city.
    function locateCurrentStation() {
        if (full.centreOn(full.mediaPlayer.station))
            globe.globeScale = Math.max(globe.globeScale, 8);
    }

    // During a search, or in a country, the globe is a map of the list: the
    // results only, no favourites, so the filter is one. Otherwise the world
    // list is capped, and stations added by hand or favourites outside the
    // cap are not in it: located favourites are appended when missing, so
    // they get a dot. The playing station is always there, so locating it
    // always lands on a dot.
    readonly property bool searching: root.listSource === "search"
    readonly property bool filtered: full.searching || root.listSource === "country" || root.filtersActive
    readonly property var globeStations: RadioModel.withLocalStations(full.filtered ? root.shownStations : root.worldStations, full.filtered ? [] : root.favorites, full.mediaPlayer.station, root.approximateLocations)

    // The packages to install for the modules main.qml found missing: the
    // command for this distribution when known, else one line per family.
    function requirementsText() {
        const missing = root.missingModules || [];
        if (missing.length === 0)
            return "";
        const names = missing.map(m => m.name).join(", ");
        if (root.installCommand)
            return i18n("Missing QML modules: %1. Install them and restart Plasma:\n%2", names, root.installCommand);
        const pkgs = distro => missing.map(m => m[distro]).join(" ");
        return i18n("Missing QML modules: %1. Install them and restart Plasma:\nDebian / Ubuntu: sudo apt install %2\nArch Linux: sudo pacman -S %3\nFedora: sudo dnf install %4", names, pkgs("deb"), pkgs("arch"), pkgs("fedora"));
    }

    // Everything to paste in a terminal: the detected command, or the three.
    function requirementsCommand() {
        const missing = root.missingModules || [];
        if (root.installCommand)
            return root.installCommand;
        const pkgs = distro => missing.map(m => m[distro]).join(" ");
        return "sudo apt install " + pkgs("deb") + "\nsudo pacman -S " + pkgs("arch") + "\nsudo dnf install " + pkgs("fedora");
    }

    // QML has no clipboard API of its own: a hidden TextEdit copies for us.
    TextEdit {
        id: copyHelper
        objectName: "copyHelper"
        visible: false
        function copyText(value) {
            text = value;
            selectAll();
            copy();
        }
    }

    // One menu and one properties panel for every station of the popup.
    // Menus are popups inside the widget's window: hidden with it, they
    // would still be open when it shows again. Close them with it.
    Connections {
        target: root
        function onExpandedChanged() {
            if (!root.expanded)
                full.closeMenus();
        }
    }
    function closeMenus() {
        searchBar.closeMenu();
        stationMenu.close();
    }

    StationMenu {
        id: stationMenu
        objectName: "stationMenu"
        onPlayRequested: station => root.playFrom(root.shownStations, station)
        onFavoriteRequested: station => root.toggleFavorite(station)
        onCopyRequested: text => copyHelper.copyText(text)
        onPropertiesRequested: station => stationProperties.open(station)
        onVoteRequested: station => root.voteFor(station)
    }

    StationProperties {
        id: stationProperties
        objectName: "stationProperties"
    }

    function openStationMenu(station) {
        if (station)
            stationMenu.open(station, root.isFavorite(station.uuid));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.InlineMessage {
            id: requirementsBanner
            objectName: "requirementsBanner"
            Layout.fillWidth: true
            type: Kirigami.MessageType.Warning
            visible: (root.missingModules || []).length > 0
            text: full.requirementsText()
            actions: [
                Kirigami.Action {
                    text: i18n("Copy the install command")
                    icon.name: "edit-copy"
                    onTriggered: copyHelper.copyText(full.requirementsCommand())
                }
            ]
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            SearchBar {
                id: searchBar
                objectName: "searchBar"
                Layout.fillWidth: true
                onSearchRequested: text => {
                    if (stationList.selectedIndex >= 0)
                        stationList.activateSelected();
                    else
                        root.runSearch(text);
                }
                onCleared: root.clearSearch()
                onRandomRequested: root.playRandom()
                filters: root.listFilters
                filtersActive: root.filtersActive
                onFilterRequested: (key, value) => root.setListFilter(key, value)
                onFiltersResetRequested: root.resetListFilters()
            }

            // The form lives in the configuration dialog ("Add a station"
            // page): a Plasma config page is the one place with room for a
            // map, and the dialog outlives the popup.
            PlasmaComponents3.ToolButton {
                objectName: "addStationButton"
                icon.name: "list-add"
                onClicked: root.openConfiguration()
                Accessible.name: i18n("Add a station…")
                PlasmaComponents3.ToolTip.text: i18n("Add a station…")
                PlasmaComponents3.ToolTip.visible: hovered
            }

            // Only a popup can be dismissed by a click elsewhere, so the pin
            // has nothing to do when the widget lives on the desktop.
            PlasmaComponents3.ToolButton {
                objectName: "pinButton"
                visible: !root.isOnDesktop
                icon.name: "window-pin"
                checkable: true
                checked: root.pinned
                onToggled: root.setPinned(checked)
                Accessible.name: i18n("Keep open")
                PlasmaComponents3.ToolTip.text: i18n("Keep open")
                PlasmaComponents3.ToolTip.visible: hovered
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: full.narrow ? 1 : 2
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing

            // Side by side, the list column takes 40 % of the width, or its
            // own minimum when that is more (the player bar's controls do
            // not shrink), and the globe gets what is left.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: full.narrow ? 0 : Kirigami.Units.gridUnit * 10
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Globe {
                        id: globe
                        objectName: "globe"
                        anchors.fill: parent
                        countries: root.countries
                        stations: full.globeStations
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
                        showDayNight: root.showDayNight
                        zoomStep: root.zoomStep
                        // Darker than the sphere in both light and dark
                        // themes, so the night side reads as a shadow.
                        nightColor: Qt.darker(Kirigami.Theme.backgroundColor, 3)
                        onStationActivated: station => root.playFrom(root.shownStations, station)
                        onCountryActivated: (code, name) => root.openCountry(code, name)
                        // The sea, or space: out of the country.
                        onEmptyActivated: if (root.currentCountry)
                            root.clearCountry()
                    }

                    // Wheel-less zoom, over the globe's bottom-right corner.
                    ColumnLayout {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: 0

                        PlasmaComponents3.ToolButton {
                            objectName: "zoomInButton"
                            icon.name: "list-add"
                            enabled: globe.canZoomIn
                            focusPolicy: Qt.NoFocus
                            onClicked: globe.zoomIn()
                            Accessible.name: i18n("Zoom in")
                            PlasmaComponents3.ToolTip.text: i18n("Zoom in")
                            PlasmaComponents3.ToolTip.visible: hovered
                        }

                        PlasmaComponents3.ToolButton {
                            objectName: "zoomOutButton"
                            icon.name: "list-remove"
                            enabled: globe.canZoomOut
                            focusPolicy: Qt.NoFocus
                            onClicked: globe.zoomOut()
                            Accessible.name: i18n("Zoom out")
                            PlasmaComponents3.ToolTip.text: i18n("Zoom out")
                            PlasmaComponents3.ToolTip.visible: hovered
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    // The visible way out of a country (Escape, the World tab
                    // and a click on the sea do it too).
                    PlasmaComponents3.ToolButton {
                        objectName: "leaveCountryButton"
                        visible: root.currentCountry ? true : false
                        icon.name: "edit-clear-locationbar-ltr"
                        onClicked: root.clearCountry()
                        Accessible.name: root.currentCountry ? i18n("Leave %1", root.currentCountry.name) : ""
                        PlasmaComponents3.ToolTip.text: root.currentCountry ? i18n("Leave %1", root.currentCountry.name) : ""
                        PlasmaComponents3.ToolTip.visible: hovered
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: full.statusLine
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                    }

                    // Only way out of the cached-data state: the world is
                    // otherwise fetched once per session.
                    PlasmaComponents3.ToolButton {
                        objectName: "retryButton"
                        visible: radioBrowser.lastError === "offline"
                        icon.name: "view-refresh"
                        text: i18n("Retry")
                        font: Kirigami.Theme.smallFont
                        onClicked: radioBrowser.refresh()
                    }
                }
            }

            ColumnLayout {
                id: listColumn
                Layout.fillWidth: full.narrow
                Layout.fillHeight: true
                Layout.preferredWidth: full.narrow ? -1 : Math.max(full.width * 0.4, listColumn.Layout.minimumWidth)
                spacing: Kirigami.Units.smallSpacing

                StationList {
                    id: stationList
                    objectName: "stationList"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    stations: root.shownStations
                    currentUuid: player.station ? player.station.uuid : ""
                    favoriteCheck: uuid => root.isFavorite(uuid)
                    currentTab: root.currentTab
                    loading: root.loadingCountry
                    onMenuRequested: station => full.openStationMenu(station)
                    onTabSelected: index => {
                        if (index === 0) {
                            // Picking World means "show me the world again":
                            // a country or a search still in place has to go.
                            if (root.currentCountry)
                                root.clearCountry();
                            if (searchBar.text !== "" || root.searchText !== "") {
                                searchBar.text = "";
                                root.clearSearch();
                            }
                        } else {
                            root.currentCountry = null;
                        }
                        root.currentTab = index;
                    }
                    onActivated: station => root.playFrom(root.shownStations, station)
                    onFavoriteToggled: station => root.toggleFavorite(station)
                    onRemoved: station => root.removeFromHistory(station)
                    onRenamed: (station, name) => root.renameFavorite(station, name)
                }

                PlayerBar {
                    objectName: "playerBar"
                    Layout.fillWidth: true
                    player: full.mediaPlayer
                    localTime: root.stationLocalTime
                    localTimeDescription: root.stationLocalTimeDescription
                    marqueeMode: root.marqueeMode
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
                    onMenuRequested: station => full.openStationMenu(station)
                    onLocateRequested: full.locateCurrentStation()
                    onEditRequested: if (full.mediaPlayer.station)
                        root.openStationEditor(full.mediaPlayer.station)
                }
            }
        }
    }

    Connections {
        target: player
        function onPlayingStarted(station) {
            full.centreOn(station);
        }
    }

    Connections {
        target: root
        function onExpandedChanged() {
            if (root.expanded)
                full.forceActiveFocus();
        }
    }

    // Typing invalidates whatever row Up/Down had picked, so Enter goes back
    // to submitting a search until the list is navigated again.
    Connections {
        target: searchBar
        function onTextChanged() {
            stationList.selectedIndex = -1;
        }
    }
}
