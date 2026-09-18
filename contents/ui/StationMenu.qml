import QtQuick
import org.kde.plasma.components as PlasmaComponents3

// Right-click menu of a station, from the list or the player bar. It only
// emits: the owner decides what playing, favouriting or copying means.
PlasmaComponents3.Menu {
    id: menu

    property var station: null
    property bool favorite: false

    signal playRequested(var station)
    signal favoriteRequested(var station)
    signal copyRequested(string text)
    signal propertiesRequested(var station)
    signal voteRequested(var station)

    function open(target, isFavorite) {
        menu.station = target;
        menu.favorite = isFavorite === true;
        menu.popup();
    }

    PlasmaComponents3.MenuItem {
        objectName: "menuPlay"
        text: i18n("Play")
        icon.name: "media-playback-start"
        onTriggered: menu.playRequested(menu.station)
    }
    PlasmaComponents3.MenuItem {
        objectName: "menuFavorite"
        text: menu.favorite ? i18n("Remove from favorites") : i18n("Add to favorites")
        icon.name: menu.favorite ? "starred-symbolic" : "non-starred-symbolic"
        onTriggered: menu.favoriteRequested(menu.station)
    }
    PlasmaComponents3.MenuSeparator {}
    PlasmaComponents3.MenuItem {
        objectName: "menuCopyUrl"
        text: i18n("Copy stream URL")
        icon.name: "edit-copy"
        enabled: menu.station && menu.station.url ? true : false
        onTriggered: menu.copyRequested(String(menu.station.url))
    }
    PlasmaComponents3.MenuItem {
        objectName: "menuHomepage"
        text: i18n("Open homepage")
        icon.name: "internet-web-browser"
        enabled: menu.station && menu.station.homepage ? true : false
        onTriggered: Qt.openUrlExternally(menu.station.homepage)
    }
    PlasmaComponents3.MenuItem {
        objectName: "menuVote"
        text: i18n("Vote for this station on Radio Browser")
        icon.name: "thumbs-up-symbolic"
        enabled: menu.station && menu.station.uuid && !menu.station.localOnly ? true : false
        onTriggered: menu.voteRequested(menu.station)
    }
    PlasmaComponents3.MenuSeparator {}
    PlasmaComponents3.MenuItem {
        objectName: "menuProperties"
        text: i18n("Properties…")
        icon.name: "documentinfo"
        onTriggered: menu.propertiesRequested(menu.station)
    }
}
