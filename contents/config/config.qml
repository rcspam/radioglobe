import QtQuick
import org.kde.plasma.configuration
import org.kde.plasma.plasmoid

// Plasma opens the dialog on the first category declared, visible or not
// (AppletConfiguration.qml: open(configModel.get(0))), and nothing lets an
// applet pick another one. So the first two categories swap their pages:
// General first, unless the popup's "+" button asked for "Add a station"
// (main.qml sets configStartPage before opening the dialog; the page clears
// it once shown, and the sidebar goes back to the usual order).
ConfigModel {
    id: categories

    // Written by tests; the plasmoid only ever reads the configuration.
    property string startPage: Plasmoid.configuration ? Plasmoid.configuration.configStartPage : ""

    readonly property var general: ({
            name: i18n("General"),
            icon: "settings-configure",
            source: "config/configGeneral.qml"
        })
    readonly property var addStation: ({
            name: i18n("Add a station"),
            icon: "list-add",
            source: "config/configAddStation.qml"
        })
    readonly property var first: categories.startPage === "addStation" ? categories.addStation : categories.general
    readonly property var second: categories.startPage === "addStation" ? categories.general : categories.addStation

    ConfigCategory {
        name: categories.first.name
        icon: categories.first.icon
        source: categories.first.source
    }
    ConfigCategory {
        name: categories.second.name
        icon: categories.second.icon
        source: categories.second.source
    }
    ConfigCategory {
        name: i18n("Backup")
        icon: "document-save"
        source: "config/configBackup.qml"
    }
}
