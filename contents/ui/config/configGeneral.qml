import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_maxWorldStations: maxStations.value
    property alias cfg_mpvPath: mpvPath.text
    property alias cfg_sendClicks: sendClicks.checked

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
            placeholderText: i18n("Leave empty to use mpv from PATH")
        }
        QQC2.CheckBox {
            id: sendClicks
            Kirigami.FormData.label: i18n("Radio Browser:")
            text: i18n("Report played stations to the click counter")
        }
    }
}
