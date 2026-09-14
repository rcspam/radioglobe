import QtQuick
import QtTest

TestCase {
    name: "Smoke"

    function i18n(text) {
        return text;
    }

    function test_config_page_compiles() {
        const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/config/configGeneral.qml"));
        compare(component.status, Component.Ready, component.errorString());
    }

    // RadioModel merges at most 5500 rows into the world, so offering more
    // than that in the settings page would promise stations that never come.
    function test_world_cap_stays_within_what_the_merge_can_hold() {
        const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/config/configGeneral.qml"));
        compare(component.status, Component.Ready, component.errorString());
        const page = component.createObject(null);
        verify(page !== null, component.errorString());
        const spin = findChild(page, "maxStations");
        verify(spin !== null, "maxStations not found");
        compare(spin.from, 500);
        compare(spin.to, 5000);
        page.destroy();
    }
}
