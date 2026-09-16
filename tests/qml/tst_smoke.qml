import QtQuick
import QtTest

TestCase {
    name: "Smoke"

    function i18n(text) {
        return text;
    }

    // Player has its own "exec" property: inside its block a bare "exec" is
    // that property, not the root's object. main.qml must qualify it.
    function test_main_qualifies_the_exec_handed_to_the_player() {
        const source = String(readFile("../../contents/ui/main.qml"));
        verify(source.indexOf("exec: root.exec.run") >= 0, "Player must get root.exec.run");
        verify(source.indexOf("\n        exec: exec.run") < 0, "unqualified exec.run inside Player");
    }

    function readFile(relative) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(relative), false);
        xhr.send();
        return xhr.responseText;
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

    // An empty home country falls back to the country of the user's locale,
    // which the placeholder advertises. Radio Browser only knows upper case
    // ISO codes, so whatever the user types is normalised.
    function test_home_country_field_follows_the_locale_and_upper_cases() {
        const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/config/configGeneral.qml"));
        compare(component.status, Component.Ready, component.errorString());
        const page = component.createObject(null);
        verify(page !== null, component.errorString());
        compare(page.localeCountry, Qt.locale().name.split("_")[1] || "");
        const field = findChild(page, "homeCountry");
        verify(field !== null, "homeCountry not found");
        compare(field.maximumLength, 2);
        field.text = "fr";
        field.editingFinished();
        compare(page.cfg_homeCountry, "FR");
        page.destroy();
    }
}
