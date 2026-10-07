import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/RadioModel.js" as RadioModel

// tests/run runs this file a second time with QT_SCALE_FACTOR=1.5: canvases
// then hold 1.5 device pixels per unit, which the rest of the suite, at
// scale 1, never exercises.
TestCase {
    id: testCase

    name: "GlobeScaled"
    when: windowShown
    width: 800
    height: 600
    visible: true

    function i18n(text, arg) {
        return arg === undefined ? text : text.replace("%1", arg);
    }

    // grabImage() returns device pixels but crops them to the size of the
    // grabbed item in units: the whole test window is grabbed, and a globe
    // at half its size stays whole in it up to a scale of 2.
    Ui.Globe {
        id: globe
        width: 400
        height: 300
    }

    // While the globe moves, dots are blitted from pre-rendered sprites. At a
    // fractional scale they came out as two thin bars with nothing in the
    // middle (issue #2): the centre of every dot must stay lit.
    function test_movingDotsStayRoundOnScaledScreens() {
        globe.centreLatitude = 0;
        globe.centreLongitude = 0;
        globe.globeScale = 1;
        globe.showDayNight = false;
        globe.backgroundColor = "#000000";
        globe.sphereColor = "#000000";
        globe.landColor = "#000000";
        globe.gridColor = "#000000";
        globe.outlineColor = "#000000";
        globe.signalColor = "#ffffff";
        // One dot per depth bucket on the prime meridian, the angle from the
        // centre picked so that depth lands mid-bucket; north and south in
        // turn so that neighbours never overlap. Bucket 0 is left out: at
        // that depth the dot sits on the limb, half cut by the disc.
        const stations = [];
        for (let b = 1; b < globe.signalDepthBuckets; b++) {
            const angle = Math.acos((b + 0.5) / globe.signalDepthBuckets) * 180 / Math.PI;
            stations.push({
                uuid: "bucket" + b,
                latitude: b % 2 === 0 ? angle : -angle,
                longitude: 0
            });
        }

        // Held mid-drag, the globe keeps painting the moving way. The dots
        // only arrive then, so no frame painted at rest can hold them.
        mousePress(globe, 350, 150);
        mouseMove(globe, 340, 150);
        mouseMove(globe, 330, 150);
        tryCompare(globe, "moving", true);
        globe.stations = stations;

        // A frame counts once the background is painted and every dot shows
        // somewhere in its sprite cell; then each dot's centre must be lit.
        const ratio = Screen.devicePixelRatio;
        const reach = Math.ceil(globe.dotSpriteCell / 2 * ratio);
        function inspect() {
            const image = grabImage(testCase);
            const result = {
                ready: Qt.colorEqual(image.pixel(2, 2), "#000000"),
                dark: ""
            };
            for (const station of stations) {
                const position = RadioModel.stationPosition(station, globe.width, globe.height, globe.globeScale, globe.centreLatitude, globe.centreLongitude);
                const x = Math.floor(position.x * ratio);
                const y = Math.floor(position.y * ratio);
                let drawn = false;
                for (let dx = -reach; dx <= reach && !drawn; dx++)
                    for (let dy = -reach; dy <= reach && !drawn; dy++)
                        drawn = image.pixel(x + dx, y + dy).r >= 0.3;
                result.ready = result.ready && drawn;
                const centre = image.pixel(x, y);
                if (centre.r < 0.3)
                    result.dark += " " + station.uuid + "=" + centre;
            }
            return result;
        }
        // The threaded canvas hands its frame over a little later.
        let frame = inspect();
        for (let attempt = 0; !frame.ready && attempt < 30; attempt++) {
            wait(100);
            frame = inspect();
        }
        verify(frame.ready, "no frame with every dot painted");
        verify(globe.moving, "still painting the moving way");
        verify(frame.dark === "", "dark dot centres at scale " + ratio + ":" + frame.dark);
        mouseRelease(globe, 330, 150);
        wait(50);
        globe.stopKineticRotation(true);
    }
}
