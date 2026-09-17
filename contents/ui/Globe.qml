import QtQuick
import "RadioModel.js" as RadioModel

// Adapted from Radio Atlas (MIT, Akshar Patel). Colours are plain properties
// so the caller binds them to Kirigami.Theme; this file stays theme-agnostic.
Item {
    id: root

    property var countries: []
    property var stations: []
    property var selectedStation: null
    readonly property string selectedStationUuid: selectedStation ? String(selectedStation.uuid || "") : ""
    readonly property real stationHitRadius: 12
    property string activeCountryCode: ""

    property real centreLatitude: 18
    property real centreLongitude: -20
    property real globeScale: 1
    property real minimumScale: 0.72
    // Dense cities (Paris, London) pack stations a few thousandths of a
    // degree apart: 0.003 degrees is 14 px at scale 1024 on a 600 px globe,
    // just over the hit radius, so that is where they stop overlapping.
    property real maximumScale: 1024
    property real longitudeSensitivity: 0.22
    property real latitudeSensitivity: 0.18
    readonly property real kineticLaunchSpeed: 120
    readonly property real kineticMaximumSpeed: 2400
    readonly property real kineticDeceleration: 1800
    readonly property real kineticMaximumFrameTime: 0.1
    readonly property real kineticMaximumSampleAge: 100

    property color backgroundColor: "#090a0c"
    property color sphereColor: "#11151a"
    property color landColor: "#283039"
    property color gridColor: "#7d8791"
    property color outlineColor: "#9099a3"
    property color signalColor: "#d9dee3"
    property color accentColor: "#ff8a3d"
    property color textColor: "#f3f4f5"
    property string fontFamily: "monospace"

    // Night side of the Earth, shaded from the Sun's current position. The
    // sun is refreshed every minute while the globe is visible; tests set it.
    property bool showDayNight: true
    property color nightColor: "#000000"
    property real nightOpacity: 0.45
    property var sun: RadioModel.subsolarPoint(new Date())

    property var hoveredStation: null
    property real hoverX: 0
    property real hoverY: 0
    property var highlightedStation: null
    property real highlightX: 0
    property real highlightY: 0
    property real kineticVelocityX: 0
    property real kineticVelocityY: 0
    property int kineticLaunchGeneration: 0
    property bool suppressNextTap: false
    property var preparedCountries: []
    property var preparedGrid: []
    property var preparedStations: []
    readonly property int signalDepthBuckets: 8
    property bool paintDirty: false
    readonly property alias paintCount: paintCounter.value

    signal stationActivated(var station)
    signal countryActivated(string code, string name)
    signal interactionStarted
    signal pointerMoved

    Accessible.name: "Interactive world radio globe"
    Accessible.description: "Drag or flick to rotate, use the mouse wheel to zoom, and select a station signal or country"
    Accessible.role: Accessible.Pane

    function radius() {
        return Math.min(width, height) * 0.44 * globeScale;
    }

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }

    // A Threaded canvas runs the JS of onPaint on the GUI thread again at every
    // frame of the render loop, without waiting for the worker to be done with
    // the previous pass. At 240 Hz that is four painting passes computed and
    // thrown away for every texture the eye actually gets, and the GUI thread
    // ends up saturated, so drags and list scrolling stutter. Requests are
    // capped at one per 16 ms (60 frames per second is plenty for a drag)
    // and the ones arriving in between are merged.
    function schedulePaint() {
        if (paintThrottle.running) {
            paintDirty = true;
            return;
        }
        paintDirty = false;
        globeCanvas.requestPaint();
        paintThrottle.restart();
    }

    function clearLandingHighlight() {
        highlightedStation = null;
        highlightX = 0;
        highlightY = 0;
    }

    function stopKineticRotation(clearLanding) {
        kineticLaunchGeneration += 1;
        kineticAnimation.running = false;
        kineticVelocityX = 0;
        kineticVelocityY = 0;
        if (clearLanding === true)
            clearLandingHighlight();
    }

    function startKineticRotation(velocityX, velocityY) {
        var launch = RadioModel.kineticLaunchVelocity(velocityX, velocityY, kineticLaunchSpeed, kineticMaximumSpeed);
        if (!launch.active)
            return false;

        kineticLaunchGeneration += 1;
        clearLandingHighlight();
        hoveredStation = null;
        kineticVelocityX = launch.x;
        kineticVelocityY = launch.y;
        kineticAnimation.running = true;
        return true;
    }

    function finishKineticRotation() {
        kineticAnimation.running = false;
        kineticVelocityX = 0;
        kineticVelocityY = 0;
        hoveredStation = null;
        var excludedUuid = selectedStation ? selectedStation.uuid : "";
        highlightedStation = RadioModel.nearestVisibleStation(stations, centreLatitude, centreLongitude, excludedUuid, width, height, globeScale);
    }

    function rotateByPointerDelta(deltaX, deltaY) {
        centreLongitude = RadioModel.wrapLongitude(centreLongitude - deltaX * longitudeSensitivity / globeScale);
        centreLatitude = RadioModel.clamp(centreLatitude + deltaY * latitudeSensitivity / globeScale, -78, 78);
    }

    function stationByUuid(uuid) {
        var wanted = String(uuid || "");
        var rows = Array.isArray(stations) ? stations : [];
        for (var i = 0; i < rows.length; i++)
            if (String(rows[i] && rows[i].uuid || "") === wanted)
                return rows[i];
        return null;
    }

    function refreshLandingHighlight() {
        if (!highlightedStation)
            return;
        var replacement = stationByUuid(highlightedStation.uuid);
        if (!replacement) {
            clearLandingHighlight();
            return;
        }
        highlightedStation = replacement;
        updateHighlightPosition();
    }

    function updateHighlightPosition() {
        if (!highlightedStation)
            return;
        var position = RadioModel.stationPosition(highlightedStation, width, height, globeScale, centreLatitude, centreLongitude);
        if (!position) {
            clearLandingHighlight();
            return;
        }
        highlightX = position.x;
        highlightY = position.y;
    }

    // Button zoom: a short animation of the scale about the current centre.
    // A second click before the first lands starts from the first's target,
    // so clicks compound; any wheel, drag or focus cuts the animation short.
    readonly property real zoomStep: 2
    readonly property real zoomTarget: zoomAnimation.running ? zoomAnimation.to : globeScale
    readonly property bool canZoomIn: zoomTarget < maximumScale - 0.001
    readonly property bool canZoomOut: zoomTarget > minimumScale + 0.001

    function stopZoomAnimation() {
        zoomAnimation.stop();
    }

    function zoomBy(factor) {
        interactionStarted();
        stopKineticRotation(true);
        suppressNextTap = false;
        hoveredStation = null;
        var target = RadioModel.clamp(zoomTarget * factor, minimumScale, maximumScale);
        if (Math.abs(target - globeScale) < 0.001)
            return;
        zoomAnimation.stop();
        zoomAnimation.from = globeScale;
        zoomAnimation.to = target;
        zoomAnimation.start();
    }

    function zoomIn() {
        zoomBy(zoomStep);
    }

    function zoomOut() {
        zoomBy(1 / zoomStep);
    }

    function focusCoordinate(latitude, longitude) {
        var nextLatitude = Number(latitude);
        var nextLongitude = Number(longitude);
        if (!isFinite(nextLatitude) || !isFinite(nextLongitude))
            return;
        stopKineticRotation(true);
        stopZoomAnimation();
        centreLatitude = RadioModel.clamp(nextLatitude, -78, 78);
        centreLongitude = RadioModel.wrapLongitude(nextLongitude);
    }

    function focusCountry(code) {
        var coordinate = RadioModel.countryCentre(countries, code);
        if (coordinate)
            focusCoordinate(coordinate.latitude, coordinate.longitude);
    }

    function prepareCoordinates(coordinates, latitudeFirst) {
        var output = [];
        if (!Array.isArray(coordinates))
            return output;
        for (var i = 0; i < coordinates.length; i++) {
            var latitude = Number(coordinates[i][latitudeFirst ? 0 : 1]) * Math.PI / 180;
            var longitude = Number(coordinates[i][latitudeFirst ? 1 : 0]) * Math.PI / 180;
            if (!isFinite(latitude) || !isFinite(longitude))
                continue;
            var cosLatitude = Math.cos(latitude);
            output.push(cosLatitude * Math.cos(longitude), cosLatitude * Math.sin(longitude), Math.sin(latitude));
        }
        return output;
    }

    // Douglas-Peucker tolerances, in degrees, of the three detail levels a
    // country is prepared at. At scale 1 a degree is under 4 px, so the
    // coarsest level (40 % of the points) draws the same picture.
    property var detailTolerances: [0.35, 0.1, 0]

    function detailLevel() {
        return globeScale < 2.5 ? 0 : (globeScale < 10 ? 1 : 2);
    }

    function prepareCountryGeometry() {
        var output = [];
        var rows = Array.isArray(countries) ? countries : [];
        for (var i = 0; i < rows.length; i++) {
            var feature = rows[i];
            if (!feature || !feature.geometry)
                continue;
            var geometry = feature.geometry;
            var polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates;
            if (!Array.isArray(polygons))
                continue;
            var levels = [];
            for (var level = 0; level < detailTolerances.length; level++) {
                var rings = [];
                for (var p = 0; p < polygons.length; p++) {
                    var ring = polygons[p] && polygons[p][0];
                    var prepared = prepareCoordinates(RadioModel.simplifyRing(ring, detailTolerances[level]), false);
                    if (prepared.length >= 9)
                        rings.push({
                            world: prepared,
                            projected: new Array(prepared.length)
                        });
                }
                levels.push(rings);
            }
            if (levels[levels.length - 1].length === 0)
                continue;
            output.push({
                code: String(feature.properties && feature.properties.code || "").toUpperCase(),
                levels: levels,
                rings: levels[levels.length - 1]
            });
        }
        return output;
    }

    function prepareGridGeometry() {
        var output = [];
        for (var latitude = -60; latitude <= 60; latitude += 30) {
            var parallel = [];
            for (var longitude = -180; longitude <= 180; longitude += 6)
                parallel.push([latitude, longitude]);
            output.push(prepareCoordinates(parallel, true));
        }
        for (var meridian = -150; meridian <= 180; meridian += 30) {
            var line = [];
            for (var lat = -90; lat <= 90; lat += 6)
                line.push([lat, meridian]);
            output.push(prepareCoordinates(line, true));
        }
        return output;
    }

    function prepareStationGeometry() {
        var output = [];
        var rows = Array.isArray(stations) ? stations : [];
        for (var i = 0; i < rows.length; i++) {
            var station = rows[i];
            if (!station || station.latitude === null || station.longitude === null)
                continue;
            var latitude = Number(station.latitude) * Math.PI / 180;
            var longitude = Number(station.longitude) * Math.PI / 180;
            if (!isFinite(latitude) || !isFinite(longitude))
                continue;
            var cosLatitude = Math.cos(latitude);
            output.push({
                station: station,
                worldX: cosLatitude * Math.cos(longitude),
                worldY: cosLatitude * Math.sin(longitude),
                worldZ: Math.sin(latitude),
                visible: false,
                screenX: 0,
                screenY: 0,
                depth: -1
            });
        }
        return output;
    }

    function paintCurve(ctx, coordinates, centreX, centreY, globeRadius, sinLatitude, cosLatitude, sinLongitude, cosLongitude) {
        var drawing = false;
        ctx.beginPath();
        for (var i = 0; i < coordinates.length; i += 3) {
            var horizontal = coordinates[i] * cosLongitude + coordinates[i + 1] * sinLongitude;
            var xProjection = coordinates[i + 1] * cosLongitude - coordinates[i] * sinLongitude;
            var yProjection = cosLatitude * coordinates[i + 2] - sinLatitude * horizontal;
            var depth = sinLatitude * coordinates[i + 2] + cosLatitude * horizontal;
            if (depth < 0) {
                drawing = false;
                continue;
            }
            var x = centreX + xProjection * globeRadius;
            var y = centreY - yProjection * globeRadius;
            if (!drawing)
                ctx.moveTo(x, y);
            else
                ctx.lineTo(x, y);
            drawing = true;
        }
        ctx.stroke();
    }

    function paintGrid(ctx, centreX, centreY, globeRadius) {
        ctx.strokeStyle = withAlpha(gridColor, 0.18);
        ctx.lineWidth = Math.min(1.5, Math.max(0.7, globeRadius / 500));
        var latitude = centreLatitude * Math.PI / 180;
        var longitude = centreLongitude * Math.PI / 180;
        var sinLatitude = Math.sin(latitude);
        var cosLatitude = Math.cos(latitude);
        var sinLongitude = Math.sin(longitude);
        var cosLongitude = Math.cos(longitude);
        for (var i = 0; i < preparedGrid.length; i++)
            paintCurve(ctx, preparedGrid[i], centreX, centreY, globeRadius, sinLatitude, cosLatitude, sinLongitude, cosLongitude);
    }

    function paintCountries(ctx, centreX, centreY, globeRadius) {
        var rows = preparedCountries;
        var latitude = centreLatitude * Math.PI / 180;
        var longitude = centreLongitude * Math.PI / 180;
        var sinLatitude = Math.sin(latitude);
        var cosLatitude = Math.cos(latitude);
        var sinLongitude = Math.sin(longitude);
        var cosLongitude = Math.cos(longitude);
        var activeCode = activeCountryCode.toUpperCase();
        for (var i = 0; i < rows.length; i++) {
            var country = rows[i];
            country.rings = country.levels[detailLevel()];
            var active = country.code === activeCode;
            ctx.fillStyle = active ? withAlpha(accentColor, 0.38) : withAlpha(landColor, 0.9);
            ctx.strokeStyle = active ? withAlpha(accentColor, 0.95) : withAlpha(outlineColor, 0.34);
            ctx.lineWidth = active ? 1.5 : 0.7;

            for (var ringIndex = 0; ringIndex < country.rings.length; ringIndex++) {
                var geometry = country.rings[ringIndex];
                var ring = geometry.world;
                var projected = geometry.projected;
                var points = Math.floor(ring.length / 3);
                var hiddenIndex = -1;
                for (var pointIndex = 0; pointIndex < points; pointIndex++) {
                    var hiddenOffset = pointIndex * 3;
                    var hiddenHorizontal = ring[hiddenOffset] * cosLongitude + ring[hiddenOffset + 1] * sinLongitude;
                    projected[hiddenOffset] = ring[hiddenOffset + 1] * cosLongitude - ring[hiddenOffset] * sinLongitude;
                    projected[hiddenOffset + 1] = cosLatitude * ring[hiddenOffset + 2] - sinLatitude * hiddenHorizontal;
                    projected[hiddenOffset + 2] = sinLatitude * ring[hiddenOffset + 2] + cosLatitude * hiddenHorizontal;
                    if (projected[hiddenOffset + 2] < 0 && hiddenIndex < 0) {
                        hiddenIndex = pointIndex;
                    }
                }

                if (hiddenIndex < 0) {
                    ctx.beginPath();
                    for (var visibleIndex = 0; visibleIndex < points; visibleIndex++) {
                        var visibleOffset = visibleIndex * 3;
                        var visibleX = projected[visibleOffset];
                        var visibleY = projected[visibleOffset + 1];
                        var screenX = centreX + visibleX * globeRadius;
                        var screenY = centreY - visibleY * globeRadius;
                        if (visibleIndex === 0)
                            ctx.moveTo(screenX, screenY);
                        else
                            ctx.lineTo(screenX, screenY);
                    }
                    ctx.closePath();
                    ctx.fill();
                    ctx.stroke();
                    continue;
                }

                var previousOffset = hiddenIndex * 3;
                var previousX = projected[previousOffset];
                var previousY = projected[previousOffset + 1];
                var previousDepth = projected[previousOffset + 2];
                var drawing = false;
                var startAngle = 0;

                for (var step = 1; step <= points; step++) {
                    var currentIndex = (hiddenIndex + step) % points;
                    var currentOffset = currentIndex * 3;
                    var currentX = projected[currentOffset];
                    var currentY = projected[currentOffset + 1];
                    var currentDepth = projected[currentOffset + 2];
                    var previousVisible = previousDepth >= 0;
                    var currentVisible = currentDepth >= 0;

                    if (!previousVisible && currentVisible) {
                        var enteringRatio = previousDepth / (previousDepth - currentDepth);
                        var enteringX = previousX + (currentX - previousX) * enteringRatio;
                        var enteringY = previousY + (currentY - previousY) * enteringRatio;
                        var enteringLength = Math.sqrt(enteringX * enteringX + enteringY * enteringY) || 1;
                        enteringX /= enteringLength;
                        enteringY /= enteringLength;
                        startAngle = Math.atan2(-enteringY, enteringX);
                        ctx.beginPath();
                        ctx.moveTo(centreX + enteringX * globeRadius, centreY - enteringY * globeRadius);
                        ctx.lineTo(centreX + currentX * globeRadius, centreY - currentY * globeRadius);
                        drawing = true;
                    } else if (previousVisible && currentVisible && drawing) {
                        ctx.lineTo(centreX + currentX * globeRadius, centreY - currentY * globeRadius);
                    } else if (previousVisible && !currentVisible && drawing) {
                        var leavingRatio = previousDepth / (previousDepth - currentDepth);
                        var leavingX = previousX + (currentX - previousX) * leavingRatio;
                        var leavingY = previousY + (currentY - previousY) * leavingRatio;
                        var leavingLength = Math.sqrt(leavingX * leavingX + leavingY * leavingY) || 1;
                        leavingX /= leavingLength;
                        leavingY /= leavingLength;
                        var endAngle = Math.atan2(-leavingY, leavingX);
                        var clockwiseArc = (startAngle - endAngle + Math.PI * 2) % (Math.PI * 2);
                        ctx.lineTo(centreX + leavingX * globeRadius, centreY - leavingY * globeRadius);
                        ctx.stroke();
                        ctx.arc(centreX, centreY, globeRadius, endAngle, startAngle, clockwiseArc > Math.PI);
                        ctx.closePath();
                        ctx.fill();
                        drawing = false;
                    }

                    previousX = currentX;
                    previousY = currentY;
                    previousDepth = currentDepth;
                }
            }
        }
    }

    // Dots are binned by depth so the fade costs 8 Qt.rgba() and 8 fillStyle
    // writes per frame instead of one per dot, quantised in steps of 0.06 of
    // alpha which is below what the eye picks up. Each dot still gets its own
    // beginPath/fill: a single path holding 1500 arcs has the whole globe for
    // a bounding box, and the raster engine scan-converts all of it.
    function paintSignals(ctx) {
        var rows = preparedStations;
        var latitude = centreLatitude * Math.PI / 180;
        var longitude = centreLongitude * Math.PI / 180;
        var sinLatitude = Math.sin(latitude);
        var cosLatitude = Math.cos(latitude);
        var sinLongitude = Math.sin(longitude);
        var cosLongitude = Math.cos(longitude);
        var globeRadius = radius();
        var bucketCount = signalDepthBuckets;
        var buckets = new Array(bucketCount);
        var markers = [];
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i];
            var horizontal = row.worldX * cosLongitude + row.worldY * sinLongitude;
            var xProjection = row.worldY * cosLongitude - row.worldX * sinLongitude;
            var yProjection = cosLatitude * row.worldZ - sinLatitude * horizontal;
            var depth = sinLatitude * row.worldZ + cosLatitude * horizontal;
            row.visible = depth >= 0;
            if (!row.visible)
                continue;
            row.screenX = globeCanvas.width / 2 + xProjection * globeRadius;
            row.screenY = globeCanvas.height / 2 - yProjection * globeRadius;
            row.depth = depth;
            row.visible = row.screenX >= -stationHitRadius && row.screenX <= globeCanvas.width + stationHitRadius && row.screenY >= -stationHitRadius && row.screenY <= globeCanvas.height + stationHitRadius;
            if (!row.visible)
                continue;
            var selected = selectedStation && row.station.uuid === selectedStation.uuid;
            var highlighted = highlightedStation && row.station.uuid === highlightedStation.uuid && !selected;
            if (selected || highlighted) {
                markers.push(row.screenX, row.screenY, selected ? 1 : 0);
                continue;
            }
            var bucket = Math.max(0, Math.min(bucketCount - 1, Math.floor(depth * bucketCount)));
            if (!buckets[bucket])
                buckets[bucket] = [];
            buckets[bucket].push(row.screenX, row.screenY);
        }
        for (var b = 0; b < bucketCount; b++) {
            var entries = buckets[b];
            if (!entries || entries.length === 0)
                continue;
            var bucketDepth = (b + 0.5) / bucketCount;
            var bucketRadius = 1.7 + bucketDepth * 1.25;
            ctx.fillStyle = withAlpha(signalColor, 0.42 + bucketDepth * 0.48);
            for (var e = 0; e < entries.length; e += 2) {
                ctx.beginPath();
                ctx.arc(entries[e], entries[e + 1], bucketRadius, 0, Math.PI * 2);
                ctx.fill();
            }
        }
        // Last, so the crowd never covers the playing or hovered station.
        for (var m = 0; m < markers.length; m += 3) {
            var isSelected = markers[m + 2] === 1;
            ctx.beginPath();
            ctx.arc(markers[m], markers[m + 1], isSelected ? 4.2 : 3.7, 0, Math.PI * 2);
            ctx.fillStyle = accentColor;
            ctx.fill();

            ctx.beginPath();
            ctx.arc(markers[m], markers[m + 1], isSelected ? 8.5 : 7.5, 0, Math.PI * 2);
            ctx.strokeStyle = withAlpha(accentColor, isSelected ? 0.72 : 0.92);
            ctx.lineWidth = isSelected ? 1.2 : 1.4;
            ctx.stroke();
        }
    }

    // A translucent veil over the night hemisphere and a thin line on the
    // terminator, both under the station dots. The polygon comes from the
    // model in unit disc coordinates; more segments at deeper zooms so the
    // curve stays smooth when a small part of it spans the whole view.
    function paintDayNight(ctx, centreX, centreY, globeRadius) {
        if (!sun)
            return;
        var steps = Math.min(512, Math.round(64 * Math.sqrt(Math.max(1, globeScale))));
        var geometry = RadioModel.terminatorGeometry(sun, centreLatitude, centreLongitude, steps);
        ctx.fillStyle = withAlpha(nightColor, nightOpacity);
        if (geometry.night.length === 0) {
            if (geometry.sunZ < 0) {
                ctx.beginPath();
                ctx.arc(centreX, centreY, globeRadius, 0, Math.PI * 2);
                ctx.fill();
            }
            return;
        }
        ctx.beginPath();
        for (var i = 0; i < geometry.night.length; i++) {
            var p = geometry.night[i];
            if (i === 0)
                ctx.moveTo(centreX + p.x * globeRadius, centreY - p.y * globeRadius);
            else
                ctx.lineTo(centreX + p.x * globeRadius, centreY - p.y * globeRadius);
        }
        ctx.closePath();
        ctx.fill();

        ctx.beginPath();
        for (var t = 0; t < geometry.terminator.length; t++) {
            var q = geometry.terminator[t];
            if (t === 0)
                ctx.moveTo(centreX + q.x * globeRadius, centreY - q.y * globeRadius);
            else
                ctx.lineTo(centreX + q.x * globeRadius, centreY - q.y * globeRadius);
        }
        ctx.strokeStyle = withAlpha(accentColor, 0.35);
        ctx.lineWidth = 1;
        ctx.stroke();
    }

    function refreshSun() {
        sun = RadioModel.subsolarPoint(new Date());
    }

    function paintGlobe(ctx) {
        var centreX = globeCanvas.width / 2;
        var centreY = globeCanvas.height / 2;
        var globeRadius = radius();
        if (!isFinite(globeRadius) || globeRadius <= 0)
            return;
        ctx.reset();
        ctx.fillStyle = backgroundColor;
        ctx.fillRect(0, 0, globeCanvas.width, globeCanvas.height);

        var sphere = ctx.createRadialGradient(centreX - globeRadius * 0.28, centreY - globeRadius * 0.32, globeRadius * 0.04, centreX, centreY, globeRadius);
        sphere.addColorStop(0, withAlpha(Qt.lighter(sphereColor, 1.7), 1));
        sphere.addColorStop(0.62, sphereColor);
        sphere.addColorStop(1, Qt.darker(sphereColor, 1.8));
        ctx.beginPath();
        ctx.arc(centreX, centreY, globeRadius, 0, Math.PI * 2);
        ctx.fillStyle = sphere;
        ctx.fill();

        ctx.save();
        ctx.beginPath();
        ctx.arc(centreX, centreY, globeRadius - 0.5, 0, Math.PI * 2);
        ctx.clip();
        paintGrid(ctx, centreX, centreY, globeRadius);
        paintCountries(ctx, centreX, centreY, globeRadius);
        if (showDayNight)
            paintDayNight(ctx, centreX, centreY, globeRadius);
        paintSignals(ctx);
        ctx.restore();

        ctx.beginPath();
        ctx.arc(centreX, centreY, globeRadius, 0, Math.PI * 2);
        ctx.strokeStyle = withAlpha(outlineColor, 0.52);
        ctx.lineWidth = 1.1;
        ctx.stroke();
    }

    function stationUnderPointer(x, y) {
        var nearest = null;
        var nearestDistance = stationHitRadius * stationHitRadius;
        for (var i = 0; i < preparedStations.length; i++) {
            var row = preparedStations[i];
            if (!row.visible)
                continue;
            var deltaX = row.screenX - x;
            var deltaY = row.screenY - y;
            var distance = deltaX * deltaX + deltaY * deltaY;
            if (distance > nearestDistance)
                continue;
            nearest = row.station;
            nearestDistance = distance;
        }
        return nearest;
    }

    function activateAt(x, y) {
        clearLandingHighlight();
        var station = stationUnderPointer(x, y);
        if (station) {
            stationActivated(station);
            return;
        }

        var globeRadius = radius();
        var normalizedX = (x - width / 2) / globeRadius;
        var normalizedY = -(y - height / 2) / globeRadius;
        var coordinate = RadioModel.unproject(normalizedX, normalizedY, centreLatitude, centreLongitude);
        if (!coordinate)
            return;
        var country = RadioModel.countryAt(countries, coordinate.latitude, coordinate.longitude);
        if (!country || !country.code || country.code === "-99")
            return;
        countryActivated(String(country.code).toUpperCase(), String(country.name || country.code));
    }

    onCountriesChanged: {
        preparedCountries = prepareCountryGeometry();
        root.schedulePaint();
        if (activeCountryCode)
            focusCountry(activeCountryCode);
    }
    onStationsChanged: {
        preparedStations = prepareStationGeometry();
        refreshLandingHighlight();
        root.schedulePaint();
    }
    onSelectedStationUuidChanged: {
        clearLandingHighlight();
        root.schedulePaint();
    }
    onActiveCountryCodeChanged: root.schedulePaint()
    onBackgroundColorChanged: root.schedulePaint()
    onSphereColorChanged: root.schedulePaint()
    onLandColorChanged: root.schedulePaint()
    onGridColorChanged: root.schedulePaint()
    onOutlineColorChanged: root.schedulePaint()
    onSignalColorChanged: root.schedulePaint()
    onAccentColorChanged: root.schedulePaint()
    onShowDayNightChanged: {
        if (showDayNight)
            refreshSun();
        root.schedulePaint();
    }
    onNightColorChanged: root.schedulePaint()
    onNightOpacityChanged: root.schedulePaint()
    onSunChanged: root.schedulePaint()
    onCentreLatitudeChanged: {
        updateHighlightPosition();
        root.schedulePaint();
    }
    onCentreLongitudeChanged: {
        updateHighlightPosition();
        root.schedulePaint();
    }
    onGlobeScaleChanged: {
        updateHighlightPosition();
        root.schedulePaint();
    }
    onWidthChanged: {
        updateHighlightPosition();
        root.schedulePaint();
    }
    onHeightChanged: {
        updateHighlightPosition();
        root.schedulePaint();
    }
    onHighlightedStationChanged: {
        updateHighlightPosition();
        root.schedulePaint();
    }
    onVisibleChanged: {
        if (!visible) {
            stopKineticRotation(true);
            stopZoomAnimation();
        }
    }

    NumberAnimation {
        id: zoomAnimation

        target: root
        property: "globeScale"
        duration: 180
        easing.type: Easing.OutCubic
    }

    Canvas {
        id: globeCanvas
        anchors.fill: parent
        // Rasterisation moves to its own thread: the JS of onPaint still runs
        // on the GUI thread, but the software painting of the whole canvas
        // does not, which is what was stealing frames from the list.
        renderStrategy: Canvas.Threaded
        onPaint: {
            var ctx = getContext("2d");
            if (!ctx)
                return;
            paintCounter.value += 1;
            root.paintGlobe(ctx);
        }
    }

    // Read-only from the outside through root.paintCount.
    QtObject {
        id: paintCounter

        property int value: 0
    }

    Timer {
        id: paintThrottle

        interval: 16
        onTriggered: if (root.paintDirty)
            root.schedulePaint()
    }

    // The terminator moves a quarter of a degree per minute.
    Timer {
        id: sunTimer

        interval: 60000
        repeat: true
        running: root.visible && root.showDayNight
        onRunningChanged: if (running)
            root.refreshSun()
        onTriggered: root.refreshSun()
    }

    Component.onCompleted: {
        preparedGrid = prepareGridGeometry();
        preparedCountries = prepareCountryGeometry();
        preparedStations = prepareStationGeometry();
        root.schedulePaint();
    }

    HoverHandler {
        id: hoverHandler
        cursorShape: dragHandler.active || tapHandler.pressed ? Qt.ClosedHandCursor : (root.hoveredStation ? Qt.PointingHandCursor : Qt.OpenHandCursor)

        onPointChanged: {
            root.hoverX = point.position.x;
            root.hoverY = point.position.y;
            root.pointerMoved();
            root.hoveredStation = kineticAnimation.running || dragHandler.active ? null : root.stationUnderPointer(point.position.x, point.position.y);
        }

        onHoveredChanged: {
            if (!hovered)
                root.hoveredStation = null;
        }
    }

    TapHandler {
        id: tapHandler
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.DragThreshold

        onPressedChanged: {
            if (!pressed)
                return;
            root.interactionStarted();
            var caughtKineticRotation = kineticAnimation.running;
            root.stopKineticRotation(true);
            root.suppressNextTap = caughtKineticRotation;
            root.hoveredStation = null;
        }

        onTapped: function (eventPoint) {
            if (root.suppressNextTap) {
                root.suppressNextTap = false;
                return;
            }
            root.activateAt(eventPoint.position.x, eventPoint.position.y);
            root.hoveredStation = hoverHandler.hovered ? root.stationUnderPointer(eventPoint.position.x, eventPoint.position.y) : null;
        }

        onCanceled: root.suppressNextTap = false
    }

    DragHandler {
        id: dragHandler
        target: null
        acceptedButtons: Qt.LeftButton

        property bool wasActive: false
        property bool launchCanceled: false
        property bool launchPending: false
        property int pendingLaunchGeneration: 0
        property real pendingVelocityX: 0
        property real pendingVelocityY: 0
        property real recentVelocityX: 0
        property real recentVelocityY: 0
        property real recentVelocityAt: 0
        property real samplePositionX: 0
        property real samplePositionY: 0
        property real sampleStartedAt: 0

        function resetMotionSample() {
            recentVelocityX = 0;
            recentVelocityY = 0;
            recentVelocityAt = 0;
            samplePositionX = centroid.position.x;
            samplePositionY = centroid.position.y;
            sampleStartedAt = Date.now();
        }

        function recordMotionSample() {
            // Qt's filtered mouse velocity can fall below the launch floor before
            // release. Keep a short, capped-by-launch recent sample for human-speed
            // flicks; the coast itself still uses frame-time-independent physics.
            var now = Date.now();
            var elapsedMilliseconds = now - sampleStartedAt;
            if (elapsedMilliseconds <= 0)
                return;
            var deltaX = centroid.position.x - samplePositionX;
            var deltaY = centroid.position.y - samplePositionY;
            samplePositionX = centroid.position.x;
            samplePositionY = centroid.position.y;
            sampleStartedAt = now;
            if (elapsedMilliseconds > 250)
                return;
            var sampledVelocityX = deltaX * 1000 / elapsedMilliseconds;
            var sampledVelocityY = deltaY * 1000 / elapsedMilliseconds;
            if (!isFinite(sampledVelocityX) || !isFinite(sampledVelocityY))
                return;
            if (recentVelocityAt > 0) {
                recentVelocityX = recentVelocityX * 0.25 + sampledVelocityX * 0.75;
                recentVelocityY = recentVelocityY * 0.25 + sampledVelocityY * 0.75;
            } else {
                recentVelocityX = sampledVelocityX;
                recentVelocityY = sampledVelocityY;
            }
            recentVelocityAt = now;
        }

        onActiveChanged: {
            if (active) {
                root.stopKineticRotation(true);
                root.stopZoomAnimation();
                wasActive = true;
                launchCanceled = false;
                launchPending = false;
                root.suppressNextTap = false;
                root.interactionStarted();
                root.hoveredStation = null;
                resetMotionSample();
                return;
            }
            if (!wasActive)
                return;
            wasActive = false;
            var releaseVelocity = RadioModel.kineticReleaseVelocity(centroid.velocity.x, centroid.velocity.y, recentVelocityX, recentVelocityY, recentVelocityAt > 0 ? Date.now() - recentVelocityAt : Infinity, root.kineticMaximumSampleAge);
            pendingVelocityX = releaseVelocity.x;
            pendingVelocityY = releaseVelocity.y;
            pendingLaunchGeneration = root.kineticLaunchGeneration;
            launchPending = !launchCanceled;
            Qt.callLater(function () {
                if (!dragHandler.launchPending || dragHandler.launchCanceled)
                    return;
                if (dragHandler.pendingLaunchGeneration !== root.kineticLaunchGeneration) {
                    dragHandler.launchPending = false;
                    return;
                }
                dragHandler.launchPending = false;
                root.startKineticRotation(dragHandler.pendingVelocityX, dragHandler.pendingVelocityY);
            });
        }

        onTranslationChanged: function (delta) {
            if (!active)
                return;
            recordMotionSample();
            root.rotateByPointerDelta(delta.x, delta.y);
        }

        onCanceled: {
            launchCanceled = true;
            launchPending = false;
            recentVelocityAt = 0;
            root.stopKineticRotation(false);
        }
    }

    WheelHandler {
        id: wheelHandler
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: true

        onWheel: function (event) {
            root.interactionStarted();
            root.stopKineticRotation(true);
            root.stopZoomAnimation();
            root.suppressNextTap = false;
            root.hoveredStation = null;
            var factor = Math.exp(event.angleDelta.y / 360);
            var nextScale = RadioModel.clamp(root.globeScale * factor, root.minimumScale, root.maximumScale);
            // The place under the cursor stays under the cursor, so zooming
            // into a city is a matter of pointing at it.
            var centre = RadioModel.zoomAnchoredCentre(point.position.x, point.position.y, root.width, root.height, root.globeScale, nextScale, root.centreLatitude, root.centreLongitude);
            root.globeScale = nextScale;
            root.centreLatitude = centre.latitude;
            root.centreLongitude = centre.longitude;
            event.accepted = true;
        }
    }

    FrameAnimation {
        id: kineticAnimation
        running: false

        onTriggered: {
            if (frameTime > root.kineticMaximumFrameTime) {
                root.stopKineticRotation(true);
                return;
            }
            if (frameTime <= 0)
                return;
            var step = RadioModel.advanceKineticRotation({
                longitude: root.centreLongitude,
                latitude: root.centreLatitude,
                velocityX: root.kineticVelocityX,
                velocityY: root.kineticVelocityY
            }, frameTime, {
                deceleration: root.kineticDeceleration,
                scale: root.globeScale,
                longitudeSensitivity: root.longitudeSensitivity,
                latitudeSensitivity: root.latitudeSensitivity,
                minimumLatitude: -78,
                maximumLatitude: 78
            });
            root.kineticVelocityX = step.velocityX;
            root.kineticVelocityY = step.velocityY;
            root.centreLongitude = step.longitude;
            root.centreLatitude = step.latitude;
            if (!step.active)
                root.finishKineticRotation();
        }
    }

    Rectangle {
        id: tooltip
        property var station: root.hoveredStation || root.highlightedStation
        property bool landing: !root.hoveredStation && !!root.highlightedStation
        property real anchorX: root.hoveredStation ? root.hoverX : root.highlightX
        property real anchorY: root.hoveredStation ? root.hoverY : root.highlightY

        visible: !!station && !tapHandler.pressed && !dragHandler.active && !kineticAnimation.running
        x: Math.min(root.width - width - 8, Math.max(8, anchorX + 14))
        y: Math.min(root.height - height - 8, Math.max(8, anchorY + 14))
        width: landing ? Math.min(280, Math.max(0, root.width - 16)) : Math.min(280, Math.max(0, root.width - 16), tooltipText.implicitWidth + 20)
        height: tooltipContent.implicitHeight + 14
        color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g, root.backgroundColor.b, 0.94)
        border.color: root.withAlpha(root.outlineColor, 0.5)
        border.width: 1
        radius: 2

        Column {
            id: tooltipContent
            anchors.centerIn: parent
            width: Math.max(0, parent.width - 20)
            spacing: 2

            Text {
                id: tooltipText
                width: parent.width
                text: {
                    if (!tooltip.station)
                        return "";
                    let label = tooltip.station.name;
                    if (tooltip.landing)
                        label = i18n("Landed near · %1", label);
                    else if (tooltip.station.estimatedLocation === true)
                        label = i18n("%1 · approximate location", label);
                    return label;
                }
                textFormat: Text.PlainText
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: tooltip.landing && tooltip.station && tooltip.station.estimatedLocation === true
                text: i18n("approximate location")
                textFormat: Text.PlainText
                color: root.withAlpha(root.textColor, 0.66)
                font.family: root.fontFamily
                font.pixelSize: 11
            }
        }
    }
}
