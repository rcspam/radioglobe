import QtQuick

// Probes the QML modules the widget uses, so a missing package on the host
// shows as a message with what to install instead of the applet failing to
// load. Everything risky in the widget itself already goes through Loaders
// (MPRIS, cache, map, exec); the config pages import their modules directly
// and would fail on their own, hence the banner listing them up front.
QtObject {
    id: root

    // name: QML module; required: false for features that degrade cleanly;
    // deb / arch / fedora: package names per distribution.
    property var modules: [
        {
            name: "org.kde.plasma.plasma5support",
            required: true,
            deb: "qml6-module-org-kde-plasma-plasma5support",
            arch: "plasma5support",
            fedora: "plasma5support"
        },
        {
            name: "org.kde.plasma.private.mpris",
            required: true,
            deb: "plasma-workspace",
            arch: "plasma-workspace",
            fedora: "plasma-workspace"
        },
        {
            name: "org.kde.kcmutils",
            required: true,
            deb: "qml6-module-org-kde-kcmutils",
            arch: "kcmutils",
            fedora: "kf6-kcmutils"
        },
        {
            name: "QtQuick.Dialogs",
            required: true,
            deb: "qml6-module-qtquick-dialogs",
            arch: "qt6-declarative",
            fedora: "qt6-qtdeclarative"
        },
        {
            name: "QtCore",
            required: true,
            deb: "qml6-module-qtcore",
            arch: "qt6-declarative",
            fedora: "qt6-qtdeclarative"
        },
        {
            name: "org.kde.iconthemes",
            required: true,
            deb: "qml6-module-org-kde-iconthemes",
            arch: "kiconthemes",
            fedora: "kf6-kiconthemes"
        },
        {
            name: "org.kde.kquickcontrols",
            required: true,
            deb: "qml6-module-org-kde-kquickcontrols",
            arch: "kdeclarative",
            fedora: "kf6-kdeclarative"
        },
        {
            name: "QtQuick.LocalStorage",
            required: false,
            deb: "qml6-module-qtquick-localstorage",
            arch: "qt6-declarative",
            fedora: "qt6-qtdeclarative"
        },
        {
            name: "QtLocation",
            required: false,
            deb: "qml6-module-qtlocation qt6-location-plugins",
            arch: "qt6-location",
            fedora: "qt6-qtlocation"
        }
    ]

    property var missingRequired: []
    property var missingOptional: []

    function probe() {
        const required = [];
        const optional = [];
        for (const module of root.modules) {
            let ok = true;
            try {
                const probeObject = Qt.createQmlObject("import " + module.name + "; import QtQuick; QtObject {}", root, "requirements-probe");
                probeObject.destroy();
            } catch (error) {
                ok = false;
            }
            if (!ok)
                (module.required ? required : optional).push(module);
        }
        root.missingRequired = required;
        root.missingOptional = optional;
    }

    // Package names of every missing module, for one distribution.
    function packages(distro) {
        return root.missingRequired.concat(root.missingOptional).map(m => m[distro]).join(" ");
    }

    function requiredPackages(distro) {
        return root.missingRequired.map(m => m[distro]).join(" ");
    }

    // The shell command that installs every missing module, for one family.
    function installCommand(distro) {
        const tools = ({
                deb: "sudo apt install ",
                arch: "sudo pacman -S ",
                fedora: "sudo dnf install "
            });
        const pkgs = root.packages(distro);
        return tools[distro] && pkgs ? tools[distro] + pkgs : "";
    }

    // "$ID $ID_LIKE" from /etc/os-release to one of the three families.
    function familyFromOsRelease(ids) {
        const words = String(ids || "").toLowerCase().split(/\s+/);
        for (const family of [["debian", "ubuntu", "deb"], ["arch", "arch"], ["fedora", "rhel", "centos", "fedora"]]) {
            const target = family[family.length - 1];
            if (words.some(w => family.slice(0, -1).indexOf(w) >= 0))
                return target;
        }
        return "";
    }

    Component.onCompleted: probe()
}
