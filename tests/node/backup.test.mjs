import assert from "node:assert/strict";
import fs from "node:fs";
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
        restoreLastStation: true,
        autoplayLastStation: false,
        nextPreviousSource: "favorites",
        toolTipDelay: 150,
        zoomStep: 30,
        marqueeMode: "bounce",
        listSort: "votes",
        codecFilter: "mp3,aac",
        minBitrate: 128,
        sleepPersist: false,
        mpvPid: 4242,
        sleepUntil: 1790198123456,
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
            restoreLastStation: true,
            autoplayLastStation: false,
            nextPreviousSource: "favorites",
            toolTipDelay: 150,
            zoomStep: 30,
            marqueeMode: "bounce",
            listSort: "votes",
            codecFilter: "mp3,aac",
            minBitrate: 128,
            sleepPersist: false,
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

// Keys of the schema the backup leaves out on purpose: what the widget
// writes by itself as it runs. Favourites and history travel on their own.
const notSettings = ["favorites", "history", "lastStation", "volume", "mpvPid", "pinned", "sleepUntil",
    "popupWidth", "popupHeight", "configStartPage", "editStation"];

test("every option of the schema is in the backup, with its type", () => {
    const schema = fs.readFileSync(new URL("../../contents/config/main.xml", import.meta.url), "utf8");
    const jsType = { Bool: "boolean", Int: "number", Double: "number", String: "string" };
    const wrong = [];
    for (const [, name, type] of schema.matchAll(/<entry name="([^"]+)" type="([^"]+)"/g)) {
        const carried = model.backupSettingTypes[name];
        if (notSettings.includes(name) ? carried !== undefined : carried !== jsType[type])
            wrong.push(name + " (" + type + ")");
    }
    assert.deepEqual(wrong, []);
});
