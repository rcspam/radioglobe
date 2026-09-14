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

    // A missing fill or a stray closePath in the dot loop would silently paint
    // nothing at all.
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

    // A depth bucket only picks the fill colour: every dot is still stroked as
    // its own beginPath/arc/fill. Batching a bucket into a single path gives
    // that path the whole globe as a bounding box, which the raster engine
    // scan-converts in full, and a missing moveTo would paint the polygon the
    // arcs enclose: verified, the centre of this ring turned #dedede.
    function test_eachDotGetsItsOwnFill() {
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

        // The same property at the call level: one closed path per dot.
        let beginPaths = 0;
        let arcs = 0;
        let fills = 0;
        const context = {
            beginPath: function () {
                beginPaths += 1;
            },
            moveTo: function () {},
            arc: function () {
                arcs += 1;
            },
            fill: function () {
                fills += 1;
            },
            stroke: function () {}
        };
        globe.paintSignals(context);
        compare(arcs, ring.length);
        compare(beginPaths, arcs);
        compare(fills, arcs);
    }

    // Threaded canvas: onPaint is re-run on the GUI thread at every frame of
    // the render loop, without waiting for the worker to hand back the previous
    // pass, so a burst of changes must leave with a single request.
    function test_rapidChangesCoalesceIntoOnePaint() {
        globe.stations = [
            {
                uuid: "dot",
                latitude: 0,
                longitude: 0
            }
        ];
        // Long enough for the throttle window opened by init() to close.
        wait(120);
        const before = globe.paintCount;
        const burst = 12;
        const started = Date.now();
        for (let i = 0; i < burst; i++)
            globe.centreLongitude = i * 0.05;
        const elapsed = Date.now() - started;
        verify(elapsed < 8, "the burst itself took " + elapsed + " ms, longer than the throttle window");
        // The first change sent the request, the other eleven were merged into
        // the single re-issue the throttle fires at the end of its window.
        verify(globe.paintDirty, "changes inside the window must be merged, not requested one by one");
        tryVerify(function () {
            return globe.paintCount > before;
        });
        // The merged state is not dropped: the window closes on a re-issue.
        tryVerify(function () {
            return !globe.paintDirty;
        });
        wait(120);
        verify(globe.paintCount - before <= 2, "expected at most 2 paints for " + burst + " changes, got " + (globe.paintCount - before));
    }

    // spreadOverlapping puts duplicates 0.08 degrees apart: at scale 24 that
    // is under the 12 px hit radius, so the ceiling has to sit higher.
    function test_wheelZoomStepAndCeiling() {
        mouseWheel(globe, 400, 300, 0, 120);
        fuzzyCompare(globe.globeScale, Math.exp(120 / 360), 0.001);
        for (var i = 0; i < 60; i++)
            mouseWheel(globe, 400, 300, 0, 120);
        compare(globe.globeScale, 256);
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
