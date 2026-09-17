import assert from "node:assert/strict";
import { test } from "node:test";
import { loadQmlJs } from "./qmljs.mjs";

const model = loadQmlJs("contents/ui/RadioModel.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

const fip = { uuid: "fip", name: "FIP", url: "https://stream.example.org/fip" };
const jazz = { uuid: "jazz", name: "Jazz", url: "https://stream.example.org/jazz", playedAt: 1700000000000 };

test("buildBackup wraps favourites, history and the known settings only", () => {
    const backup = model.buildBackup([fip], [jazz], {
        homeCountry: "FR",
        maxWorldStations: 3000,
        approximateLocations: false,
        mpvPath: "",
        sendClicks: true,
        icon: "map-globe",
        iconColor: "#226ce7",
        badgeColor: "#4fa710",
        invertWheel: false,
        showDayNight: false,
        maxCountryStations: 500,
        maxSearchStations: 500,
        mpvPid: 4242,
        lastStation: "{}",
    });
    assert.deepEqual(plain(backup), {
        radioglobe: 1,
        favorites: [fip],
        history: [jazz],
        settings: {
            homeCountry: "FR",
            maxWorldStations: 3000,
            approximateLocations: false,
            mpvPath: "",
            sendClicks: true,
            icon: "map-globe",
            iconColor: "#226ce7",
            badgeColor: "#4fa710",
            invertWheel: false,
            showDayNight: false,
            maxCountryStations: 500,
            maxSearchStations: 500,
        },
    });
});

test("parseBackup round-trips what buildBackup produced", () => {
    const text = JSON.stringify(model.buildBackup([fip], [jazz], { homeCountry: "FR", sendClicks: false }));
    const result = model.parseBackup(text);
    assert.equal(result.ok, true);
    assert.deepEqual(plain(result.favorites), [fip]);
    assert.deepEqual(plain(result.history), [jazz]);
    assert.deepEqual(plain(result.settings), { homeCountry: "FR", sendClicks: false });
});

test("parseBackup rejects text that is not JSON", () => {
    const result = model.parseBackup("{ not json");
    assert.equal(result.ok, false);
    assert.equal(result.error, "invalid-json");
});

test("parseBackup rejects JSON that is not a RadioGlobe backup", () => {
    assert.equal(model.parseBackup("[]").error, "not-a-backup");
    assert.equal(model.parseBackup('{"favorites": []}').error, "not-a-backup");
    assert.equal(model.parseBackup('{"radioglobe": 1, "favorites": {}}').error, "not-a-backup");
});

test("parseBackup drops station rows without a uuid and unknown or mistyped settings", () => {
    const result = model.parseBackup(JSON.stringify({
        radioglobe: 1,
        favorites: [fip, { name: "no uuid" }, null, "text"],
        settings: { homeCountry: 12, maxWorldStations: "3000", invertWheel: true, mpvPid: 7, bogus: "x" },
    }));
    assert.equal(result.ok, true);
    assert.deepEqual(plain(result.favorites), [fip]);
    assert.deepEqual(plain(result.history), []);
    assert.deepEqual(plain(result.settings), { invertWheel: true });
});
