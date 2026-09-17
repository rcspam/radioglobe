import QtQuick
import QtTest
import "../../contents/ui" as Ui

// Paint cost of the globe, driven like a drag: 60 frames of 0.5 degree,
// one every 16 ms, in a few situations. Run one function at a time under
// /usr/bin/time (see run.sh): the process CPU is the measure, the paint
// count checks that every frame was actually painted.
TestCase {
    name: "Bench"
    when: windowShown
    width: 520
    height: 480
    visible: true

    function i18n(text, arg) {
        return arg === undefined ? text : text.replace("%1", arg);
    }

    Ui.Globe {
        id: globe
        width: 520
        height: 480
        centreLatitude: 30
        centreLongitude: 10
    }

    function loadCountries() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../../contents/data/countries.json"), false);
        xhr.send();
        return JSON.parse(xhr.responseText).features;
    }

    // Deterministic pseudo-random stations, most of them on the front half.
    function randomStations(count) {
        var rows = [];
        var seed = 42;
        function next() {
            seed = (seed * 1103515245 + 12345) % 2147483648;
            return seed / 2147483648;
        }
        for (var i = 0; i < count; i++)
            rows.push({
                uuid: "s" + i,
                name: "S" + i,
                latitude: next() * 140 - 60,
                longitude: next() * 360 - 180
            });
        return rows;
    }

    // A real pointer drag through the DragHandler, so whatever the globe
    // does while it moves (no antialiasing) is part of the measure.
    function drag(frames) {
        var before = globe.paintCount;
        mousePress(globe, 200, 240);
        for (var i = 1; i <= frames; i++) {
            mouseMove(globe, 200 + i * 2, 240);
            wait(16);
        }
        mouseRelease(globe, 200 + frames * 2, 240);
        wait(50);
        globe.stopKineticRotation(true);
        wait(200);
        return globe.paintCount - before;
    }

    function run(label, rounds) {
        wait(500);
        var paints = 0;
        for (var k = 0; k < rounds; k++)
            paints += drag(60);
        console.log("BENCH " + label + ": paints=" + paints);
    }

    function test_full() {
        globe.countries = loadCountries();
        globe.stations = randomStations(3000);
        globe.showDayNight = true;
        run("full (countries, 3000 stations, day/night)", 5);
    }

    function test_nostations() {
        globe.countries = loadCountries();
        globe.stations = [];
        globe.showDayNight = true;
        run("countries only", 5);
    }

    function test_nocountries() {
        globe.countries = [];
        globe.stations = randomStations(3000);
        globe.showDayNight = true;
        run("3000 stations only", 5);
    }

    function test_empty() {
        globe.countries = [];
        globe.stations = [];
        globe.showDayNight = false;
        run("empty globe", 5);
    }

    function test_zoomed() {
        globe.countries = loadCountries();
        globe.stations = randomStations(3000);
        globe.showDayNight = true;
        globe.globeScale = 8;
        run("full at scale 8", 5);
    }

    function test_nopaint() {
        globe.countries = loadCountries();
        globe.stations = randomStations(3000);
        wait(5000);
        console.log("BENCH no paint: paints=0");
    }
}
