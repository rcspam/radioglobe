import assert from "node:assert/strict";
import { test } from "node:test";
import { loadQmlJs } from "./qmljs.mjs";

const tz = loadQmlJs("contents/ui/TimeZones.js");

// A slice of /usr/share/zoneinfo/zone1970.tab, comments and blanks included.
const table = `# tzdb timezone descriptions
#
#codes\tcoordinates\tTZ\tcomments
AU\t-3352+15113\tAustralia/Sydney\tNew South Wales (most areas)
AU\t-3157+11551\tAustralia/Perth\tWestern Australia (most areas)

CH,DE,LI\t+4723+00832\tEurope/Zurich\tBüsingen
DE,DK,NO,SE,SJ\t+5230+01322\tEurope/Berlin\tmost of Germany
FR,MC\t+4852+00220\tEurope/Paris
IN\t+2232+08822\tAsia/Kolkata
US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)
US\t+415100-0873900\tAmerica/Chicago\tCentral (most areas)
US\t+340308-1181434\tAmerica/Los_Angeles\tPacific
`;

test("parseZoneTable reads codes, coordinates and zone names", () => {
  const zones = JSON.parse(JSON.stringify(tz.parseZoneTable(table)));
  assert.equal(zones.length, 9);
  assert.deepEqual(zones[2], {
    countries: ["CH", "DE", "LI"],
    latitude: 47 + 23 / 60,
    longitude: 8 + 32 / 60,
    zone: "Europe/Zurich"
  });
  // Seconds are read too, and the minus sign is kept.
  const newYork = zones[6];
  assert.equal(newYork.zone, "America/New_York");
  assert.ok(Math.abs(newYork.latitude - 40.714) < 0.001);
  assert.ok(Math.abs(newYork.longitude + 74.006) < 0.001);
  const sydney = zones[0];
  assert.ok(Math.abs(sydney.latitude + 33.867) < 0.001);
  assert.deepEqual(JSON.parse(JSON.stringify(tz.parseZoneTable(""))), []);
  assert.deepEqual(JSON.parse(JSON.stringify(tz.parseZoneTable("garbage\nAB\tnope\tZone\n"))), []);
});

test("zoneFor prefers the country's own zones, nearest to the station", () => {
  const zones = tz.parseZoneTable(table);
  // Single-zone country, coordinates or not.
  assert.equal(tz.zoneFor(zones, { countryCode: "FR", latitude: 43.3, longitude: 5.4 }), "Europe/Paris");
  assert.equal(tz.zoneFor(zones, { countryCode: "fr" }), "Europe/Paris");
  // Multi-zone country: nearest reference point.
  assert.equal(tz.zoneFor(zones, { countryCode: "US", latitude: 37.77, longitude: -122.42 }), "America/Los_Angeles");
  assert.equal(tz.zoneFor(zones, { countryCode: "US", latitude: 42.36, longitude: -71.06 }), "America/New_York");
  assert.equal(tz.zoneFor(zones, { countryCode: "AU", latitude: -31.95, longitude: 115.86 }), "Australia/Perth");
  // Without coordinates the first zone listed for the country wins.
  assert.equal(tz.zoneFor(zones, { countryCode: "US" }), "America/New_York");
  // A zone naming the country first beats one where it is a guest: Munich is
  // nearer Zurich than Berlin, but Germany's own zone is Europe/Berlin.
  assert.equal(tz.zoneFor(zones, { countryCode: "DE", latitude: 48.14, longitude: 11.58 }), "Europe/Berlin");
  assert.equal(tz.zoneFor(zones, { countryCode: "DE" }), "Europe/Berlin");
  // Liechtenstein has no zone of its own and takes Zurich.
  assert.equal(tz.zoneFor(zones, { countryCode: "LI" }), "Europe/Zurich");
  // Unknown country with coordinates: nearest zone anywhere.
  assert.equal(tz.zoneFor(zones, { countryCode: "XK", latitude: 42.66, longitude: 21.17 }), "Europe/Zurich");
  assert.equal(tz.zoneFor(zones, { latitude: 19.07, longitude: 72.88 }), "Asia/Kolkata");
  // Nothing to go on.
  assert.equal(tz.zoneFor(zones, { countryCode: "XK" }), "");
  assert.equal(tz.zoneFor(zones, {}), "");
  assert.equal(tz.zoneFor(zones, null), "");
  assert.equal(tz.zoneFor([], { countryCode: "FR" }), "");
});

test("parseUtcOffset reads the output of date +%z", () => {
  assert.equal(tz.parseUtcOffset("+0200\n"), 120);
  assert.equal(tz.parseUtcOffset("-0330"), -210);
  assert.equal(tz.parseUtcOffset("+0545"), 345);
  assert.equal(tz.parseUtcOffset("+0000"), 0);
  assert.equal(tz.parseUtcOffset(""), null);
  assert.equal(tz.parseUtcOffset("garbage"), null);
  assert.equal(tz.parseUtcOffset(null), null);
});

test("formatLocalTime and formatOffset", () => {
  const noonUtc = Date.UTC(2026, 8, 18, 12, 0, 0);
  assert.equal(tz.formatLocalTime(noonUtc, 120), "14:00");
  assert.equal(tz.formatLocalTime(noonUtc, -210), "08:30");
  assert.equal(tz.formatLocalTime(noonUtc, 345), "17:45");
  // Crossing midnight wraps.
  assert.equal(tz.formatLocalTime(Date.UTC(2026, 8, 18, 23, 30, 0), 120), "01:30");
  assert.equal(tz.formatLocalTime(noonUtc, null), "");
  assert.equal(tz.formatOffset(0), "UTC");
  assert.equal(tz.formatOffset(120), "UTC+2");
  assert.equal(tz.formatOffset(-210), "UTC-3:30");
  assert.equal(tz.formatOffset(345), "UTC+5:45");
  assert.equal(tz.formatOffset(null), "");
});
