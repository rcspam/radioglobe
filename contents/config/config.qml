import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "settings-configure"
        source: "config/configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Add a station")
        icon: "list-add"
        source: "config/configAddStation.qml"
    }
}
