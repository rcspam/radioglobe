import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Globe"
    when: windowShown
    width: 800
    height: 600
    visible: true

    function i18n(text, arg) {
        return arg === undefined ? text : text.replace("%1", arg);
    }

    Ui.Globe {
        id: globe
        width: 800
        height: 600
    }

    SignalSpy {
        id: selectionChanges
        target: globe
        signalName: "selectedStationUuidChanged"
    }

    function init() {
        globe.centreLatitude = 0;
        globe.centreLongitude = 0;
        globe.globeScale = 1;
        globe.stations = [];
        globe.selectedStation = null;
        globe.highlightedStation = null;
        selectionChanges.clear();
    }

    function test_statusUpdatePreservesLandingHighlight() {
        globe.selectedStation = {
            uuid: "playing",
            name: "Radio",
            latitude: 0,
            longitude: 0
        };
        globe.highlightedStation = {
            uuid: "landing",
            latitude: 0,
            longitude: 5
        };
        selectionChanges.clear();

        globe.selectedStation = {
            uuid: "playing",
            name: "Updated metadata",
            latitude: 0,
            longitude: 0
        };
        compare(selectionChanges.count, 0);
        compare(globe.highlightedStation.uuid, "landing");

        globe.selectedStation = {
            uuid: "different",
            latitude: 0,
            longitude: 10
        };
        compare(selectionChanges.count, 1);
        compare(globe.highlightedStation, null);
    }

    function test_themeChangeRepaintsWithoutInteraction() {
        globe.backgroundColor = "#000000";
        tryVerify(function () {
            return Qt.colorEqual(grabImage(globe).pixel(2, 2), "#000000");
        });
        globe.backgroundColor = "#ffffff";
        tryVerify(function () {
            return Qt.colorEqual(grabImage(globe).pixel(2, 2), "#ffffff");
        });
    }

    // The depth buckets share one beginPath/fill per bucket: a missing fill or
    // a stray closePath would silently paint nothing at all.
    function test_bucketedDotsReachTheCanvas() {
        // Everything but the dots painted black: the grid lines cross exactly
        // at the centre of the globe.
        globe.backgroundColor = "#000000";
        globe.sphereColor = "#000000";
        globe.gridColor = "#000000";
        globe.outlineColor = "#000000";
        globe.signalColor = "#ffffff";
        const centreX = Math.round(globe.width / 2);
        const centreY = Math.round(globe.height / 2);
        tryVerify(function () {
            return grabImage(globe).pixel(centreX, centreY).toString() === Qt.rgba(0, 0, 0, 1).toString();
        });
        globe.stations = [
            {
                uuid: "dot",
                latitude: 0,
                longitude: 0
            }
        ];
        tryVerify(function () {
            return grabImage(globe).pixel(centreX, centreY).toString() !== Qt.rgba(0, 0, 0, 1).toString();
        });
        globe.gridColor = "#7d8791";
        globe.outlineColor = "#9099a3";
        globe.signalColor = "#d9dee3";
    }

    function test_offscreenMarkersAreSkippedButEdgeMarkersRemainClickable() {
        globe.globeScale = 3;
        var edgeLongitude = Math.asin((-6 - globe.width / 2) / globe.radius()) * 180 / Math.PI;
        var edge = {
            uuid: "edge",
            latitude: 0,
            longitude: edgeLongitude
        };
        globe.stations = [
            {
                uuid: "centre",
                latitude: 0,
                longitude: 0
            },
            {
                uuid: "offscreen",
                latitude: 0,
                longitude: 60
            },
            {
                uuid: "back",
                latitude: 0,
                longitude: 180
            },
            edge];
        globe.selectedStation = edge;
        var arcs = [];
        var context = {
            beginPath: function () {},
            moveTo: function () {},
            arc: function (x, y, radius) {
                arcs.push({
                    x: x,
                    y: y,
                    radius: radius
                });
            },
            fill: function () {},
            stroke: function () {}
        };
        globe.paintSignals(context);
        // The plain dot goes through the depth buckets, the selected marker
        // and its halo are still drawn one path each, on top.
        compare(arcs.length, 3);
        compare(arcs[1].radius, 4.2);
        compare(arcs[2].radius, 8.5);
        compare(globe.stationUnderPointer(0, globe.height / 2).uuid, "edge");
        compare(globe.stationUnderPointer(globe.width / 2, globe.height / 2).uuid, "centre");

        globe.centreLongitude = 180;
        globe.paintSignals(context);
        compare(globe.stationUnderPointer(globe.width / 2, globe.height / 2).uuid, "back");
    }
}
