import QtQuick
import org.kde.plasma.configuration
import org.kde.plasma.plasmoid

// The dialog always opens on the first visible category and nothing lets an
// applet pick another one, so "Add a station" is declared twice: first,
// visible only when the popup's "+" button asked for it (main.qml sets
// configStartPage before opening the dialog), and after General otherwise.
ConfigModel {
    ConfigCategory {
        name: i18n("Add a station")
        icon: "list-add"
        source: "config/configAddStation.qml"
        visible: Plasmoid.configuration.configStartPage === "addStation"
    }
    ConfigCategory {
        name: i18n("General")
        icon: "settings-configure"
        source: "config/configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Add a station")
        icon: "list-add"
        source: "config/configAddStation.qml"
        visible: Plasmoid.configuration.configStartPage !== "addStation"
    }
    ConfigCategory {
        name: i18n("Backup")
        icon: "document-save"
        source: "config/configBackup.qml"
    }
}
