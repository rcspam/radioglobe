import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "RadioModel.js" as RadioModel

ColumnLayout {
    id: list

    property var stations: []
    property string currentUuid: ""
    property var favoriteCheck: function (uuid) {
        return false;
    }
    property int currentTab: 0
    property int selectedIndex: -1

    // uuid of the row behind selectedIndex, kept so the selection survives a
    // list refresh. Tracked by hand: it must still hold the previous value
    // while onStationsChanged runs.
    property string _selectedUuid: ""

    signal tabSelected(int index)
    signal activated(var station)
    signal favoriteToggled(var station)
    // Trash on the Recent tab.
    signal removed(var station)
    // Pencil on the Favorites tab; name already trimmed by the field.
    signal renamed(var station, string name)

    function moveSelection(delta) {
        const count = Array.isArray(list.stations) ? list.stations.length : 0;
        if (count === 0) {
            list.selectedIndex = -1;
            return;
        }
        list.selectedIndex = Math.min(count - 1, Math.max(0, list.selectedIndex + delta));
        view.positionViewAtIndex(list.selectedIndex, ListView.Contain);
    }

    function activateSelected() {
        if (list.selectedIndex >= 0 && list.selectedIndex < list.stations.length)
            list.activated(list.stations[list.selectedIndex]);
    }

    // A refresh (new world batch, favourite toggled...) replaces the array
    // wholesale, so the highlight follows the station rather than the row.
    onStationsChanged: list.selectedIndex = RadioModel.indexByUuid(list.stations, list._selectedUuid)
    onSelectedIndexChanged: list._selectedUuid = list.selectedIndex >= 0 && Array.isArray(list.stations) && list.selectedIndex < list.stations.length ? String(list.stations[list.selectedIndex].uuid || "") : ""

    spacing: 0

    PlasmaComponents3.TabBar {
        Layout.fillWidth: true
        currentIndex: list.currentTab
        onCurrentIndexChanged: if (currentIndex !== list.currentTab)
            list.tabSelected(currentIndex)

        PlasmaComponents3.TabButton {
            objectName: "worldTab"
            text: i18n("World")
            // Clicking World while it is already the current tab changes no
            // index, so the bar stays silent; emit by hand, otherwise there
            // is no way back to the world from a country or a search.
            onClicked: list.tabSelected(0)
        }
        PlasmaComponents3.TabButton {
            text: i18n("Favorites")
        }
        PlasmaComponents3.TabButton {
            text: i18n("Recent")
        }
    }

    // A bare ListView with its own scroll bar, on purpose: wrapped in a
    // ScrollView, the view's implicitHeight and the ScrollView's content
    // size chased each other and the whole model got instantiated once
    // (3 000 rows, 5 s of GUI thread at every plasmashell start, since
    // Plasma preloads the popup at 0x0).
    ListView {
        id: view
        objectName: "stationView"
        Layout.fillWidth: true
        Layout.fillHeight: true
        QQC2.ScrollBar.vertical: PlasmaComponents3.ScrollBar {}
        clip: true

        // What the ScrollView used to add: wheel and touchpad scrolling with
        // Kirigami's stepping and momentum.
        Kirigami.WheelHandler {
            target: view
            horizontalStepSize: Application.styleHints.wheelScrollLines * 20
            verticalStepSize: Application.styleHints.wheelScrollLines * 20
        }
        model: list.stations
        currentIndex: list.selectedIndex
        // A world batch is 3000 rows and the user flings through them:
        // recycling the delegates is what keeps the scroll off the GUI
        // thread. Everything below binds to modelData and to list.*, so a
        // reused row rebinds on its own with no onReused handler.
        reuseItems: true
        cacheBuffer: view.height

        // Deliberately not an ItemDelegate with nested layouts: that cost
        // 2 ms per row to build against 0.8 ms for plain anchors.
        delegate: Item {
            id: row
            objectName: "stationRow"

            required property var modelData
            required property int index
            readonly property bool playing: list.currentUuid === row.modelData.uuid
            readonly property bool highlighted: list.selectedIndex === row.index || row.playing
            // Reads list.favorites through the injected favoriteCheck, so
            // the binding re-evaluates when the favourites change.
            readonly property bool favorite: list.favoriteCheck(row.modelData.uuid)

            width: view.width
            height: Math.max(nameLabel.implicitHeight + metaLabel.implicitHeight + Kirigami.Units.smallSpacing * 2, starArea.height)

            // An Item is not an ItemDelegate: the screen reader gets
            // nothing unless the row says what it is.
            Accessible.role: Accessible.ListItem
            Accessible.name: row.modelData.name
            Accessible.description: metaLabel.text
            Accessible.selected: row.highlighted

            Rectangle {
                anchors.fill: parent
                anchors.margins: Math.round(Kirigami.Units.smallSpacing / 2)
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.highlightColor
                opacity: rowArea.pressed ? 0.45 : (row.highlighted ? 0.28 : (rowArea.containsMouse ? 0.14 : 0))
                visible: opacity > 0
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: list.activated(row.modelData)
            }

            PlasmaComponents3.Label {
                id: nameLabel
                anchors.left: parent.left
                anchors.right: actionArea.left
                anchors.top: parent.top
                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                anchors.rightMargin: Kirigami.Units.smallSpacing
                text: row.modelData.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.bold: row.playing
                visible: !renameField.visible
            }

            // Inline rename, shown by the pencil. Return commits, Escape
            // or leaving the field drops the edit. A Loader, not a plain
            // TextField: one text field per recycled row sent plasmashell
            // into a layout loop at 100 % CPU (seen on 6.6.6).
            Loader {
                id: renameField
                objectName: "renameLoader"
                anchors.left: nameLabel.left
                anchors.right: nameLabel.right
                anchors.top: parent.top
                active: false
                visible: active
                function open() {
                    active = true;
                }
                sourceComponent: PlasmaComponents3.TextField {
                    objectName: "renameField"
                    text: row.modelData.name
                    Component.onCompleted: {
                        forceActiveFocus();
                        selectAll();
                    }
                    onAccepted: {
                        const name = text.trim();
                        if (name !== "" && name !== row.modelData.name)
                            list.renamed(row.modelData, name);
                        renameField.active = false;
                    }
                    Keys.onEscapePressed: renameField.active = false
                    onActiveFocusChanged: if (!activeFocus)
                        renameField.active = false
                }
            }

            PlasmaComponents3.Label {
                id: metaLabel
                objectName: "stationMeta"
                anchors.left: nameLabel.left
                anchors.right: nameLabel.right
                anchors.top: nameLabel.bottom
                // Precomputed by normalizeStation; rows restored from a
                // cache written by an older build have no meta field.
                text: row.modelData.meta || RadioModel.stationMeta(row.modelData)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                opacity: 0.7
                font: Kirigami.Theme.smallFont
            }

            // Tab-specific button left of the star: the trash on Recent,
            // the pencil on Favorites. An Item so the star keeps its place.
            Item {
                id: actionArea
                anchors.right: starArea.left
                anchors.verticalCenter: parent.verticalCenter
                width: (removeArea.visible || renameArea.visible) ? starArea.width : 0
                height: starArea.height

                MouseArea {
                    id: removeArea
                    objectName: "removeButton"
                    anchors.fill: parent
                    visible: list.currentTab === 2
                    hoverEnabled: true
                    onClicked: list.removed(row.modelData)
                    PlasmaComponents3.ToolTip.text: i18n("Remove from recent")
                    PlasmaComponents3.ToolTip.visible: removeArea.containsMouse
                    Accessible.role: Accessible.Button
                    Accessible.name: i18n("Remove from recent")
                    Accessible.onPressAction: list.removed(row.modelData)

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: "edit-delete-symbolic"
                        opacity: removeArea.containsMouse ? 1 : 0.6
                    }
                }

                MouseArea {
                    id: renameArea
                    objectName: "renameButton"
                    anchors.fill: parent
                    visible: list.currentTab === 1
                    hoverEnabled: true
                    onClicked: renameField.open()
                    PlasmaComponents3.ToolTip.text: i18n("Rename")
                    PlasmaComponents3.ToolTip.visible: renameArea.containsMouse
                    Accessible.role: Accessible.Button
                    Accessible.name: i18n("Rename")
                    Accessible.onPressAction: renameField.open()

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: "edit-rename"
                        opacity: renameArea.containsMouse ? 1 : 0.6
                    }
                }
            }

            MouseArea {
                id: starArea
                objectName: "favoriteButton"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: Kirigami.Units.smallSpacing
                width: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing * 2
                height: width
                hoverEnabled: true
                onClicked: list.favoriteToggled(row.modelData)
                PlasmaComponents3.ToolTip.text: i18n("Toggle favorite (F)")
                PlasmaComponents3.ToolTip.visible: starArea.containsMouse

                Accessible.role: Accessible.CheckBox
                Accessible.name: i18n("Toggle favorite (F)")
                Accessible.checkable: true
                Accessible.checked: row.favorite
                Accessible.onPressAction: list.favoriteToggled(row.modelData)

                Kirigami.Icon {
                    objectName: "favoriteIcon"
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    source: row.favorite ? "starred-symbolic" : "non-starred-symbolic"
                    opacity: starArea.containsMouse ? 1 : 0.85
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: view.count === 0
            iconName: "radio"
            text: list.currentTab === 1 ? i18n("No favorites yet") : list.currentTab === 2 ? i18n("Nothing played yet") : i18n("No stations")
        }
    }
}
