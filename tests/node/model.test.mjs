import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { loadQmlJs } from "./qmljs.mjs";

const testDir = path.dirname(fileURLToPath(import.meta.url));
const model = loadQmlJs("contents/ui/RadioModel.js");

test("radio atlas model", () => {
  function approximatelyEqual(actual, expected, tolerance = 1e-9) {
    assert.ok(
      Math.abs(actual - expected) <= tolerance,
      `expected ${actual} to be within ${tolerance} of ${expected}`
    )
  }

  assert.equal(model.clamp(12, 0, 10), 10)
  assert.equal(model.wrapLongitude(190), -170)
  assert.equal(model.wrapLongitude(-190), 170)

  const rejectedKineticVelocity = model.kineticLaunchVelocity(119, 0, 120, 2400)
  assert.equal(rejectedKineticVelocity.active, false)
  assert.equal(rejectedKineticVelocity.x, 0)
  const acceptedKineticVelocity = model.kineticLaunchVelocity(120, 0, 120, 2400)
  assert.equal(acceptedKineticVelocity.active, true)
  const cappedKineticVelocity = model.kineticLaunchVelocity(3000, 4000, 120, 2400)
  assert.equal(cappedKineticVelocity.active, true)
  approximatelyEqual(cappedKineticVelocity.x, 1440)
  approximatelyEqual(cappedKineticVelocity.y, 1920)
  approximatelyEqual(Math.hypot(cappedKineticVelocity.x, cappedKineticVelocity.y), 2400)

  const sampledReleaseVelocity = model.kineticReleaseVelocity(60, 20, 300, -40, 20, 100)
  approximatelyEqual(sampledReleaseVelocity.x, 300)
  approximatelyEqual(sampledReleaseVelocity.y, -40)
  const staleReleaseVelocity = model.kineticReleaseVelocity(60, 20, 300, -40, 101, 100)
  approximatelyEqual(staleReleaseVelocity.x, 60)
  approximatelyEqual(staleReleaseVelocity.y, 20)
  const fasterNativeReleaseVelocity = model.kineticReleaseVelocity(400, 0, 300, -40, 20, 100)
  approximatelyEqual(fasterNativeReleaseVelocity.x, 400)
  approximatelyEqual(fasterNativeReleaseVelocity.y, 0)
  const invalidReleaseVelocity = model.kineticReleaseVelocity(60, 20, 300, -40, Number.NaN, 100)
  approximatelyEqual(invalidReleaseVelocity.x, 60)
  approximatelyEqual(invalidReleaseVelocity.y, 20)
  const reversedReleaseVelocity = model.kineticReleaseVelocity(60, 20, -300, -40, 20, 100)
  approximatelyEqual(reversedReleaseVelocity.x, 60)
  approximatelyEqual(reversedReleaseVelocity.y, 20)
  const zeroNativeReleaseVelocity = model.kineticReleaseVelocity(0, 0, -300, -40, 20, 100)
  approximatelyEqual(zeroNativeReleaseVelocity.x, -300)
  approximatelyEqual(zeroNativeReleaseVelocity.y, -40)

  const kineticOptions = {
    deceleration: 1800,
    scale: 1,
    longitudeSensitivity: 0.22,
    latitudeSensitivity: 0.18,
    minimumLatitude: -78,
    maximumLatitude: 78
  }

  function simulateKineticRotation(framesPerSecond, initialState) {
    var state = initialState
    for (var frame = 0; frame < framesPerSecond * 3 && state.active !== false; frame++)
      state = model.advanceKineticRotation(state, 1 / framesPerSecond, kineticOptions)
    return state
  }

  const exactKineticStop = model.advanceKineticRotation({
    longitude: 0,
    latitude: 0,
    velocityX: 600,
    velocityY: 0
  }, 1, kineticOptions)
  assert.equal(exactKineticStop.active, false)
  approximatelyEqual(exactKineticStop.longitude, -22)

  const kineticAt30 = simulateKineticRotation(30, {
    longitude: 0,
    latitude: 0,
    velocityX: 1200,
    velocityY: 0,
    active: true
  })
  const kineticAt60 = simulateKineticRotation(60, {
    longitude: 0,
    latitude: 0,
    velocityX: 1200,
    velocityY: 0,
    active: true
  })
  const kineticAt120 = simulateKineticRotation(120, {
    longitude: 0,
    latitude: 0,
    velocityX: 1200,
    velocityY: 0,
    active: true
  })
  approximatelyEqual(kineticAt30.longitude, -88)
  approximatelyEqual(kineticAt60.longitude, kineticAt30.longitude)
  approximatelyEqual(kineticAt120.longitude, kineticAt30.longitude)
  assert.equal(kineticAt120.active, false)

  const wrappedKineticStop = model.advanceKineticRotation({
    longitude: 179,
    latitude: 0,
    velocityX: -600,
    velocityY: 0
  }, 1, kineticOptions)
  approximatelyEqual(wrappedKineticStop.longitude, -159)

  const poleKineticStep = model.advanceKineticRotation({
    longitude: 0,
    latitude: 77,
    velocityX: 600,
    velocityY: 600
  }, 0.05, kineticOptions)
  assert.equal(poleKineticStep.latitude, 78)
  assert.equal(poleKineticStep.velocityY, 0)
  assert.ok(poleKineticStep.velocityX > 0)
  assert.equal(poleKineticStep.active, true)

  const invalidKineticStep = model.advanceKineticRotation({
    longitude: 0,
    latitude: 0,
    velocityX: Number.NaN,
    velocityY: Number.POSITIVE_INFINITY
  }, 0.016, kineticOptions)
  assert.equal(invalidKineticStep.active, false)

  const centre = model.project(0, 0, 0, 0)
  assert.ok(Math.abs(centre.x) < 1e-9)
  assert.ok(Math.abs(centre.y) < 1e-9)
  assert.ok(centre.z > 0.999)

  const restored = model.unproject(0.25, -0.2, 20, -30)
  const projected = model.project(restored.latitude, restored.longitude, 20, -30)
  assert.ok(Math.abs(projected.x - 0.25) < 1e-9)
  assert.ok(Math.abs(projected.y + 0.2) < 1e-9)

  const square = [[[-10, -10], [10, -10], [10, 10], [-10, 10], [-10, -10]]]
  assert.equal(model.pointInPolygon(0, 0, square), true)
  assert.equal(model.pointInPolygon(20, 0, square), false)

  const countries = JSON.parse(fs.readFileSync(path.join(testDir, "..", "..", "contents", "data", "countries.json"), "utf8")).features
  const india = model.countryCentre(countries, "IN")
  assert.ok(india.latitude > 5 && india.latitude < 35)
  assert.ok(india.longitude > 65 && india.longitude < 100)
  const unitedStates = model.countryCentre(countries, "US")
  assert.ok(unitedStates.latitude > 25 && unitedStates.latitude < 55)
  assert.ok(unitedStates.longitude > -125 && unitedStates.longitude < -65)
  const canada = model.countryCentre(countries, "CA")
  assert.ok(canada.latitude > 40 && canada.latitude < 65)
  assert.ok(canada.longitude > -140 && canada.longitude < -50)
  assert.equal(model.countryCentre(countries, "XX"), null)

  const stations = [
    { uuid: "a", latitude: 0, longitude: 0 },
    { uuid: "b", latitude: 0, longitude: 180 }
  ]
  assert.equal(model.stationAt(stations, 100, 100, 200, 200, 1, 0, 0, 12).uuid, "a")
  assert.equal(model.compactTags("jazz, soul, jazz", 2), "jazz · soul")

  const landingStations = [
    { uuid: "playing", name: "Playing", latitude: 0, longitude: 0 },
    { uuid: "nearby", name: "Nearby", latitude: 0, longitude: 10 },
    { uuid: "horizon", name: "Horizon", latitude: 0, longitude: 90 },
    { uuid: "hidden", name: "Hidden", latitude: 0, longitude: 180 }
  ]
  const landingSnapshot = JSON.stringify(landingStations)
  assert.equal(model.nearestVisibleStation(landingStations, 0, 0, "").uuid, "playing")
  assert.equal(model.nearestVisibleStation(landingStations, 0, 0, "playing").uuid, "nearby")
  assert.equal(model.nearestVisibleStation([landingStations[0]], 0, 0, "playing").uuid, "playing")
  assert.equal(model.nearestVisibleStation([landingStations[3]], 0, 0, ""), null)
  assert.equal(JSON.stringify(landingStations), landingSnapshot)

  const zoomedLandingStations = [
    { uuid: "offscreen", name: "Off-screen", latitude: 0, longitude: 10 },
    { uuid: "onscreen", name: "On-screen", latitude: 0, longitude: 1 }
  ]
  assert.equal(
    model.nearestVisibleStation(zoomedLandingStations, 0, 0, "", 600, 600, 24).uuid,
    "onscreen"
  )
  assert.equal(
    model.nearestVisibleStation([zoomedLandingStations[0]], 0, 0, "", 600, 600, 24),
    null
  )

  const worldStations = [
    { uuid: "world", name: "World", latitude: 1, longitude: 1 },
    { uuid: "shared", name: "Old metadata", latitude: 2, longitude: 2 }
  ]
  const filteredStations = [
    { uuid: "shared", name: "Fresh metadata", latitude: 2, longitude: 2 },
    { uuid: "country", name: "Country", latitude: 3, longitude: 3 }
  ]
  const mergedStations = model.mergeGeoStations(worldStations, filteredStations)
  assert.deepEqual(Array.from(mergedStations, station => station.uuid), ["world", "shared", "country"])
  assert.equal(mergedStations[1].name, "Fresh metadata")

  const mergedCountryStations = model.mergeStations(
    [{ uuid: "cached", name: "Cached" }, { uuid: "shared", name: "Old" }],
    [{ uuid: "shared", name: "Fresh" }, { uuid: "remote", name: "Remote" }],
    3
  )
  assert.deepEqual(
    Array.from(mergedCountryStations, station => station.uuid),
    ["cached", "shared", "remote"]
  )
  assert.equal(mergedCountryStations[1].name, "Fresh")

  const fullCountryCache = Array.from({ length: 150 }, (_, index) => ({
    uuid: `country-cache-${index}`
  }))
  const fullCountryRefresh = Array.from({ length: 25 }, (_, index) => ({
    uuid: `country-refresh-${index}`
  }))
  assert.equal(model.mergeStations(fullCountryCache, fullCountryRefresh, 500).length, 175)

  const fullAtlas = Array.from({ length: 5000 }, (_, index) => ({
    uuid: `atlas-${index}`,
    name: `Background ${index}`
  }))
  const discoveredStations = [
    { uuid: "country-new", name: "Newly discovered" },
    { uuid: "atlas-4999", name: "Fresh country metadata" }
  ]
  const prioritizedAtlas = model.prioritizeStations(discoveredStations, fullAtlas, 5000)
  assert.equal(prioritizedAtlas.length, 5000)
  assert.deepEqual(
    Array.from(prioritizedAtlas.slice(0, 2), station => station.uuid),
    ["country-new", "atlas-4999"]
  )
  assert.equal(prioritizedAtlas[1].name, "Fresh country metadata")
  assert.equal(prioritizedAtlas.some(station => station.uuid === "atlas-4998"), false)
  const reprioritizedAtlas = model.prioritizeStations(
    [{ uuid: "second-country", name: "Second country" }], prioritizedAtlas, 5000
  )
  assert.deepEqual(
    Array.from(reprioritizedAtlas.slice(0, 3), station => station.uuid),
    ["second-country", "country-new", "atlas-4999"]
  )

  const fullWorld = Array.from({ length: 500 }, (_, index) => ({
    uuid: `world-${index}`,
    latitude: 0,
    longitude: index / 10
  }))
  const fullFilter = Array.from({ length: 300 }, (_, index) => ({
    uuid: `filter-${index}`,
    latitude: 1,
    longitude: index / 10
  }))
  const cappedStations = model.mergeGeoStations(fullWorld, fullFilter)
  assert.equal(cappedStations.length, 800)
  assert.equal(cappedStations.filter(station => station.uuid.startsWith("world-")).length, 500)

  const largeWorld = Array.from({ length: 5000 }, (_, index) => ({
    uuid: `large-world-${index}`,
    latitude: 0,
    longitude: 0
  }))
  const largeFilter = Array.from({ length: 1000 }, (_, index) => ({
    uuid: `large-filter-${index}`,
    latitude: 1,
    longitude: 1
  }))
  assert.equal(model.mergeGeoStations(largeWorld, largeFilter).length, 5500)

  const estimatedCountries = [{
    properties: { code: "ZZ", name: "Testland" },
    geometry: {
      type: "Polygon",
      coordinates: [[[10, 20], [20, 20], [20, 30], [10, 30], [10, 20]]]
    }
  }]
  const missingLocations = [
    { uuid: "estimate-one", name: "One", countryCode: "ZZ", latitude: null, longitude: null },
    { uuid: "estimate-two", name: "Two", countryCode: "ZZ", latitude: null, longitude: null }
  ]
  // Off (the default): a station without coordinates stays without.
  const kept = model.mergeGeoStations([], missingLocations, estimatedCountries)
  assert.equal(kept.length, 2)
  assert.equal(kept.every(station => station.latitude === null && station.estimatedLocation === undefined), true)
  const estimatedStations = model.mergeGeoStations([], missingLocations, estimatedCountries, true)
  assert.equal(estimatedStations.length, 2)
  assert.equal(estimatedStations.every(station => station.estimatedLocation === true), true)
  assert.equal(estimatedStations.every(station => station.latitude >= 20 && station.latitude <= 30), true)
  assert.equal(estimatedStations.every(station => station.longitude >= 10 && station.longitude <= 20), true)
  assert.notDeepEqual(
    [estimatedStations[0].latitude, estimatedStations[0].longitude],
    [estimatedStations[1].latitude, estimatedStations[1].longitude]
  )
  assert.deepEqual(
    Array.from(model.mergeGeoStations([], missingLocations, estimatedCountries, true), station => [station.latitude, station.longitude]),
    Array.from(estimatedStations, station => [station.latitude, station.longitude])
  )

  const searchableStations = [
    {
      uuid: "jazz",
      name: "Blue Note 93",
      country: "United States",
      countryCode: "US",
      state: "New York",
      language: "English",
      tags: "jazz,soul",
      codec: "AAC"
    },
    {
      uuid: "ambient",
      name: "Night Signals",
      country: "Germany",
      countryCode: "DE",
      state: "Berlin",
      language: "German",
      tags: "ambient,electronic",
      codec: "MP3"
    }
  ]
  assert.deepEqual(Array.from(model.searchStations(searchableStations, "93"), station => station.uuid), ["jazz"])
  assert.deepEqual(Array.from(model.searchStations(searchableStations, "germany"), station => station.uuid), ["ambient"])
  assert.deepEqual(Array.from(model.searchStations(searchableStations, "SOUL"), station => station.uuid), ["jazz"])
  assert.deepEqual(Array.from(model.searchStations(searchableStations, "")), [])
  assert.deepEqual(Array.from(model.stationsForCountry(searchableStations, "de"), station => station.uuid), ["ambient"])
  assert.equal(model.searchStations(searchableStations, "a", 1).length, 1)

  const playlistRows = Array.from({ length: 8 }, (_, index) => ({ uuid: `queue-${index}` }))
  assert.deepEqual(
    Array.from(model.stationWindow(playlistRows, "queue-4", 5), station => station.uuid),
    ["queue-2", "queue-3", "queue-4", "queue-5", "queue-6"]
  )
  assert.deepEqual(
    Array.from(model.stationWindow(playlistRows, "queue-0", 5), station => station.uuid),
    ["queue-6", "queue-7", "queue-0", "queue-1", "queue-2"]
  )
  assert.deepEqual(Array.from(model.stationWindow(playlistRows, "missing", 5)), [])
});

test("zoomAnchoredCentre keeps the point under the cursor in place", () => {
    const width = 800, height = 600;
    const centre = { latitude: 20, longitude: -10 };
    const cursor = { x: 560, y: 210 };
    const normalised = (scale) => {
        const r = Math.min(width, height) * 0.44 * scale;
        return { x: (cursor.x - width / 2) / r, y: -(cursor.y - height / 2) / r };
    };
    const before = normalised(1);
    const anchor = model.unproject(before.x, before.y, centre.latitude, centre.longitude);
    const next = model.zoomAnchoredCentre(cursor.x, cursor.y, width, height, 1, 3, centre.latitude, centre.longitude);
    const pos = model.stationPosition(anchor, width, height, 3, next.latitude, next.longitude);
    assert.ok(Math.abs(pos.x - cursor.x) < 0.5 && Math.abs(pos.y - cursor.y) < 0.5, JSON.stringify(pos));
});

test("zoomAnchoredCentre zooms about the centre when the cursor is off the sphere", () => {
    const next = model.zoomAnchoredCentre(5, 5, 800, 600, 1, 2, 20, -10);
    assert.equal(next.latitude, 20);
    assert.equal(next.longitude, -10);
});

test("zoomAnchoredCentre respects the latitude limits", () => {
    const next = model.zoomAnchoredCentre(400, 40, 800, 600, 1, 8, 70, 0);
    assert.ok(next.latitude <= 78);
});

test("subsolarPoint follows the seasons and the clock", () => {
    const june = model.subsolarPoint(new Date("2026-06-21T12:00:00Z"));
    assert.ok(june.latitude > 23.3 && june.latitude < 23.5, "summer solstice " + june.latitude);
    assert.ok(Math.abs(june.longitude) < 2, "noon UTC near Greenwich " + june.longitude);

    const december = model.subsolarPoint(new Date("2026-12-21T12:00:00Z"));
    assert.ok(december.latitude < -23.3 && december.latitude > -23.5, "winter solstice " + december.latitude);

    const march = model.subsolarPoint(new Date("2026-03-20T12:00:00Z"));
    assert.ok(Math.abs(march.latitude) < 0.5, "equinox " + march.latitude);

    const midnight = model.subsolarPoint(new Date("2026-03-20T00:00:00Z"));
    assert.ok(Math.abs(midnight.longitude) > 175, "midnight UTC antipodal " + midnight.longitude);

    // At 06:00 UTC it is solar noon 90 degrees east of Greenwich.
    const sixUtc = model.subsolarPoint(new Date("2026-03-20T06:00:00Z"));
    assert.ok(Math.abs(sixUtc.longitude - 90) < 2, "06:00 UTC " + sixUtc.longitude);
});

test("terminatorGeometry: the visible half of the terminator is orthogonal to the sun", () => {
    const geometry = model.terminatorGeometry({ latitude: 10, longitude: 90 }, 20, -30, 32);
    assert.equal(geometry.terminator.length, 33);
    for (const p of geometry.terminator) {
        assert.ok(Math.abs(p.x * p.x + p.y * p.y + p.z * p.z - 1) < 1e-9, "unit " + JSON.stringify(p));
        assert.ok(Math.abs(p.x * geometry.sunX + p.y * geometry.sunY + p.z * geometry.sunZ) < 1e-9, "orthogonal " + JSON.stringify(p));
        assert.ok(p.z >= -1e-9, "visible " + JSON.stringify(p));
    }
    // Both ends sit on the rim, opposite each other.
    const first = geometry.terminator[0];
    const last = geometry.terminator[32];
    assert.ok(Math.abs(first.z) < 1e-9 && Math.abs(last.z) < 1e-9);
    assert.ok(Math.abs(first.x + last.x) < 1e-9 && Math.abs(first.y + last.y) < 1e-9);
});

test("terminatorGeometry: the night polygon covers the side away from the sun", () => {
    // Sun due east of the view centre: the western half of the disc is night.
    const geometry = model.terminatorGeometry({ latitude: 0, longitude: 90 }, 0, 0, 32);
    assert.ok(Math.abs(geometry.sunZ) < 1e-9);
    assert.ok(geometry.night.length > geometry.terminator.length);
    for (const p of geometry.night)
        assert.ok(p.x <= 1e-9, "night point on the west " + JSON.stringify(p));
    // The rim part of the polygon passes through the point opposite the sun.
    assert.ok(geometry.night.some(p => Math.abs(p.x + 1) < 1e-9 && Math.abs(p.y) < 1e-9));
    // Every polygon point sits on or inside the disc.
    for (const p of geometry.night)
        assert.ok(p.x * p.x + p.y * p.y <= 1 + 1e-9);
});

test("terminatorGeometry: sun in front lights the whole disc, sun behind darkens it", () => {
    const lit = model.terminatorGeometry({ latitude: 0, longitude: 0 }, 0, 0, 32);
    assert.equal(lit.terminator.length, 0);
    assert.equal(lit.night.length, 0);
    assert.ok(lit.sunZ > 0.99);

    const dark = model.terminatorGeometry({ latitude: 0, longitude: 180 }, 0, 0, 32);
    assert.equal(dark.terminator.length, 0);
    assert.equal(dark.night.length, 0);
    assert.ok(dark.sunZ < -0.99);
});

test("terminatorGeometry: a sun mostly in front leaves less than half the disc in night", () => {
    const geometry = model.terminatorGeometry({ latitude: 0, longitude: 30 }, 0, 0, 64);
    assert.ok(geometry.sunZ > 0.8);
    // The terminator bulges away from the sun (west), so the night crescent
    // is the thin strip between it and the western rim.
    const middle = geometry.terminator[32];
    assert.ok(middle.x < 0 && middle.x > -1, "bulge " + JSON.stringify(middle));
    for (const p of geometry.night)
        assert.ok(p.x <= 1e-9);
});

test("simplifyRing drops the points that stay within the tolerance", () => {
    // A straight run of ten points, one of them bent away by a full degree.
    const ring = [];
    for (let i = 0; i <= 9; i++)
        ring.push([i, 0]);
    ring[5] = [5, 1];
    // The bend stays, and so do its neighbours: 0.78 degree off the new chords.
    const kept = model.simplifyRing(ring, 0.35);
    assert.deepEqual(Array.from(kept, p => [...p]), [[0, 0], [4, 0], [5, 1], [6, 0], [9, 0]]);
    // A tolerance wider than the bend flattens the whole run.
    assert.deepEqual(Array.from(model.simplifyRing(ring, 1.5), p => [...p]), [[0, 0], [9, 0]]);
});

test("simplifyRing keeps everything at tolerance zero and on tiny rings", () => {
    const ring = [[0, 0], [1, 0.1], [2, 0], [3, 0.1], [4, 0], [5, 0.1], [6, 0], [7, 0.1], [8, 0]];
    assert.equal(model.simplifyRing(ring, 0), ring);
    const tiny = [[0, 0], [1, 0], [2, 0], [3, 0], [4, 0], [0, 0]];
    assert.equal(model.simplifyRing(tiny, 5), tiny);
});

test("simplifyRing on the real countries gives the three detail levels", () => {
    const features = JSON.parse(fs.readFileSync(path.join(testDir, "../../contents/data/countries.json"), "utf8")).features;
    function count(tolerance) {
        let points = 0;
        for (const feature of features) {
            const geometry = feature.geometry;
            const polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates;
            for (const polygon of polygons)
                points += model.simplifyRing(polygon[0], tolerance).length;
        }
        return points;
    }
    assert.equal(count(0), 10642);
    assert.ok(count(0.1) < 8600 && count(0.1) > 8200, "0.1 degree: " + count(0.1));
    assert.ok(count(0.35) < 4600 && count(0.35) > 4200, "0.35 degree: " + count(0.35));
});

test("countryGeoLimit gives the big countries three times the room", () => {
    assert.equal(model.countryGeoLimit("FR", 500), 500);
    assert.equal(model.countryGeoLimit("us", 500), 1500);
    assert.equal(model.countryGeoLimit("CN", 200), 600);
    assert.equal(model.countryGeoLimit("RU", 1000), 3000);
    assert.equal(model.countryGeoLimit("", 500), 500);
    // Nothing sensible given: the default.
    assert.equal(model.countryGeoLimit("FR"), 500);
    assert.equal(model.countryGeoLimit("FR", 0), 500);
});

test("navigationTarget steps through the list, and enters it when the station is not there", () => {
    const list = [{ uuid: "a" }, { uuid: "b" }, { uuid: "c" }];
    assert.equal(model.navigationTarget(list, "a", 1).uuid, "b");
    assert.equal(model.navigationTarget(list, "a", -1).uuid, "c");
    assert.equal(model.navigationTarget(list, "zzz", 1).uuid, "a");
    assert.equal(model.navigationTarget(list, "zzz", -1).uuid, "c");
    assert.equal(model.navigationTarget(list, "", 1).uuid, "a");
    assert.equal(model.navigationTarget([], "a", 1), null);
});

test("applyFilters sorts and filters a loaded list without touching it", () => {
    const list = [
        { uuid: "a", name: "Zeta", codec: "MP3", bitrate: 128, clicks: 50, votes: 3 },
        { uuid: "b", name: "alpha", codec: "AAC+", bitrate: 64, clicks: 40, votes: 10 },
        { uuid: "c", name: "Éclair", codec: "AAC", bitrate: 256, clicks: 30, votes: 10 },
        { uuid: "d", name: "Beta", codec: "", bitrate: 0, clicks: 20 },
        { uuid: "e", name: "Gamma", codec: "OGG", bitrate: 192, clicks: 10, votes: 1 },
        { uuid: "f", name: "Delta", codec: "FLAC", bitrate: 900, clicks: 5, votes: 0 },
        { uuid: "g", name: "Eta", codec: "AAC,H.264", bitrate: 96, clicks: 4, votes: 0 },
        { uuid: "h", name: "Theta", codec: "Vorbis", bitrate: 160, clicks: 3, votes: 0 }
    ];
    const ids = rows => Array.from(rows, r => r.uuid);
    const none = { sort: "popularity", codec: "", minBitrate: 0 };
    // Default: the input order, untouched.
    const all = ["a", "b", "c", "d", "e", "f", "g", "h"];
    assert.deepEqual(ids(model.applyFilters(list, none)), all);
    assert.deepEqual(ids(model.applyFilters(list, null)), all);
    assert.deepEqual(ids(model.applyFilters(list, {})), all);
    // Sorts: ties keep the input order; missing votes count as 0.
    assert.deepEqual(ids(model.applyFilters(list, { sort: "votes" })), ["b", "c", "a", "e", "d", "f", "g", "h"]);
    assert.deepEqual(ids(model.applyFilters(list, { sort: "name" })), ["b", "d", "f", "c", "g", "e", "h", "a"]);
    assert.deepEqual(ids(model.applyFilters(list, { sort: "bitrate" })), ["f", "c", "e", "h", "a", "g", "b", "d"]);
    // Codec families, several at once: AAC covers AAC+ and "AAC,H.264",
    // OGG covers Vorbis, unknown families (FLAC, empty) never match.
    assert.deepEqual(ids(model.applyFilters(list, { codec: "mp3" })), ["a"]);
    assert.deepEqual(ids(model.applyFilters(list, { codec: "aac" })), ["b", "c", "g"]);
    assert.deepEqual(ids(model.applyFilters(list, { codec: "AAC" })), ["b", "c", "g"]);
    assert.deepEqual(ids(model.applyFilters(list, { codec: "ogg" })), ["e", "h"]);
    assert.deepEqual(ids(model.applyFilters(list, { codec: "mp3,ogg" })), ["a", "e", "h"]);
    assert.deepEqual(ids(model.applyFilters(list, { codec: "ogg, mp3" })), ["a", "e", "h"]);
    // Only unknown names: no restriction at all.
    assert.deepEqual(ids(model.applyFilters(list, { codec: "flac,opus" })), all);
    // Minimum bitrate; an unknown bitrate (0) is dropped once a minimum is set.
    assert.deepEqual(ids(model.applyFilters(list, { minBitrate: 128 })), ["a", "c", "e", "f", "h"]);
    assert.deepEqual(ids(model.applyFilters(list, { minBitrate: 128, sort: "bitrate" })), ["f", "c", "e", "h", "a"]);
    assert.deepEqual(ids(model.applyFilters(list, { codec: "aac", minBitrate: 128 })), ["c"]);
    // The input is left alone.
    assert.deepEqual(ids(list), all);
    assert.deepEqual(ids(model.applyFilters(null, { sort: "name" })), []);
});

test("filtersActive says whether anything departs from the defaults", () => {
    assert.equal(model.filtersActive({ sort: "popularity", codec: "", minBitrate: 0 }), false);
    assert.equal(model.filtersActive(null), false);
    assert.equal(model.filtersActive({ sort: "votes" }), true);
    assert.equal(model.filtersActive({ codec: "mp3" }), true);
    assert.equal(model.filtersActive({ codec: "opus" }), false);
    assert.equal(model.filtersActive({ minBitrate: 64 }), true);
});

test("codecSet and toggleCodec keep the codec setting clean", () => {
    assert.deepEqual([...model.codecSet("aac,mp3")], ["mp3", "aac"]);
    assert.deepEqual([...model.codecSet(" MP3 ,flac")], ["mp3"]);
    assert.deepEqual([...model.codecSet("")], []);
    assert.deepEqual([...model.codecSet(null)], []);
    assert.equal(model.toggleCodec("", "aac", true), "aac");
    assert.equal(model.toggleCodec("aac", "mp3", true), "mp3,aac");
    assert.equal(model.toggleCodec("mp3,aac", "aac", false), "mp3");
    assert.equal(model.toggleCodec("mp3", "mp3", false), "");
    assert.equal(model.toggleCodec("mp3", "mp3", true), "mp3");
});
