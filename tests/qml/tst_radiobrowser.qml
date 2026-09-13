import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "RadioBrowser"

    property var pending: []
    property var store: ({})
    property real clock: 1000000

    function fakeRequest(url, callback) {
        pending.push({
            url: url,
            callback: callback
        });
    }

    function answer(match, status, body) {
        for (let i = 0; i < pending.length; i++) {
            if (pending[i].url.indexOf(match) >= 0) {
                const job = pending.splice(i, 1)[0];
                job.callback(status, typeof body === "string" ? body : JSON.stringify(body));
                return job.url;
            }
        }
        fail("no pending request matching " + match + " in " + JSON.stringify(pending.map(p => p.url)));
    }

    property var fakeCache: ({
            get: function (key) {
                return store[key] === undefined ? null : store[key];
            },
            set: function (key, value, savedAt) {
                store[key] = {
                    value: value,
                    savedAt: savedAt
                };
            },
            remove: function (key) {
                delete store[key];
            }
        })

    function raw(uuid, extra) {
        const row = {
            stationuuid: uuid,
            name: "Radio " + uuid,
            url_resolved: "https://s/" + uuid,
            countrycode: "FR",
            codec: "MP3",
            bitrate: 128,
            geo_lat: 48,
            geo_long: 2,
            clickcount: 10
        };
        for (const k in extra)
            row[k] = extra[k];
        return row;
    }

    Ui.RadioBrowser {
        id: rb
        request: fakeRequest
        cache: fakeCache
        countries: []
        now: () => clock
        random: () => 0.5
        worldLimit: 6
        userAgentVersion: "0.1.0"
    }

    SignalSpy {
        id: updates
        target: rb
        signalName: "worldUpdated"
    }

    function init() {
        pending = [];
        store = ({});
        clock = 1000000;
        updates.clear();
        rb.reset();
    }

    function test_discovers_mirrors_and_loads_first_batch() {
        rb.start();
        answer("/json/servers", 200, [
            {
                name: "de1.api.radio-browser.info"
            },
            {
                name: "evil.example.org"
            }
        ]);
        const url = answer("/json/stations/search", 200, [raw("a"), raw("b")]);
        verify(url.indexOf("https://de1.api.radio-browser.info/json/stations/search?") === 0, url);
        verify(url.indexOf("has_geo_info=true") > 0);
        verify(url.indexOf("hidebroken=true") > 0);
        verify(url.indexOf("order=clickcount") > 0);
        verify(url.indexOf("reverse=true") > 0);
        verify(url.indexOf("limit=500") > 0);
        compare(rb.worldStations.length, 2);
        compare(rb.worldFromCache, false);
        compare(updates.count, 1);
        verify(store["world"] !== undefined);
    }

    function test_serves_cache_first_and_skips_network_when_fresh() {
        store["world"] = {
            value: [
                {
                    uuid: "c",
                    name: "Cached",
                    url: "https://s/c",
                    countryCode: "FR",
                    latitude: 1,
                    longitude: 1,
                    clicks: 1
                }
            ],
            savedAt: clock - 1000
        };
        rb.start();
        compare(rb.worldStations.length, 1);
        compare(rb.worldFromCache, true);
        compare(pending.length, 0);
    }

    function test_stale_cache_is_refreshed_in_background() {
        store["world"] = {
            value: [
                {
                    uuid: "c",
                    name: "Cached",
                    url: "https://s/c",
                    countryCode: "FR",
                    latitude: 1,
                    longitude: 1,
                    clicks: 1
                }
            ],
            savedAt: clock - 25 * 3600 * 1000
        };
        rb.start();
        compare(rb.worldStations.length, 1);
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        compare(rb.worldStations.map(s => s.uuid).sort().join(), "a,c");
    }

    function test_falls_back_to_next_mirror_then_all() {
        rb.start();
        answer("/json/servers", 200, [
            {
                name: "de1.api.radio-browser.info"
            },
            {
                name: "de2.api.radio-browser.info"
            }
        ]);
        answer("de1.api", 503, "");
        const url = answer("de2.api", 0, "");
        verify(url.indexOf("https://de2.api") === 0);
        answer("https://all.api.radio-browser.info/json/stations/search", 200, [raw("a")]);
        compare(rb.worldStations.length, 1);
        compare(rb.lastError, "");
    }

    function test_all_mirrors_failing_sets_offline() {
        rb.start();
        answer("/json/servers", 0, "");
        answer("https://all.api.radio-browser.info/json/stations/search", 0, "");
        compare(rb.lastError, "offline");
        compare(rb.worldStations.length, 0);
    }

    function test_expansion_uses_random_with_nonce_and_stops_when_dry() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        rb.expandWorld();
        const url = answer("order=random", 200, [raw("b")]);
        verify(url.indexOf("_=") > 0, url);
        compare(rb.worldStations.length, 2);
        answer("order=random", 200, [raw("b")]);
        answer("order=random", 200, []);
        answer("order=random", 0, "");
        compare(rb.expanding, false);
        compare(pending.length, 0);
    }

    function test_expansion_respects_world_limit() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a"), raw("b"), raw("c"), raw("d"), raw("e")]);
        rb.expandWorld();
        answer("order=random", 200, [raw("f"), raw("g"), raw("h")]);
        compare(rb.worldStations.length, 6);
        compare(rb.expanding, false);
    }

    function test_country_returns_local_then_network_and_caches() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a"), raw("z", {
                countrycode: "DE"
            })]);
        let calls = [];
        rb.loadCountry("fr", (stations, source) => calls.push({
                n: stations.length,
                source
            }));
        compare(calls[0].source, "local");
        compare(calls[0].n, 1);
        const url = answer("/json/stations/bycountrycodeexact/FR", 200, [raw("a"), raw("b")]);
        verify(url.indexOf("limit=25") > 0);
        compare(calls[1].source, "network");
        compare(calls[1].n, 2);
        verify(store["country:FR"] !== undefined);
        calls = [];
        rb.loadCountry("FR", (stations, source) => calls.push(source));
        compare(calls, ["local", "cache"]);
        compare(pending.length, 0);
    }

    function test_search_merges_three_requests_without_duplicates() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a", {
                name: "Jazz FM"
            })]);
        let results = [];
        rb.search("Jazz", (stations, isFinal) => results.push({
                n: stations.length,
                final: isFinal
            }));
        compare(results[0].final, false);
        compare(results[0].n, 1);
        answer("name=Jazz", 200, [raw("a", {
                name: "Jazz FM"
            }), raw("b")]);
        answer("country=Jazz", 200, []);
        answer("tag=jazz", 200, [raw("b"), raw("c")]);
        compare(results[1].final, true);
        compare(results[1].n, 3);
    }

    function test_newer_search_cancels_final_delivery_of_older_one() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, []);
        let finals = [];
        rb.search("one", (stations, isFinal) => {
            if (isFinal)
                finals.push("one");
        });
        rb.search("two", (stations, isFinal) => {
            if (isFinal)
                finals.push("two");
        });
        answer("name=one", 200, []);
        answer("country=one", 200, []);
        answer("tag=one", 200, []);
        answer("name=two", 200, []);
        answer("country=two", 200, []);
        answer("tag=two", 200, []);
        compare(finals, ["two"]);
    }

    function test_click_is_single_attempt_and_respects_toggle() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, []);
        rb.click("abc");
        answer("/json/url/abc", 0, "");
        compare(pending.length, 0);
        rb.sendClicks = false;
        rb.click("def");
        compare(pending.length, 0);
    }

    function test_background_refresh_updates_known_stations() {
        store["world"] = {
            value: [
                {
                    uuid: "a",
                    name: "Old",
                    url: "https://s/a",
                    countryCode: "FR",
                    latitude: 48,
                    longitude: 2,
                    clicks: 5
                }
            ],
            savedAt: clock - 25 * 3600 * 1000
        };
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a", {
                name: "New"
            })]);
        compare(rb.worldStations.find(s => s.uuid === "a").name, "New");
    }

    function test_overlap_spread_is_not_persisted() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a"), raw("b")]);
        const a = rb.worldStations.find(s => s.uuid === "a");
        const b = rb.worldStations.find(s => s.uuid === "b");
        verify(a.latitude !== b.latitude || a.longitude !== b.longitude, "expected spread apart coordinates");
        const stored = store["world"].value;
        const storedA = stored.find(s => s.uuid === "a");
        const storedB = stored.find(s => s.uuid === "b");
        compare(storedA.latitude, 48);
        compare(storedA.longitude, 2);
        compare(storedB.latitude, 48);
        compare(storedB.longitude, 2);
    }

    function test_cap_keeps_most_clicked_stations() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a", {
                clickcount: 100
            }), raw("b", {
                clickcount: 100
            }), raw("c", {
                clickcount: 100
            }), raw("d", {
                clickcount: 100
            }), raw("e", {
                clickcount: 100
            })]);
        rb.expandWorld();
        answer("order=random", 200, [raw("f", {
                clickcount: 1
            }), raw("g", {
                clickcount: 1
            }), raw("h", {
                clickcount: 1
            })]);
        compare(rb.worldStations.length, 6);
        const uuids = rb.worldStations.map(s => s.uuid);
        for (const uuid of ["a", "b", "c", "d", "e"])
            verify(uuids.indexOf(uuid) >= 0, uuid + " missing from " + uuids.join());
    }

    function test_reset_ignores_late_callbacks() {
        rb.start();
        answer("/json/servers", 200, []);
        rb.reset();
        updates.clear();
        answer("/json/stations/search", 200, [raw("a")]);
        compare(rb.worldStations.length, 0);
        compare(updates.count, 0);
        verify(store["world"] === undefined);
    }
}
