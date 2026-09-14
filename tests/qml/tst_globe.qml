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
        globe.backgroundColor = "#090a0c";
        globe.sphereColor = "#11151a";
        globe.gridColor = "#7d8791";
        globe.outlineColor = "#9099a3";
        globe.signalColor = "#d9dee3";
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
    }

    // Every dot of a depth bucket goes into one path closed by a single fill.
    // Without the moveTo before each arc, the arcs are chained by a straight
    // line and the fill paints the polygon they enclose: verified, the centre
    // of this ring turns from black to #dedede when the moveTo is removed.
    function test_bucketedDotsAreNotJoinedIntoOneBlob() {
        globe.backgroundColor = "#000000";
        globe.sphereColor = "#000000";
        globe.gridColor = "#000000";
        globe.outlineColor = "#000000";
        globe.signalColor = "#ffffff";
        // A ring of eight dots 12 degrees off the centre: same distance from
        // the viewer, so the same depth bucket, and empty sky in the middle.
        const ring = [];
        for (let i = 0; i < 8; i++)
            ring.push({
                uuid: "d" + i,
                latitude: 12 * Math.sin(i * Math.PI / 4),
                longitude: 12 * Math.cos(i * Math.PI / 4)
            });
        globe.stations = ring;
        const centreX = Math.round(globe.width / 2);
        const centreY = Math.round(globe.height / 2);
        tryVerify(function () {
            return grabImage(globe).pixel(centreX, centreY).toString() === Qt.rgba(0, 0, 0, 1).toString();
        });

        // The same property at the call level: one moveTo per arc of a bucket.
        let moveTos = 0;
        let arcs = 0;
        const context = {
            beginPath: function () {},
            moveTo: function () {
                moveTos += 1;
            },
            arc: function () {
                arcs += 1;
            },
            fill: function () {},
            stroke: function () {}
        };
        globe.paintSignals(context);
        compare(arcs, ring.length);
        compare(moveTos, arcs);
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
