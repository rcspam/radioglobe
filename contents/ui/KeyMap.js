.pragma library

// Maps key presses to player / list actions. Pure so it can be unit-tested;
// `targets` supplies the callbacks. Returns true when the key was handled.
function handle(targets, key, text) {
    switch (key) {
    case Qt.Key_Slash:
        targets.focusSearch();
        return true;
    case Qt.Key_Down:
        targets.moveSelection(1);
        return true;
    case Qt.Key_Up:
        targets.moveSelection(-1);
        return true;
    case Qt.Key_Return:
    case Qt.Key_Enter:
        targets.activateSelected();
        return true;
    case Qt.Key_Space:
        targets.togglePause();
        return true;
    case Qt.Key_R:
        targets.random();
        return true;
    case Qt.Key_F:
        targets.favorite();
        return true;
    case Qt.Key_Plus:
    case Qt.Key_Equal:
        targets.volumeStep(0.05);
        return true;
    case Qt.Key_Minus:
        targets.volumeStep(-0.05);
        return true;
    case Qt.Key_M:
        targets.mute();
        return true;
    case Qt.Key_Escape:
        targets.escape();
        return true;
    default:
        return false;
    }
}
