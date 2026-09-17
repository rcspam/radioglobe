import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Backup"

    // The KDE globals, with the %1 substitution they do.
    function i18n(text, ...args) {
        return args.reduce((out, arg, index) => out.replace("%" + (index + 1), arg), text);
    }
    function i18np(singular, plural, count) {
        return (count === 1 ? singular : plural).replace("%1", count);
    }

    readonly property string tempFile: "/tmp/radioglobe-tst-backup " + Date.now() + ".json"

    function createPage() {
        const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/config/configBackup.qml"));
        compare(component.status, Component.Ready, component.errorString());
        const page = component.createObject(null);
        verify(page !== null, component.errorString());
        return page;
    }

    function test_backup_text_carries_favourites_history_and_settings() {
        const page = createPage();
        page.cfg_favorites = JSON.stringify([
            {
                uuid: "fip",
                name: "FIP"
            }
        ]);
        page.cfg_history = JSON.stringify([
            {
                uuid: "jazz",
                name: "Jazz",
                playedAt: 1
            }
        ]);
        page.cfg_homeCountry = "FR";
        page.cfg_maxWorldStations = 2500;
        page.cfg_invertWheel = true;
        page.cfg_showDayNight = false;
        const backup = JSON.parse(page.backupText());
        compare(backup.radioglobe, 1);
        compare(backup.favorites.length, 1);
        compare(backup.favorites[0].uuid, "fip");
        compare(backup.history[0].uuid, "jazz");
        compare(backup.settings.homeCountry, "FR");
        compare(backup.settings.maxWorldStations, 2500);
        compare(backup.settings.invertWheel, true);
        compare(backup.settings.showDayNight, false);
        page.destroy();
    }

    // Importing only fills the page: the dialog's Apply writes it, Cancel drops it.
    function test_apply_backup_fills_the_page_and_reports_the_count() {
        const page = createPage();
        page.cfg_favorites = "[]";
        page.cfg_homeCountry = "DE";
        const ok = page.applyBackup(JSON.stringify({
            radioglobe: 1,
            favorites: [
                {
                    uuid: "fip"
                },
                {
                    uuid: "jazz"
                }
            ],
            history: [
                {
                    uuid: "fip",
                    playedAt: 1
                }
            ],
            settings: {
                homeCountry: "FR",
                icon: "radio",
                bogus: 1
            }
        }));
        compare(ok, true);
        compare(JSON.parse(page.cfg_favorites).length, 2);
        compare(JSON.parse(page.cfg_history).length, 1);
        compare(page.cfg_homeCountry, "FR");
        compare(page.cfg_icon, "radio");
        verify(page.importStatus.indexOf("2") >= 0, page.importStatus);
        page.destroy();
    }

    function test_apply_backup_refuses_a_foreign_file_and_keeps_the_page() {
        const page = createPage();
        page.cfg_favorites = JSON.stringify([
            {
                uuid: "fip"
            }
        ]);
        compare(page.applyBackup("{ nope"), false);
        compare(page.applyBackup('{"favorites": []}'), false);
        compare(JSON.parse(page.cfg_favorites).length, 1);
        verify(page.importStatus !== "", "no error shown");
        page.destroy();
    }

    // The round trip through the shell: a path with a space, written then read.
    function test_export_then_import_through_a_file() {
        const page = createPage();
        page.cfg_favorites = JSON.stringify([
            {
                uuid: "fip",
                name: "L'ami 'quoté'"
            }
        ]);
        page.cfg_homeCountry = "FR";
        page.exportTo("file://" + tempFile);
        tryVerify(() => page.exportStatus.indexOf(tempFile) >= 0, 5000, page.exportStatus);

        const other = createPage();
        other.cfg_favorites = "[]";
        other.importFrom("file://" + tempFile);
        tryVerify(() => other.cfg_favorites !== "[]", 5000, other.importStatus);
        compare(JSON.parse(other.cfg_favorites)[0].name, "L'ami 'quoté'");
        compare(other.cfg_homeCountry, "FR");
        page.destroy();
        other.destroy();

        let removed = false;
        cleanup.run("rm -f '" + tempFile + "'", () => removed = true);
        tryVerify(() => removed, 5000);
    }

    Ui.Exec {
        id: cleanup
    }

    function test_import_of_a_missing_file_reports_an_error() {
        const page = createPage();
        page.importFrom("/nonexistent/radioglobe.json");
        tryVerify(() => page.importStatus !== "", 5000, "no status");
        compare(page.cfg_favorites, "[]");
        page.destroy();
    }
}
