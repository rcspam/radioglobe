import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

// The sleep timer's button and menu. The button stays lit while a timer runs,
// and its tooltip says when playback stops.
PlasmaComponents3.ToolButton {
    id: button

    // SleepTimer.qml.
    property var timer: null
    // The window the button lives in, for keeping the menu inside it.
    readonly property var hostWindow: Window.window

    readonly property bool timerActive: button.timer ? button.timer.active : false
    readonly property string stopTime: button.timerActive ? new Date(button.timer.deadline).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : ""
    readonly property string toolTipText: {
        if (!button.timerActive)
            return i18n("Sleep timer");
        if (button.timer.fading)
            return i18n("Sleep timer: fading out");
        return i18n("Sleep timer: stops at %1, %2 left", button.stopTime, button.formatMinutes(Math.ceil(button.timer.remainingMs / 60000)));
    }

    // 45 -> "45 min", 60 -> "1 h", 90 -> "1 h 30".
    function formatMinutes(minutes) {
        if (minutes < 60)
            return i18n("%1 min", minutes);
        const hours = Math.floor(minutes / 60);
        const rest = minutes % 60;
        return rest === 0 ? i18n("%1 h", hours) : i18n("%1 h %2", hours, String(rest).padStart(2, "0"));
    }

    // The owner calls this when the widget's popup closes, like the filter
    // menu's.
    function close() {
        sleepPopup.close();
    }

    icon.name: "chronometer"
    highlighted: button.timerActive
    // A second click closes the menu: it does not close on a press over its
    // parent (closePolicy below), so this sees it still open.
    onClicked: {
        if (sleepPopup.visible)
            sleepPopup.close();
        else
            sleepPopup.open();
    }
    Accessible.name: button.toolTipText
    PlasmaComponents3.ToolTip.text: button.toolTipText
    PlasmaComponents3.ToolTip.visible: hovered && !sleepPopup.visible

    component DurationItem: PlasmaComponents3.MenuItem {
        required property int minutes
        objectName: "sleep-" + minutes
        Layout.fillWidth: true
        text: button.formatMinutes(minutes)
        onTriggered: {
            button.timer.armFor(minutes);
            sleepPopup.close();
        }
    }

    // A Popup, not a Menu: a Menu takes the keyboard for its own navigation
    // and closes on the first entry, and the end time is typed in a field.
    // Same behaviour as the filter menu otherwise.
    PlasmaComponents3.Popup {
        id: sleepPopup
        objectName: "sleepPopup"
        parent: button
        focus: true
        onAboutToShow: sleepPopup.place()
        function place() {
            const origin = button.mapToItem(null, 0, 0);
            const window = button.hostWindow;
            const windowWidth = window ? window.width : Infinity;
            const windowHeight = window ? window.height : Infinity;
            let wantedX = button.width - sleepPopup.width;
            if (origin.x + wantedX < 0)
                wantedX = -origin.x;
            let wantedY = button.height;
            if (origin.y + wantedY + sleepPopup.height > windowHeight)
                wantedY = Math.max(-origin.y, windowHeight - sleepPopup.height - origin.y);
            sleepPopup.x = Math.round(Math.min(wantedX, windowWidth - sleepPopup.width - origin.x));
            sleepPopup.y = Math.round(wantedY);
        }
        property int leaveDelayMs: 400
        closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutsideParent

        // A time half typed keeps the menu open whatever the pointer does.
        readonly property bool held: menuHover.hovered || button.hovered || timeField.text !== ""
        onHeldChanged: {
            if (sleepPopup.held)
                leaveTimer.stop();
            else if (sleepPopup.visible)
                leaveTimer.restart();
        }
        onClosed: {
            leaveTimer.stop();
            timeField.text = "";
        }

        HoverHandler {
            id: menuHover
        }
        Timer {
            id: leaveTimer
            interval: sleepPopup.leaveDelayMs
            onTriggered: if (!sleepPopup.held)
                sleepPopup.close()
        }

        contentItem: ColumnLayout {
            spacing: 0

            PlasmaComponents3.MenuItem {
                Layout.fillWidth: true
                text: i18n("Stop playback in")
                enabled: false
            }
            DurationItem {
                minutes: 15
            }
            DurationItem {
                minutes: 30
            }
            DurationItem {
                minutes: 45
            }
            DurationItem {
                minutes: 60
            }
            DurationItem {
                minutes: 90
            }
            DurationItem {
                minutes: 120
            }
            PlasmaComponents3.MenuSeparator {
                Layout.fillWidth: true
            }
            PlasmaComponents3.MenuItem {
                Layout.fillWidth: true
                text: i18n("Stop playback at")
                enabled: false
            }
            // Enter arms it. A time already gone today means tomorrow. No
            // validator: one drops the keystrokes it refuses, and "25:00"
            // would quietly become "2:00". The text turns red instead.
            PlasmaComponents3.TextField {
                id: timeField
                objectName: "sleepTime"
                readonly property var time: button.timer ? button.timer.parseTime(text) : null
                // The text before the edit being handled: Qt emits
                // textEdited before textChanged.
                property string shownText: ""
                onTextChanged: shownText = text
                onTextEdited: {
                    const completed = button.timer.completeTime(shownText, text);
                    if (completed !== text)
                        text = completed;
                }
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                Layout.rightMargin: Kirigami.Units.smallSpacing * 2
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                placeholderText: i18n("hh:mm")
                inputMethodHints: Qt.ImhPreferNumbers
                color: text === "" || time ? Kirigami.Theme.textColor : Kirigami.Theme.negativeTextColor
                onAccepted: {
                    if (!time)
                        return;
                    button.timer.armUntil(time.hour, time.minute);
                    sleepPopup.close();
                }
            }
            PlasmaComponents3.MenuSeparator {
                Layout.fillWidth: true
                visible: button.timerActive
            }
            PlasmaComponents3.MenuItem {
                objectName: "sleepCancel"
                Layout.fillWidth: true
                visible: button.timerActive
                icon.name: "dialog-cancel"
                text: i18n("Cancel (stops at %1)", button.stopTime)
                onTriggered: {
                    button.timer.cancel();
                    sleepPopup.close();
                }
            }
        }
    }
}
