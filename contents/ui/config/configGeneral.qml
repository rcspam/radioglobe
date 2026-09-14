import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import ".." as Ui
import "../RadioModel.js" as RadioModel

KCM.SimpleKCM {
    id: page

    property alias cfg_maxWorldStations: maxStations.value
    property alias cfg_mpvPath: mpvPath.text
    property alias cfg_sendClicks: sendClicks.checked

    readonly property string checkingText: i18n("Checking…")
    readonly property string unknownText: i18n("Could not check (the command did not return). Try again.")

    property string mpvStatus: checkingText
    property string mprisStatus: checkingText

    Ui.Exec {
        id: exec
    }

    Timer {
        id: probeTimeout
        interval: 5000
        onTriggered: {
            if (page.mpvStatus === page.checkingText)
                page.mpvStatus = page.unknownText;
            if (page.mprisStatus === page.checkingText)
                page.mprisStatus = page.unknownText;
        }
    }

    function probe() {
        page.mpvStatus = page.checkingText;
        page.mprisStatus = page.checkingText;
        probeTimeout.restart();
        const binary = mpvPath.text.trim() || "mpv";
        exec.run("command -v " + RadioModel.shellQuote(binary), (code, out) => {
            page.mpvStatus = code === 0 ? i18n("Found: %1", out.trim()) : i18n("Not found. Install the “mpv” package.");
        });
        exec.run("for f in /etc/mpv/scripts/mpris.so /usr/lib/mpv-mpris/mpris.so /usr/lib64/mpv-mpris/mpris.so /usr/lib/x86_64-linux-gnu/mpv-mpris/mpris.so \"$HOME/.config/mpv/scripts/mpris.so\"; do [ -e \"$f\" ] && echo \"$f\" && exit 0; done; exit 1", (code, out) => {
            page.mprisStatus = code === 0 ? i18n("Found: %1", out.trim()) : i18n("Not found. Install the “mpv-mpris” package (media keys and the Media Player widget need it).");
        });
    }

    Component.onCompleted: probe()

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: maxStations
            Kirigami.FormData.label: i18n("Maximum stations on the globe:")
            from: 500
            to: 12000
            stepSize: 500
        }
        QQC2.TextField {
            id: mpvPath
            Kirigami.FormData.label: i18n("mpv executable:")
            placeholderText: i18n("Absolute path, or leave empty to use mpv from PATH")
            onEditingFinished: page.probe()
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("mpv:")
            text: page.mpvStatus
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        QQC2.Label {
            Kirigami.FormData.label: i18n("mpv-mpris:")
            text: page.mprisStatus
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: i18n("Check again")
            icon.name: "view-refresh"
            onClicked: page.probe()
        }
        QQC2.CheckBox {
            id: sendClicks
            Kirigami.FormData.label: i18n("Radio Browser:")
            text: i18n("Report played stations to the click counter")
        }
    }
}
