import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Requirements"

    function i18n(text) {
        return text;
    }

    Ui.Requirements {
        id: req
        // Probe nothing at startup: the tests drive it.
        modules: []
    }

    // A module that loads is fine, one that does not is reported with its
    // package names, so the widget can say what to install instead of dying.
    function test_probe_reports_missing_modules_with_packages() {
        req.modules = [
            {
                name: "QtQuick",
                required: true,
                deb: "qml6-module-qtquick",
                arch: "qt6-declarative",
                fedora: "qt6-qtdeclarative"
            },
            {
                name: "No.Such.Module",
                required: true,
                deb: "some-deb",
                arch: "some-arch",
                fedora: "some-fedora"
            },
            {
                name: "Nor.This.One",
                required: false,
                deb: "opt-deb",
                arch: "opt-arch",
                fedora: "opt-fedora"
            }
        ];
        req.probe();
        compare(req.missingRequired.length, 1);
        compare(req.missingRequired[0].name, "No.Such.Module");
        compare(req.missingOptional.length, 1);
        compare(req.missingOptional[0].name, "Nor.This.One");
        compare(req.packages("deb"), "some-deb opt-deb");
        compare(req.packages("arch"), "some-arch opt-arch");
        compare(req.requiredPackages("fedora"), "some-fedora");
    }

    function test_default_list_covers_every_import_of_the_widget() {
        const fresh = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/Requirements.qml")).createObject(null);
        const names = fresh.modules.map(m => m.name);
        for (const m of ["org.kde.plasma.plasma5support", "org.kde.plasma.private.mpris", "QtQuick.Dialogs", "QtCore", "org.kde.iconthemes", "org.kde.kquickcontrols", "org.kde.kcmutils", "QtQuick.LocalStorage", "QtLocation"])
            verify(names.indexOf(m) >= 0, "missing from the list: " + m);
        for (const m of fresh.modules)
            verify(m.deb && m.arch && m.fedora, m.name + " has no package names");
        fresh.destroy();
    }
}
