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
}
