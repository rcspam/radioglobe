import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "RadioModel.js" as RadioModel

RowLayout {
    id: bar

    property alias text: field.text
    readonly property bool inputFocused: field.activeFocus

    // The filter menu's current choices ({sort, codec, minBitrate}, see
    // RadioModel.applyFilters) and whether any departs from the defaults.
    property var filters: ({})
    property bool filtersActive: false
    // The window the bar lives in, for keeping the filter menu inside it.
    readonly property var hostWindow: Window.window

    signal searchRequested(string text)
    signal cleared
    signal randomRequested
    // key "sort" / "codec" / "minBitrate", the new value.
    signal filterRequested(string key, var value)
    signal filtersResetRequested

    // The owner calls this when the widget's popup closes: a menu left open
    // in a hidden window would be back, still open, the next time.
    function closeMenu() {
        filterMenu.close();
    }

    function focusInput() {
        field.forceActiveFocus();
        field.selectAll();
    }

    spacing: Kirigami.Units.smallSpacing

    // A text field with a clear button. Not PlasmaExtras.SearchField: its
    // own clear action stays in rightActions next to any added one, and it
    // also fires accepted(), which here plays the list row Up/Down picked.
    PlasmaExtras.ActionTextField {
        id: field
        objectName: "searchField"
        Layout.fillWidth: true
        placeholderText: i18n("Search stations, countries, tags…")
        rightActions: [
            Kirigami.Action {
                objectName: "clearAction"
                icon.name: field.effectiveHorizontalAlignment === TextInput.AlignRight ? "edit-clear-locationbar-ltr" : "edit-clear-locationbar-rtl"
                visible: field.text.length > 0
                text: i18n("Clear search")
                onTriggered: field.clear()
            }
        ]
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
        // A second click closes the menu: it does not close on a press over
        // its parent (closePolicy below), so this sees it still open.
        onClicked: {
            if (filterMenu.visible)
                filterMenu.close();
            else
                filterMenu.open();
        }
        Accessible.name: i18n("Sort and filter the list")
        PlasmaComponents3.ToolTip.text: i18n("Sort and filter the list")
        PlasmaComponents3.ToolTip.visible: hovered && !filterMenu.visible
    }

    // A checkable menu line with a plain check icon: Plasma's own indicator
    // draws its hover frame over the mark, which hides it in some themes.
    // Not `checkable`: a checkable MenuItem flips its own `checked` on every
    // click, before the owner has applied anything, and from then on shows
    // its private state rather than the filters. `active` is bound to the
    // filters alone; a click only asks the owner for a change.
    component CheckedItem: PlasmaComponents3.MenuItem {
        id: line
        property bool active: false
        Layout.fillWidth: true
        checkable: false
        // Room for the mark, which a non-checkable item does not reserve.
        leftPadding: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 3
        indicator: Kirigami.Icon {
            x: line.mirrored ? line.width - width - Kirigami.Units.smallSpacing * 2 : Kirigami.Units.smallSpacing * 2
            y: line.topPadding + Math.round((line.availableHeight - height) / 2)
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            source: "checkmark"
            visible: line.active
        }
    }
    component CodecItem: CheckedItem {
        required property string family
        objectName: "codec-" + family
        active: filterMenu.codecs.indexOf(family) >= 0
        onTriggered: bar.filterRequested("codec", RadioModel.toggleCodec(filterMenu.current("codec"), family, !active))
    }
    component FilterItem: CheckedItem {
        required property string key
        required property var value
        readonly property var current: filterMenu.current(key)
        objectName: key + "-" + (value === "" || value === 0 ? "any" : value)
        active: current === value
        onTriggered: bar.filterRequested(key, value)
    }

    // A Popup, not a Menu: a Menu closes as soon as an entry is picked, and
    // one usually sets two or three things here. It closes when the pointer
    // leaves it (or the button) for a moment, on Escape, on a press outside
    // or on a second click on the button.
    PlasmaComponents3.Popup {
        id: filterMenu
        objectName: "filterMenu"
        parent: filterButton
        // Right-aligned to its button, which sits at the right of the bar,
        // and kept inside the window whatever the popup's size (a Popup
        // never moves itself, unlike a Menu). Placed on each opening: the
        // bar may have been resized since the last one.
        onAboutToShow: filterMenu.place()
        function place() {
            const origin = filterButton.mapToItem(null, 0, 0);
            const window = bar.hostWindow;
            const windowWidth = window ? window.width : Infinity;
            const windowHeight = window ? window.height : Infinity;
            let wantedX = filterButton.width - filterMenu.width;
            if (origin.x + wantedX < 0)
                wantedX = -origin.x;
            let wantedY = filterButton.height;
            if (origin.y + wantedY + filterMenu.height > windowHeight)
                wantedY = Math.max(-origin.y, windowHeight - filterMenu.height - origin.y);
            filterMenu.x = Math.round(Math.min(wantedX, windowWidth - filterMenu.width - origin.x));
            filterMenu.y = Math.round(wantedY);
        }
        // Grace period once the pointer is out, so a quick brush past the
        // edge does not close it.
        property int leaveDelayMs: 400
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

        readonly property var codecs: RadioModel.codecSet(filterMenu.current("codec"))

        function current(key) {
            const filters = bar.filters || {};
            if (key === "minBitrate")
                return Number(filters.minBitrate) || 0;
            if (key === "sort")
                return String(filters.sort || "popularity");
            return String(filters.codec || "");
        }

        readonly property bool pointerInside: menuHover.hovered || filterButton.hovered
        onPointerInsideChanged: {
            if (filterMenu.pointerInside)
                leaveTimer.stop();
            else if (filterMenu.visible)
                leaveTimer.restart();
        }
        onClosed: leaveTimer.stop()

        HoverHandler {
            id: menuHover
        }
        Timer {
            id: leaveTimer
            interval: filterMenu.leaveDelayMs
            onTriggered: if (!filterMenu.pointerInside)
                filterMenu.close()
        }

        contentItem: ColumnLayout {
            spacing: 0

            PlasmaComponents3.MenuItem {
                Layout.fillWidth: true
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
            PlasmaComponents3.MenuSeparator {
                Layout.fillWidth: true
            }
            PlasmaComponents3.MenuItem {
                Layout.fillWidth: true
                text: i18n("Codec")
                enabled: false
            }
            // Codecs combine: each entry toggles its family in the set,
            // "Any" empties it.
            FilterItem {
                key: "codec"
                value: ""
                text: i18n("Any codec")
                active: filterMenu.codecs.length === 0
            }
            CodecItem {
                family: "mp3"
                text: "MP3"
            }
            CodecItem {
                family: "aac"
                text: i18n("AAC (and AAC+)")
            }
            CodecItem {
                family: "ogg"
                text: i18n("OGG (Vorbis)")
            }
            PlasmaComponents3.MenuSeparator {
                Layout.fillWidth: true
            }
            PlasmaComponents3.MenuItem {
                Layout.fillWidth: true
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
            PlasmaComponents3.MenuSeparator {
                Layout.fillWidth: true
            }
            PlasmaComponents3.MenuItem {
                objectName: "filterReset"
                Layout.fillWidth: true
                text: i18n("Reset")
                icon.name: "edit-clear-all"
                enabled: bar.filtersActive
                onTriggered: bar.filtersResetRequested()
            }
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
