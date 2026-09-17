import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/RadioModel.js" as RadioModel

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
        globe.stopZoomAnimation();
        globe.centreLatitude = 0;
        globe.centreLongitude = 0;
        globe.globeScale = 1;
        globe.stations = [];
        globe.selectedStation = null;
        globe.highlightedStation = null;
        globe.backgroundColor = "#090a0c";
        globe.sphereColor = "#11151a";
        globe.landColor = "#283039";
        globe.gridColor = "#7d8791";
        globe.outlineColor = "#9099a3";
        globe.signalColor = "#d9dee3";
        // The real Sun would shade half of the pixel tests below.
        globe.showDayNight = false;
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

    // Everything black except the night shade: with the Sun due east of the
    // view centre, the western half of the disc is shaded and the eastern
    // half is not, and turning the option off removes the shade.
    function test_nightSideIsShadedAwayFromTheSun() {
        globe.backgroundColor = "#000000";
        globe.sphereColor = "#000000";
        globe.gridColor = "#000000";
        globe.outlineColor = "#000000";
        globe.signalColor = "#000000";
        globe.nightColor = "#ffffff";
        globe.nightOpacity = 1;
        globe.showDayNight = true;
        globe.sun = {
            latitude: 0,
            longitude: 90
        };
        const centreX = Math.round(globe.width / 2);
        const centreY = Math.round(globe.height / 2);
        const west = Math.round(centreX - globe.radius() / 2);
        const east = Math.round(centreX + globe.radius() / 2);
        tryVerify(function () {
            return Qt.colorEqual(grabImage(globe).pixel(west, centreY), "#ffffff");
        });
        compare(grabImage(globe).pixel(east, centreY).toString(), Qt.rgba(0, 0, 0, 1).toString());

        globe.showDayNight = false;
        tryVerify(function () {
            return Qt.colorEqual(grabImage(globe).pixel(west, centreY), "#000000");
        });
    }

    // Stations are painted after the shade, so a night-side signal keeps its
    // colour instead of being dimmed with the land under it.
    function test_stationsStayOnTopOfTheNightShade() {
        globe.backgroundColor = "#000000";
        globe.sphereColor = "#000000";
        globe.gridColor = "#000000";
        globe.outlineColor = "#000000";
        globe.signalColor = "#ffffff";
        globe.nightColor = "#ff0000";
        globe.nightOpacity = 1;
        globe.showDayNight = true;
        globe.sun = {
            latitude: 0,
            longitude: 180
        };
        globe.stations = [
            {
                uuid: "night",
                latitude: 0,
                longitude: 0
            }
        ];
        const centreX = Math.round(globe.width / 2);
        const centreY = Math.round(globe.height / 2);
        // The dot is white at 87 % over the red veil: green channel high
        // there, zero anywhere the veil is the last thing painted.
        tryVerify(function () {
            return grabImage(globe).pixel(centreX, centreY).g > 0.8;
        });
        compare(grabImage(globe).pixel(centreX, Math.round(centreY - globe.radius() / 2)).toString(), Qt.rgba(1, 0, 0, 1).toString());
    }

    function loadCountries() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../../contents/data/countries.json"), false);
        xhr.send();
        return JSON.parse(xhr.responseText).features;
    }

    // Three detail levels per country, the coarsest picked at scale 1.
    function test_countriesCarryThreeDetailLevels() {
        globe.countries = loadCountries();
        const counts = [0, 0, 0];
        for (const country of globe.preparedCountries)
            for (let level = 0; level < 3; level++)
                for (const ring of country.levels[level])
                    counts[level] += ring.world.length / 3;
        verify(counts[0] < counts[1] && counts[1] < counts[2], "levels " + counts.join(" "));
        verify(counts[0] < counts[2] / 2, "coarsest level keeps less than half: " + counts.join(" "));
        globe.globeScale = 1;
        compare(globe.detailLevel(), 0);
        globe.globeScale = 4;
        compare(globe.detailLevel(), 1);
        globe.globeScale = 16;
        compare(globe.detailLevel(), 2);
        globe.countries = [];
    }

    // Away from the borders the simplified land looks exactly like the full
    // one: centre of a large country and open sea.
    function test_simplifiedCountriesMatchTheFullOnesAwayFromBorders() {
        globe.landColor = "#ff0000";
        globe.sphereColor = "#000000";
        globe.backgroundColor = "#000000";
        globe.gridColor = "#000000";
        globe.outlineColor = "#000000";
        globe.centreLatitude = 20;
        globe.centreLongitude = 20;
        globe.countries = loadCountries();
        const samples = [
            [400, 300], // centre of the view, in the Sahara
            [400 + globe.radius() * 0.55, 300 + globe.radius() * 0.25], // Indian Ocean
            [400 - globe.radius() * 0.6, 300 - globe.radius() * 0.1] // Atlantic
        ];
        function pixels() {
            const image = grabImage(globe);
            return samples.map(s => image.pixel(Math.round(s[0]), Math.round(s[1])).toString());
        }
        wait(100);
        const simplified = pixels();
        verify(grabImage(globe).pixel(400, 300).r > 0.8, "Sahara is land: " + simplified[0]);
        verify(simplified[1] === Qt.rgba(0, 0, 0, 1).toString(), "Indian Ocean is sea: " + simplified[1]);
        globe.detailTolerances = [0, 0, 0];
        globe.countries = loadCountries();
        wait(100);
        compare(pixels(), simplified);
        globe.detailTolerances = [0.35, 0.1, 0];
        globe.countries = [];
    }

    // The shaded disc does not depend on the rotation: its own canvas is
    // painted on size, scale and colour changes only.
    function test_sphereLayerIgnoresRotation() {
        wait(120);
        const before = globe.spherePaintCount;
        globe.centreLongitude = 45;
        globe.centreLatitude = 10;
        wait(120);
        compare(globe.spherePaintCount, before);
        globe.globeScale = 2;
        tryVerify(function () {
            return globe.spherePaintCount > before;
        });
        const afterScale = globe.spherePaintCount;
        globe.sphereColor = "#123456";
        tryVerify(function () {
            return globe.spherePaintCount > afterScale;
        });
    }

    // What the two layers compose: background colour outside the disc, the
    // sphere colour inside where nothing else is painted.
    function test_sphereLayerShowsThroughTheGlobeCanvas() {
        globe.backgroundColor = "#00ff00";
        globe.sphereColor = "#0000ff";
        globe.gridColor = "#0000ff";
        globe.outlineColor = "#0000ff";
        globe.countries = [];
        globe.stations = [];
        tryVerify(function () {
            return Qt.colorEqual(grabImage(globe).pixel(2, 2), "#00ff00");
        });
        const centre = grabImage(globe).pixel(Math.round(globe.width / 2), Math.round(globe.height / 2));
        // The gradient lightens the centre, so the check is "blue dominates".
        verify(centre.b > 0.5 && centre.b > centre.g + 0.3, "inside the disc the sphere shows: " + centre);
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
        verify(elapsed < 16, "the burst itself took " + elapsed + " ms, longer than the throttle window");
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

        // Sixty changes spread over 400 ms: at most one paint per 16 ms.
        const start = globe.paintCount;
        for (let j = 0; j < 60; j++) {
            globe.centreLongitude = j * 0.1;
            wait(6);
        }
        wait(60);
        verify(globe.paintCount - start <= 26, "expected at most 26 paints in 400 ms, got " + (globe.paintCount - start));
    }

    // spreadOverlapping puts duplicates 0.08 degrees apart: at scale 24 that
    // is under the 12 px hit radius, so the ceiling has to sit higher.
    function test_wheelZoomStepAndCeiling() {
        mouseWheel(globe, 400, 300, 0, 120);
        fuzzyCompare(globe.globeScale, Math.exp(120 / 360), 0.001);
        for (var i = 0; i < 60; i++)
            mouseWheel(globe, 400, 300, 0, 120);
        compare(globe.globeScale, 1024);
    }

    function test_zoomButtonsStepByTwoAndAnimate() {
        globe.zoomIn();
        verify(globe.globeScale < 2, "animated, not jumped: " + globe.globeScale);
        tryCompare(globe, "globeScale", 2);
        globe.zoomOut();
        tryCompare(globe, "globeScale", 1);
    }

    // The centre stays where it is: a button zoom has no cursor to anchor.
    function test_zoomButtonsKeepTheCentre() {
        globe.centreLatitude = 40;
        globe.centreLongitude = -3;
        globe.zoomIn();
        tryCompare(globe, "globeScale", 2);
        compare(globe.centreLatitude, 40);
        compare(globe.centreLongitude, -3);
    }

    function test_zoomButtonsStopAtTheLimits() {
        globe.globeScale = globe.maximumScale;
        verify(!globe.canZoomIn);
        verify(globe.canZoomOut);
        globe.zoomIn();
        wait(250);
        compare(globe.globeScale, globe.maximumScale);

        globe.globeScale = globe.minimumScale;
        verify(globe.canZoomIn);
        verify(!globe.canZoomOut);
        globe.zoomOut();
        wait(250);
        compare(globe.globeScale, globe.minimumScale);
    }

    // Two quick clicks compound: the second starts from the first's target.
    function test_zoomButtonsQueueFromTheTarget() {
        globe.zoomIn();
        globe.zoomIn();
        tryCompare(globe, "globeScale", 4);
    }

    function test_wheelInterruptsTheButtonZoom() {
        globe.zoomIn();
        mouseWheel(globe, 400, 300, 0, -120);
        const afterWheel = globe.globeScale;
        wait(250);
        compare(globe.globeScale, afterWheel);
        verify(afterWheel < 2, "the animation did not carry on to 2: " + afterWheel);
    }

    function test_wheelZoomKeepsThePointUnderTheCursor() {
        var radius = globe.radius();
        var anchor = RadioModel.unproject((560 - 400) / radius, -(210 - 300) / radius, 0, 0);
        for (var i = 0; i < 20; i++)
            mouseWheel(globe, 560, 210, 0, 120);
        verify(globe.globeScale > 500, "reached a deep zoom: " + globe.globeScale);
        var position = RadioModel.stationPosition(anchor, globe.width, globe.height, globe.globeScale, globe.centreLatitude, globe.centreLongitude);
        verify(Math.abs(position.x - 560) < 1 && Math.abs(position.y - 210) < 1, JSON.stringify(position));
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
