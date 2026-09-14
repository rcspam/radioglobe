import assert from "node:assert/strict";
import { test } from "node:test";
import { loadQmlJs } from "./qmljs.mjs";

const model = loadQmlJs("contents/ui/RadioModel.js");

const raw = {
    stationuuid: "abc-123",
    name: " FIP\n Paris ",
    url: "http://example.org/list.pls",
    url_resolved: "https://stream.example.org/fip.mp3",
    homepage: "https://fip.fr",
    favicon: "javascript:alert(1)",
    country: "France",
    countrycode: "fr",
    state: "Île-de-France",
    language: "french",
    tags: "jazz,eclectic",
    codec: "MP3",
    bitrate: 128000,
    geo_lat: 48.85,
    geo_long: 2.35,
    clickcount: "42",
    hls: 0,
};

test("normalizeStation maps and cleans Radio Browser fields", () => {
    const s = model.normalizeStation(raw);
    assert.equal(s.uuid, "abc-123");
    assert.equal(s.name, "FIP Paris");
    assert.equal(s.url, "https://stream.example.org/fip.mp3");
    assert.equal(s.favicon, "");
    assert.equal(s.countryCode, "FR");
    assert.equal(s.bitrate, 128);
    assert.equal(s.latitude, 48.85);
    assert.equal(s.longitude, 2.35);
    assert.equal(s.clicks, 42);
    assert.equal(s.hls, false);
    assert.equal(s.estimatedLocation, undefined);
});

test("normalizeStation falls back to url and rejects non-http streams", () => {
    const s = model.normalizeStation({ ...raw, url_resolved: "" });
    assert.equal(s.url, "http://example.org/list.pls");
    assert.equal(model.normalizeStation({ ...raw, url_resolved: null, url: "rtsp://x" }), null);
    assert.equal(model.normalizeStation({ ...raw, stationuuid: "" }), null);
});

test("normalizeStation drops out-of-range coordinates and caps lengths", () => {
    const s = model.normalizeStation({ ...raw, geo_lat: 95, geo_long: 2, name: "x".repeat(300) });
    assert.equal(s.latitude, null);
    assert.equal(s.longitude, null);
    assert.equal(s.name.length, 160);
    assert.equal(model.normalizeStation({ ...raw, name: "" }).name, "Unknown station");
});

test("normalizeStations dedupes by uuid and caps the count", () => {
    const rows = [raw, raw, { ...raw, stationuuid: "other" }, { ...raw, stationuuid: "third" }];
    const list = model.normalizeStations(rows, 2);
    assert.deepEqual(Array.from(list, s => s.uuid), ["abc-123", "other"]);
});

test("dedupeByUrl keeps the most clicked station per stream url", () => {
    const a = { uuid: "a", url: "https://x/1", clicks: 5 };
    const b = { uuid: "b", url: "https://x/1", clicks: 9 };
    const c = { uuid: "c", url: "https://x/2", clicks: 1 };
    assert.deepEqual(Array.from(model.dedupeByUrl([a, b, c]), s => s.uuid), ["b", "c"]);
});

test("pickRandomStation avoids recent uuids and uses the injected random", () => {
    const stations = [{ uuid: "a" }, { uuid: "b" }, { uuid: "c" }];
    assert.equal(model.pickRandomStation(stations, ["a", "b"], () => 0.99).uuid, "c");
    assert.equal(model.pickRandomStation(stations, ["a", "b", "c"], () => 0).uuid, "a");
    assert.equal(model.pickRandomStation([], [], () => 0), null);
});

test("neighbourStation wraps around the queue", () => {
    const q = [{ uuid: "a" }, { uuid: "b" }, { uuid: "c" }];
    assert.equal(model.neighbourStation(q, "c", 1).uuid, "a");
    assert.equal(model.neighbourStation(q, "a", -1).uuid, "c");
    assert.equal(model.neighbourStation(q, "zz", 1), null);
    assert.equal(model.neighbourStation([], "a", 1), null);
});

test("toggleFavorite adds then removes by uuid", () => {
    const s = { uuid: "a", name: "A" };
    const once = model.toggleFavorite([], s);
    assert.equal(once.length, 1);
    assert.equal(model.toggleFavorite(once, { uuid: "a" }).length, 0);
});

test("pushHistory prepends, dedupes and caps", () => {
    const h1 = model.pushHistory([], { uuid: "a" }, 1000, 2);
    const h2 = model.pushHistory(h1, { uuid: "b" }, 2000, 2);
    const h3 = model.pushHistory(h2, { uuid: "a" }, 3000, 2);
    assert.deepEqual(Array.from(h3, e => e.uuid), ["a", "b"]);
    assert.equal(h3[0].playedAt, 3000);
    const h4 = model.pushHistory(h3, { uuid: "c" }, 4000, 2);
    assert.deepEqual(Array.from(h4, e => e.uuid), ["c", "a"]);
});

test("isRawTitle detects the url filename mpv reports before ICY arrives", () => {
    assert.equal(model.isRawTitle("fip-midfi.mp3", "https://x/fip-midfi.mp3"), true);
    assert.equal(model.isRawTitle("", "https://x/a.mp3"), true);
    assert.equal(model.isRawTitle("https://x/a.mp3", "https://x/a.mp3"), true);
    assert.equal(model.isRawTitle("Klangstein - Closer", "https://x/a.mp3"), false);
});

test("validMirrorName only accepts radio-browser api hosts", () => {
    assert.equal(model.validMirrorName("de1.api.radio-browser.info"), true);
    assert.equal(model.validMirrorName("evil.example.org"), false);
    assert.equal(model.validMirrorName("x.api.radio-browser.info.evil"), false);
});

test("buildQuery encodes values and writes booleans as literal strings", () => {
    assert.equal(model.buildQuery({ hidebroken: true, limit: 5, name: "a b" }), "hidebroken=true&limit=5&name=a%20b");
});

test("spreadOverlapping nudges stations sharing the exact same point", () => {
    const rows = [
        { uuid: "a", latitude: 48.85, longitude: 2.35 },
        { uuid: "b", latitude: 48.85, longitude: 2.35 },
        { uuid: "c", latitude: 48.85, longitude: 2.35 },
        { uuid: "d", latitude: 10, longitude: 10 },
        { uuid: "e", latitude: null, longitude: null },
    ];
    const out = model.spreadOverlapping(rows);
    assert.equal(out[0].latitude, 48.85);
    assert.notEqual(out[1].latitude + "," + out[1].longitude, out[0].latitude + "," + out[0].longitude);
    assert.notEqual(out[2].latitude + "," + out[2].longitude, out[1].latitude + "," + out[1].longitude);
    assert.ok(Math.abs(out[2].latitude - 48.85) < 0.2);
    assert.equal(out[3].latitude, 10);
    assert.equal(out[4].latitude, null);
    assert.equal(rows[1].latitude, 48.85, "input rows are not mutated");
});

test("shellQuote wraps a value and escapes embedded single quotes", () => {
    assert.equal(model.shellQuote("mpv"), "'mpv'");
    assert.equal(model.shellQuote("/opt/my player/mpv"), "'/opt/my player/mpv'");
    assert.equal(model.shellQuote("it's"), "'it'\\''s'");
    assert.equal(model.shellQuote(42), "'42'");
});

test("sortWorld keeps home stations first, then sorts by clicks", () => {
    const rows = [
        { uuid: "de1", countryCode: "DE", clicks: 500 },
        { uuid: "fr1", countryCode: "FR", clicks: 1 },
        { uuid: "de2", countryCode: "DE", clicks: 900 },
        { uuid: "fr2", countryCode: "FR", clicks: 0 },
        { uuid: "us1", countryCode: "US", clicks: 700 },
    ];
    const out = model.sortWorld(rows, "FR");
    assert.deepEqual(Array.from(out, s => s.uuid), ["fr1", "fr2", "de2", "us1", "de1"]);
    assert.deepEqual(Array.from(rows, s => s.uuid), ["de1", "fr1", "de2", "fr2", "us1"], "input is not mutated");
    assert.notEqual(out, rows);
});

test("sortWorld is stable between stations of equal rank", () => {
    const rows = [
        { uuid: "a", countryCode: "FR", clicks: 3 },
        { uuid: "b", countryCode: "FR", clicks: 3 },
        { uuid: "c", countryCode: "DE", clicks: 3 },
        { uuid: "d", countryCode: "DE", clicks: 3 },
    ];
    assert.deepEqual(Array.from(model.sortWorld(rows, "FR"), s => s.uuid), ["a", "b", "c", "d"]);
});

test("sortWorld without a home country sorts by clicks only", () => {
    const rows = [
        { uuid: "a", countryCode: "FR", clicks: 1 },
        { uuid: "b", countryCode: "DE", clicks: 5 },
    ];
    assert.deepEqual(Array.from(model.sortWorld(rows, ""), s => s.uuid), ["b", "a"]);
    assert.deepEqual(Array.from(model.sortWorld(rows), s => s.uuid), ["b", "a"]);
});
