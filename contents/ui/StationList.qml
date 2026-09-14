import QtQuick
import QtQuick.Layouts
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

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ListView {
            id: view
            objectName: "stationView"
            clip: true
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

                width: view.width
                height: nameLabel.implicitHeight + metaLabel.implicitHeight + Kirigami.Units.smallSpacing * 2

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
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
                    anchors.right: starArea.left
                    anchors.top: parent.top
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    anchors.topMargin: Kirigami.Units.smallSpacing
                    text: row.modelData.name
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.bold: row.playing
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

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.smallMedium
                        height: width
                        source: list.favoriteCheck(row.modelData.uuid) ? "starred-symbolic" : "non-starred-symbolic"
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
}
