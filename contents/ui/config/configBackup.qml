import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import ".." as Ui
import "../RadioModel.js" as RadioModel

// Export and import of everything the user set up, as one JSON file. Plasma
// drops an applet's configuration when the applet is removed from the panel,
// so this is the only way favourites survive that (or move to another machine).
//
// Importing only fills the cfg_ properties: the dialog's Apply writes them to
// the configuration, Cancel forgets them, like any other page.
KCM.SimpleKCM {
    id: page

    property string cfg_favorites: "[]"
    property string cfg_history: "[]"
    property string cfg_homeCountry: ""
    property int cfg_maxWorldStations: 3000
    property bool cfg_approximateLocations: false
    property string cfg_mpvPath: ""
    property bool cfg_sendClicks: true
    property string cfg_icon: "map-globe"
    property string cfg_iconColor: ""
    property string cfg_badgeColor: ""
    property bool cfg_invertWheel: false
    property bool cfg_showDayNight: true

    property string exportStatus: ""
    property string importStatus: ""

    readonly property string defaultFileName: "radioglobe-backup.json"

    // /bin/sh -c takes the whole command as one argument, capped around 128 KiB
    // by the kernel: a long favourites list is written in several appends.
    readonly property int writeChunk: 60000

    Ui.Exec {
        id: exec
    }

    function parseList(text) {
        try {
            const rows = JSON.parse(String(text || "[]"));
            return Array.isArray(rows) ? rows : [];
        } catch (error) {
            return [];
        }
    }

    function localPath(fileUrl) {
        return decodeURIComponent(String(fileUrl).replace(/^file:\/\//, ""));
    }

    function backupText() {
        const settings = ({});
        for (const key in RadioModel.backupSettingTypes)
            settings[key] = page["cfg_" + key];
        const backup = RadioModel.buildBackup(page.parseList(page.cfg_favorites), page.parseList(page.cfg_history), settings);
        return JSON.stringify(backup, null, 1);
    }

    // Fills the page from a backup file's text. False (with importStatus set)
    // when the text is not one of ours; the page is then left as it was.
    function applyBackup(text) {
        const result = RadioModel.parseBackup(text);
        if (!result.ok) {
            page.importStatus = result.error === "invalid-json" ? i18n("This file is not valid JSON.") : i18n("This file is not a RadioGlobe backup.");
            return false;
        }
        page.cfg_favorites = JSON.stringify(result.favorites);
        page.cfg_history = JSON.stringify(result.history);
        for (const key in result.settings)
            page["cfg_" + key] = result.settings[key];
        page.importStatus = i18np("%1 favourite imported. Apply to keep it.", "%1 favourites imported. Apply to keep them.", result.favorites.length);
        return true;
    }

    function exportTo(fileUrl) {
        const path = page.localPath(fileUrl);
        const text = page.backupText();
        page.exportStatus = i18n("Saving…");
        const chunks = [];
        for (let offset = 0; offset < text.length; offset += page.writeChunk)
            chunks.push(text.slice(offset, offset + page.writeChunk));
        const writeNext = index => {
            const redirect = index === 0 ? " > " : " >> ";
            exec.run("printf '%s' " + RadioModel.shellQuote(chunks[index]) + redirect + RadioModel.shellQuote(path), code => {
                if (code !== 0)
                    page.exportStatus = i18n("Could not write %1.", path);
                else if (index + 1 < chunks.length)
                    writeNext(index + 1);
                else
                    page.exportStatus = i18n("Saved to %1", path);
            });
        };
        writeNext(0);
    }

    function importFrom(fileUrl) {
        const path = page.localPath(fileUrl);
        page.importStatus = i18n("Reading…");
        exec.run("cat " + RadioModel.shellQuote(path), (code, out) => {
            if (code !== 0) {
                page.importStatus = i18n("Could not read %1.", path);
                return;
            }
            page.applyBackup(out);
        });
    }

    FileDialog {
        id: exportDialog
        title: i18n("Export RadioGlobe settings")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [i18n("JSON files (*.json)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        selectedFile: currentFolder + "/" + page.defaultFileName
        onAccepted: page.exportTo(selectedFile)
    }

    FileDialog {
        id: importDialog
        title: i18n("Import RadioGlobe settings")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("JSON files (*.json)"), i18n("All files (*)")]
        currentFolder: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        onAccepted: page.importFrom(selectedFile)
    }

    Kirigami.FormLayout {
        QQC2.Label {
            text: i18n("Plasma forgets a widget's settings when the widget is removed from the panel. Save them to a file to restore them later or on another computer.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Item {
            Kirigami.FormData.isSection: true
        }
        QQC2.Button {
            Kirigami.FormData.label: i18n("Export:")
            text: i18n("Save to a file…")
            icon.name: "document-export"
            onClicked: exportDialog.open()
        }
        QQC2.Label {
            text: i18n("Favourites, history, home country, panel icon and the other options. Not the volume or the station being played.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        QQC2.Label {
            text: page.exportStatus
            visible: text !== ""
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        Item {
            Kirigami.FormData.isSection: true
        }
        QQC2.Button {
            Kirigami.FormData.label: i18n("Import:")
            text: i18n("Load from a file…")
            icon.name: "document-import"
            onClicked: importDialog.open()
        }
        QQC2.Label {
            text: i18n("Replaces the current favourites and history. Nothing is changed until you apply.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            opacity: 0.7
        }
        QQC2.Label {
            text: page.importStatus
            visible: text !== ""
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
