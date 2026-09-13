import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    switchWidth: Kirigami.Units.gridUnit * 30
    switchHeight: Kirigami.Units.gridUnit * 20

    toolTipMainText: i18n("RadioGlobe")
    toolTipSubText: i18n("No station playing")

    compactRepresentation: Kirigami.Icon {
        source: "radio"
        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 45
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30
        PlasmaComponents3.Label {
            anchors.centerIn: parent
            text: i18n("RadioGlobe")
        }
    }
}
