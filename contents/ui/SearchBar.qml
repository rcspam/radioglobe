import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

RowLayout {
    id: bar

    property alias text: field.text
    readonly property bool inputFocused: field.activeFocus

    // The filter menu's current choices ({sort, codec, minBitrate}, see
    // RadioModel.applyFilters) and whether any departs from the defaults.
    property var filters: ({})
    property bool filtersActive: false

    signal searchRequested(string text)
    signal cleared
    signal randomRequested
    // key "sort" / "codec" / "minBitrate", the new value.
    signal filterRequested(string key, var value)

    function focusInput() {
        field.forceActiveFocus();
        field.selectAll();
    }

    spacing: Kirigami.Units.smallSpacing

    PlasmaComponents3.TextField {
        id: field
        objectName: "searchField"
        Layout.fillWidth: true
        placeholderText: i18n("Search stations, countries, tags…")
        onAccepted: bar.searchRequested(text)
        onTextChanged: if (text === "")
            bar.cleared()
        Keys.onEscapePressed: event => {
            if (text !== "")
                text = "";
            else
                event.accepted = false;
        }
    }

    PlasmaComponents3.ToolButton {
        id: filterButton
        objectName: "filterButton"
        icon.name: "view-filter"
        // Stays lit while a sort or a filter is on.
        highlighted: bar.filtersActive
        onClicked: filterMenu.popup(filterButton, 0, filterButton.height)
        Accessible.name: i18n("Sort and filter the list")
        PlasmaComponents3.ToolTip.text: i18n("Sort and filter the list")
        PlasmaComponents3.ToolTip.visible: hovered && !filterMenu.visible
    }

    // One checkable line of the filter menu: the choice it stands for is
    // lit when it is the current one, and asks for itself when triggered.
    component FilterItem: PlasmaComponents3.MenuItem {
        required property string key
        required property var value
        readonly property var current: filterMenu.current(key)
        objectName: key + "-" + (value === "" || value === 0 ? "any" : value)
        checkable: true
        checked: current === value
        onTriggered: bar.filterRequested(key, value)
    }

    PlasmaComponents3.Menu {
        id: filterMenu
        objectName: "filterMenu"

        function current(key) {
            const filters = bar.filters || {};
            if (key === "minBitrate")
                return Number(filters.minBitrate) || 0;
            if (key === "sort")
                return String(filters.sort || "popularity");
            return String(filters.codec || "");
        }

        PlasmaComponents3.MenuItem {
            text: i18n("Sort by")
            enabled: false
        }
        FilterItem {
            key: "sort"
            value: "popularity"
            text: i18n("Popularity")
        }
        FilterItem {
            key: "sort"
            value: "votes"
            text: i18n("Votes")
        }
        FilterItem {
            key: "sort"
            value: "name"
            text: i18n("Name")
        }
        FilterItem {
            key: "sort"
            value: "bitrate"
            text: i18n("Bitrate")
        }
        PlasmaComponents3.MenuSeparator {}
        PlasmaComponents3.MenuItem {
            text: i18n("Codec")
            enabled: false
        }
        FilterItem {
            key: "codec"
            value: ""
            text: i18n("Any codec")
        }
        FilterItem {
            key: "codec"
            value: "mp3"
            text: "MP3"
        }
        FilterItem {
            key: "codec"
            value: "aac"
            text: "AAC"
        }
        PlasmaComponents3.MenuSeparator {}
        PlasmaComponents3.MenuItem {
            text: i18n("Minimum bitrate")
            enabled: false
        }
        FilterItem {
            key: "minBitrate"
            value: 0
            text: i18n("Any bitrate")
        }
        FilterItem {
            key: "minBitrate"
            value: 64
            text: i18n("%1 kbps", 64)
        }
        FilterItem {
            key: "minBitrate"
            value: 128
            text: i18n("%1 kbps", 128)
        }
        FilterItem {
            key: "minBitrate"
            value: 192
            text: i18n("%1 kbps", 192)
        }
        FilterItem {
            key: "minBitrate"
            value: 256
            text: i18n("%1 kbps", 256)
        }
    }

    PlasmaComponents3.ToolButton {
        icon.name: "media-playlist-shuffle"
        text: i18n("Random")
        display: PlasmaComponents3.AbstractButton.IconOnly
        onClicked: bar.randomRequested()
        PlasmaComponents3.ToolTip.text: i18n("Tune a random station (R)")
        PlasmaComponents3.ToolTip.visible: hovered
    }
}
