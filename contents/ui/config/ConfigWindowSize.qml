import QtQuick

// Plasma opens the configuration dialog at a fixed 35 grid units of height,
// which cuts the longer pages. Each page drops this in: the window grows to
// 900 px once, when the screen allows it; the user can still resize it.
Item {
    visible: false

    Component.onCompleted: {
        const window = Window.window;
        if (!window)
            return;
        const wanted = Math.min(900, Screen.desktopAvailableHeight - 60);
        if (window.height < wanted)
            window.height = wanted;
    }
}
