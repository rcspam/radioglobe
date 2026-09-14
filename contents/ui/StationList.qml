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
            text: i18n("World")
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
            clip: true
            model: list.stations
            currentIndex: list.selectedIndex

            delegate: PlasmaComponents3.ItemDelegate {
                id: row
                required property var modelData
                required property int index
                width: view.width
                highlighted: list.selectedIndex === index || list.currentUuid === modelData.uuid
                onClicked: list.activated(modelData)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.bold: list.currentUuid === row.modelData.uuid
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: RadioModel.stationMeta(row.modelData)
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            opacity: 0.7
                            font: Kirigami.Theme.smallFont
                        }
                    }
                    PlasmaComponents3.ToolButton {
                        icon.name: list.favoriteCheck(row.modelData.uuid) ? "starred-symbolic" : "non-starred-symbolic"
                        onClicked: list.favoriteToggled(row.modelData)
                        PlasmaComponents3.ToolTip.text: i18n("Toggle favorite (F)")
                        PlasmaComponents3.ToolTip.visible: hovered
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
