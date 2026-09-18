import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "RadioBrowser"

    property var pending: []
    property var store: ({})
    // Cache writes per key, so a test can tell "written once" from "written
    // on every round".
    property var writes: ({})
    property real clock: 1000000

    function fakeRequest(url, callback, options) {
        pending.push({
            url: url,
            callback: callback,
            options: options || null
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
                writes[key] = (writes[key] || 0) + 1;
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
        writes = ({});
        clock = 1000000;
        updates.clear();
        rb.reset();
        rb.homeCountry = "";
        rb.approximateLocations = false;
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
        verify(store[rb.worldKey()] !== undefined);
    }

    // QtQuick.LocalStorage is not installed on a stock Kubuntu: without a cache
    // the world still loads from the network, nothing is written anywhere.
    function test_vote_reports_ok_and_refusals() {
        const results = [];
        rb.vote("abc", ok => results.push(ok));
        answer("/json/servers", 200, [
            {
                name: "de1.api.radio-browser.info"
            }
        ]);
        const url = answer("/json/vote/abc", 200, {
            ok: true,
            message: "voted for station successfully"
        });
        compare(url, "https://de1.api.radio-browser.info/json/vote/abc");
        compare(results, [true]);
        rb.vote("abc", ok => results.push(ok));
        answer("/json/vote/abc", 200, {
            ok: false,
            message: "you are voting for the same station too often"
        });
        compare(results, [true, false]);
        // Radio Browser sends "ok" as a string in some versions.
        rb.vote("abc", ok => results.push(ok));
        answer("/json/vote/abc", 200, {
            ok: "true",
            message: "voted"
        });
        compare(results, [true, false, true]);
        // Nothing to vote for: no request.
        const before = pending.length;
        rb.vote("", ok => results.push(ok));
        compare(pending.length, before);
    }

    function test_works_without_a_cache() {
        rb.cache = null;
        rb.start();
        answer("/json/servers", 200, [
            {
                name: "de1.api.radio-browser.info"
            }
        ]);
        answer("/json/stations/search", 200, [raw("a"), raw("b")]);
        compare(rb.worldStations.length, 2);
        compare(rb.worldFromCache, false);
        compare(Object.keys(store).length, 0);
        rb.cache = fakeCache;
    }

    function test_serves_cache_first_and_skips_network_when_fresh() {
        store[rb.worldKey()] = {
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
        store[rb.worldKey()] = {
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

    function test_refresh_retries_after_going_offline() {
        rb.start();
        answer("/json/servers", 0, "");
        answer("https://all.api.radio-browser.info/json/stations/search", 0, "");
        compare(rb.lastError, "offline");
        compare(pending.length, 0);
        rb.refresh();
        compare(rb.lastError, "");
        verify(pending.length > 0, "refresh issued no request");
        answer("/json/stations/search", 200, [raw("a")]);
        compare(rb.lastError, "");
        compare(rb.worldStations.length, 1);
    }

    function test_refresh_goes_to_the_network_even_on_a_fresh_cache() {
        store[rb.worldKey()] = {
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
        compare(pending.length, 0);
        rb.refresh();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        compare(rb.worldStations.map(s => s.uuid).sort().join(), "a,c");
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

    // Each write is a JSON.stringify of the whole world plus a synchronous
    // SQLite write, and it used to happen on every round of the expansion.
    function test_expansion_writes_the_cache_once_at_each_end() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        compare(writes[rb.worldKey()], 1);

        rb.expandWorld();
        // The first round still writes: a start interrupted halfway has to
        // leave something usable in the cache.
        answer("order=random", 200, [raw("b")]);
        compare(writes[rb.worldKey()], 2);
        answer("order=random", 200, [raw("c")]);
        answer("order=random", 200, [raw("d")]);
        compare(writes[rb.worldKey()], 2);
        compare(rb.worldStations.length, 4);
        // worldUpdated still fires on every round, the globe needs it.
        compare(updates.count, 4);

        // Three dry rounds end the expansion, which flushes once.
        answer("order=random", 200, [raw("d")]);
        answer("order=random", 200, []);
        answer("order=random", 0, "");
        compare(rb.expanding, false);
        compare(writes[rb.worldKey()], 3);
        compare(store[rb.worldKey()].value.length, 4);
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
                first: stations[0].uuid,
                source
            }));
        // No early wave from the world list: everything lands at once.
        compare(calls.length, 0);
        // Two requests: the 300 most clicked for the list, and the located
        // ones for the globe (the popular ones rarely have coordinates).
        const url = answer("/json/stations/bycountrycodeexact/FR", 200, [raw("a"), raw("b")]);
        verify(url.indexOf("limit=300") > 0);
        compare(calls.length, 0, "the list waits for both answers");
        const geoUrl = answer("/json/stations/search", 200, [raw("b", {
                clickcount: 9
            }), raw("c", {
                geo_lat: 48.8,
                geo_long: 2.3,
                clickcount: 50
            })]);
        verify(geoUrl.indexOf("countrycode=FR") > 0, geoUrl);
        verify(geoUrl.indexOf("has_geo_info=true") > 0, geoUrl);
        verify(geoUrl.indexOf("limit=500") > 0, geoUrl);
        compare(calls[0].source, "network");
        // a, b, c merged without duplicates, most clicked first.
        compare(calls[0].n, 3);
        compare(calls[0].first, "c");
        verify(store["country:FR:300+500"] !== undefined);
        calls = [];
        rb.loadCountry("FR", (stations, source) => calls.push(source));
        compare(calls, ["cache"]);
        compare(pending.length, 0);
    }

    // Offline, the stations of the country already in the world list are
    // better than nothing.
    function test_country_falls_back_to_the_world_list_when_the_network_fails() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a"), raw("z", {
                countrycode: "DE"
            })]);
        const calls = [];
        rb.loadCountry("FR", (stations, source) => calls.push({
                n: stations.length,
                source
            }));
        answer("/json/stations/bycountrycodeexact/FR", 500, "");
        answer("/json/stations/search", 500, "");
        compare(calls.length, 1);
        compare(calls[0].source, "local");
        compare(calls[0].n, 1);
    }

    // The setting drives how many located stations a country asks for.
    function test_country_limit_setting() {
        rb.countryStationLimit = 200;
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        rb.loadCountry("FR", () => {});
        answer("/json/stations/bycountrycodeexact/FR", 200, [raw("f")]);
        const geoUrl = answer("/json/stations/search", 200, []);
        verify(geoUrl.indexOf("limit=200") > 0, geoUrl);
        verify(store["country:FR:300+200"] !== undefined);
        rb.countryStationLimit = 500;
    }

    // And the search has its own.
    function test_search_limit_setting() {
        rb.searchStationLimit = 250;
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, []);
        rb.search("Jazz", () => {});
        answer("name=Jazz", 200, []);
        answer("country=Jazz", 200, []);
        answer("tag=jazz", 200, []);
        const geoUrl = answer("name=Jazz", 200, []);
        verify(geoUrl.indexOf("limit=250") > 0, geoUrl);
        answer("tag=jazz", 200, []);
        rb.searchStationLimit = 500;
    }

    // A big country gets more located stations.
    function test_big_country_asks_for_more_located_stations() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        rb.loadCountry("US", () => {});
        answer("/json/stations/bycountrycodeexact/US", 200, [raw("u")]);
        const geoUrl = answer("/json/stations/search", 200, []);
        verify(geoUrl.indexOf("limit=1500") > 0, geoUrl);
    }

    // An upgrading user has a fresh world cache that predates the home
    // country: start() must still go and get it instead of waiting a day.
    function test_fresh_cache_still_loads_a_missing_home_country() {
        store[rb.worldKey()] = {
            value: [
                {
                    uuid: "d1",
                    name: "Cached",
                    url: "https://s/d1",
                    countryCode: "DE",
                    latitude: 50,
                    longitude: 8,
                    clicks: 5
                }
            ],
            savedAt: clock - 1000
        };
        rb.homeCountry = "FR";
        rb.start();
        answer("/json/servers", 200, []);
        compare(pending.length, 1);
        verify(pending[0].url.indexOf("/json/stations/bycountrycodeexact/FR") > 0, pending[0].url);
        verify(pending[0].url.indexOf("/json/stations/search") < 0, pending[0].url);
    }

    function test_fresh_cache_skips_home_when_already_present() {
        const rows = [];
        for (let i = 0; i < 20; i++)
            rows.push({
                uuid: "f" + i,
                name: "Cached " + i,
                url: "https://s/f" + i,
                countryCode: "FR",
                latitude: 48,
                longitude: 2,
                clicks: 5
            });
        store[rb.worldKey()] = {
            value: rows,
            savedAt: clock - 1000
        };
        rb.homeCountry = "FR";
        rb.start();
        compare(rb.worldFromCache, true);
        compare(pending.length, 0);
    }

    function test_home_country_is_loaded_after_the_world_batch() {
        rb.homeCountry = "FR";
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a", {
                countrycode: "DE"
            })]);
        const url = answer("/json/stations/bycountrycodeexact/FR", 200, [raw("f1"), raw("f2"), raw("f3")]);
        verify(url.indexOf("has_geo_info=true") > 0, url);
        verify(url.indexOf("limit=1000") > 0, url);
        const uuids = rb.worldStations.map(s => s.uuid);
        for (const uuid of ["f1", "f2", "f3"])
            verify(uuids.indexOf(uuid) >= 0, uuid + " missing from " + uuids.join());
        compare(pending.length, 0);
    }

    // With approximate locations on, the home country comes whole and the
    // stations without coordinates get a spot inside the country's borders.
    function test_approximate_locations_load_the_home_country_whole() {
        rb.homeCountry = "FR";
        rb.approximateLocations = true;
        rb.countries = [
            {
                properties: {
                    code: "FR"
                },
                geometry: {
                    type: "Polygon",
                    coordinates: [[[-2, 43], [7, 43], [7, 50], [-2, 50], [-2, 43]]]
                }
            }
        ];
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a", {
                countrycode: "DE"
            })]);
        const url = answer("/json/stations/bycountrycodeexact/FR", 200, [raw("f1"), raw("f3", {
                geo_lat: null,
                geo_long: null
            })]);
        verify(url.indexOf("has_geo_info") < 0, url);
        const estimated = rb.worldStations.find(s => s.uuid === "f3");
        verify(estimated !== undefined, "unlocated home station kept");
        compare(estimated.estimatedLocation, true);
        verify(estimated.latitude > 43 && estimated.latitude < 50, "inside the country: " + estimated.latitude);
        verify(store["world:3:approximate"] !== undefined, "own cache key");
        compare(store["world:3"], undefined);
        // Switching the option off starts the world over: the approximate
        // rows must not survive.
        rb.approximateLocations = false;
        answer("/json/stations/search", 200, [raw("b")]);
        answer("/json/stations/bycountrycodeexact/FR", 200, [raw("f1")]);
        verify(rb.worldStations.every(s => s.uuid !== "f3"), "approximate row gone: " + rb.worldStations.map(s => s.uuid).join());
        rb.countries = [];
    }

    function test_home_country_stations_survive_the_cap() {
        rb.homeCountry = "FR";
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("d1", {
                countrycode: "DE",
                clickcount: 100
            }), raw("d2", {
                countrycode: "DE",
                clickcount: 99
            }), raw("d3", {
                countrycode: "DE",
                clickcount: 98
            }), raw("d4", {
                countrycode: "DE",
                clickcount: 97
            }), raw("d5", {
                countrycode: "DE",
                clickcount: 96
            })]);
        answer("bycountrycodeexact/FR", 200, [raw("f1", {
                clickcount: 1
            }), raw("f2", {
                clickcount: 1
            }), raw("f3", {
                clickcount: 1
            })]);
        compare(rb.worldStations.length, 6);
        compare(rb.worldStations.map(s => s.uuid).sort().join(), "d1,d2,d3,f1,f2,f3");
    }

    function test_changing_home_country_loads_it_live() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        compare(pending.length, 0);
        rb.homeCountry = "DE";
        const url = answer("bycountrycodeexact/DE", 200, [raw("d", {
                countrycode: "DE"
            })]);
        verify(url.indexOf("limit=1000") > 0, url);
        verify(rb.worldStations.map(s => s.uuid).indexOf("d") >= 0);
    }

    function test_no_home_request_without_a_valid_code() {
        rb.homeCountry = "FRA";
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a")]);
        compare(pending.length, 0);
        rb.homeCountry = "";
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
        // Plus the located ones, by name and by tag, so the globe fills up:
        // the popular results rarely have coordinates.
        compare(results.length, 1, "waits for the located requests");
        const geoName = answer("name=Jazz", 200, [raw("d")]);
        verify(geoName.indexOf("has_geo_info=true") > 0, geoName);
        verify(geoName.indexOf("limit=500") > 0, geoName);
        answer("tag=jazz", 200, [raw("d"), raw("e")]);
        compare(results[1].final, true);
        compare(results[1].n, 5);
    }

    // "fr" is an ISO code, not a station name: a fourth request looks it up.
    // With a country open, the search stays inside it: the local pass only
    // looks at that country's stations, the requests carry its code, and the
    // "is it a country name" variants are pointless.
    function test_search_inside_a_country() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, [raw("a", {
                name: "Jazz FM"
            }), raw("z", {
                name: "Jazz Berlin",
                countrycode: "DE"
            })]);
        let results = [];
        rb.search("Jazz", (stations, isFinal) => results.push({
                uuids: stations.map(s => s.uuid).join(","),
                final: isFinal
            }), "FR");
        compare(results[0].final, false);
        compare(results[0].uuids, "a");
        compare(pending.length, 4, pending.map(p => p.url).join(", "));
        verify(pending.every(p => p.url.indexOf("countrycode=FR") > 0), pending.map(p => p.url).join(", "));
        verify(!pending.some(p => p.url.indexOf("country=Jazz") > 0));
        answer("name=Jazz", 200, [raw("a", {
                name: "Jazz FM"
            })]);
        answer("tag=jazz", 200, [raw("c")]);
        answer("name=Jazz", 200, []);
        answer("tag=jazz", 200, [raw("d")]);
        compare(results[1].final, true);
        compare(results[1].uuids, "a,c,d");
    }

    // In a large country the located requests ask for more.
    function test_search_inside_a_big_country_asks_for_more_located_stations() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, []);
        rb.search("Jazz", () => {}, "US");
        answer("name=Jazz", 200, []);
        answer("tag=jazz", 200, []);
        const geoName = answer("name=Jazz", 200, []);
        verify(geoName.indexOf("limit=1500") > 0, geoName);
        answer("tag=jazz", 200, []);
        compare(pending.length, 0);
    }

    function test_two_letter_search_also_asks_for_the_country_code() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, []);
        let finals = [];
        rb.search("fr", (stations, isFinal) => finals.push(isFinal));
        answer("name=fr", 200, []);
        answer("country=Fr", 200, []);
        answer("tag=fr", 200, []);
        answer("name=fr", 200, []);
        answer("tag=fr", 200, []);
        compare(finals.indexOf(true), -1, "delivered before the country code answered");
        const url = answer("countrycode=FR", 200, [raw("a")]);
        verify(url.indexOf("countrycode=FR") > 0, url);
        compare(finals[finals.length - 1], true);
        compare(pending.length, 0);
    }

    function test_longer_search_keeps_three_requests() {
        rb.start();
        answer("/json/servers", 200, []);
        answer("/json/stations/search", 200, []);
        rb.search("jazz", () => {});
        // name, country, tag, plus name and tag among the located stations
        compare(pending.length, 5);
        verify(pending.some(p => p.url.indexOf("country=Jazz") > 0), pending.map(p => p.url).join(", "));
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
        answer("country=One", 200, []);
        answer("tag=one", 200, []);
        answer("name=one", 200, []);
        answer("tag=one", 200, []);
        answer("name=two", 200, []);
        answer("country=Two", 200, []);
        answer("tag=two", 200, []);
        answer("name=two", 200, []);
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
        store[rb.worldKey()] = {
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
        const stored = store[rb.worldKey()].value;
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
        verify(store[rb.worldKey()] === undefined);
    }

    function test_stale_discovery_response_keeps_discovering_flag() {
        rb.start();
        // Discovery request "A" is now pending. Reset before it answers, then
        // start() again: this issues a second, live discovery request "B".
        rb.reset();
        rb.start();
        compare(pending.length, 2);
        // Answer the stale one first (it is first in the queue): its epoch no
        // longer matches, so it must be ignored without touching the
        // discovering flag that belongs to the still-in-flight "B".
        answer("/json/servers", 200, []);
        compare(pending.length, 1);
        // Any further request while "B" is still in flight must not start a
        // third discovery: that would happen if the stale response above had
        // cleared the discovering flag.
        rb.loadCountry("FR", () => {});
        compare(pending.length, 1, "a stale discovery response must not re-open the discovering gate");
        verify(pending[0].url.indexOf("/json/servers") >= 0, pending[0].url);
        // Resolving "B" flushes the queued callers (the original world fetch
        // and the two requests of the loadCountry() call above); none is a
        // further discovery.
        answer("/json/servers", 200, []);
        compare(pending.length, 3);
        const urls = pending.map(p => p.url);
        verify(urls.some(u => u.indexOf("/json/stations/search") >= 0), urls.join(", "));
        verify(urls.every(u => u.indexOf("/json/servers") < 0), urls.join(", "));
    }

    function test_non_retryable_status_calls_back_null_without_failover() {
        rb.start();
        answer("/json/servers", 200, [
            {
                name: "de1.api.radio-browser.info"
            }
        ]);
        const url = answer("/json/stations/search", 404, "");
        verify(url.indexOf("https://de1.api.radio-browser.info") === 0, url);
        compare(pending.length, 0);
        compare(rb.worldStations.length, 0);
        compare(rb.lastError, "");
    }

    function submitForm() {
        return {
            name: "Radio Test",
            url: "https://stream.example.org/live",
            countryCode: "FR",
            latitude: "48.85",
            longitude: "2.35"
        };
    }

    function test_submit_returns_the_existing_station_without_posting() {
        let result = null;
        rb.submit(submitForm(), r => {
            result = r;
        });
        answer("/json/servers", 200, [
            {
                name: "m1.api.radio-browser.info"
            }
        ]);
        const url = answer("/json/stations/byurl", 200, [raw("known")]);
        verify(url.indexOf("url=https%3A%2F%2Fstream.example.org%2Flive") >= 0, url);
        compare(pending[0] === undefined ? null : pending[0].options, null);
        compare(result.status, "exists");
        compare(result.station.uuid, "known");
        compare(pending.length, 0);
    }

    function test_submit_posts_and_returns_the_new_uuid() {
        let result = null;
        rb.submit(submitForm(), r => {
            result = r;
        });
        answer("/json/servers", 200, [
            {
                name: "m1.api.radio-browser.info"
            }
        ]);
        answer("/json/stations/byurl", 200, []);
        compare(pending.length, 1);
        compare(pending[0].url, "https://m1.api.radio-browser.info/json/add");
        compare(pending[0].options.method, "POST");
        compare(pending[0].options.body, "name=Radio%20Test&url=https%3A%2F%2Fstream.example.org%2Flive&countrycode=FR&geo_lat=48.85&geo_long=2.35");
        answer("/json/add", 200, {
            ok: true,
            message: "station was added",
            uuid: "new-1"
        });
        compare(result.status, "added");
        compare(result.uuid, "new-1");
    }

    function test_submit_reports_a_refusal() {
        let result = null;
        rb.submit(submitForm(), r => {
            result = r;
        });
        answer("/json/servers", 200, [
            {
                name: "m1.api.radio-browser.info"
            }
        ]);
        answer("/json/stations/byurl", 200, []);
        answer("/json/add", 200, {
            ok: false,
            message: "StationUrlInvalid"
        });
        compare(result.status, "error");
        compare(result.message, "StationUrlInvalid");
    }

    function test_submit_falls_back_to_the_next_mirror_and_reports_offline() {
        let result = null;
        rb.submit(submitForm(), r => {
            result = r;
        });
        answer("/json/servers", 200, [
            {
                name: "m1.api.radio-browser.info"
            },
            {
                name: "m2.api.radio-browser.info"
            }
        ]);
        // A mirror without the route is not an outage: the check is skipped.
        answer("/json/stations/byurl", 404, "");
        answer("m1.api.radio-browser.info/json/add", 500, "");
        answer("m2.api.radio-browser.info/json/add", 0, "");
        answer("all.api.radio-browser.info/json/add", 0, "");
        compare(result.status, "offline");
        compare(pending.length, 0);
    }

    function test_submit_reports_offline_when_the_check_itself_fails() {
        let result = null;
        rb.submit(submitForm(), r => {
            result = r;
        });
        answer("/json/servers", 200, [
            {
                name: "m1.api.radio-browser.info"
            }
        ]);
        answer("m1.api.radio-browser.info/json/stations/byurl", 0, "");
        answer("all.api.radio-browser.info/json/stations/byurl", 0, "");
        compare(result.status, "offline");
        compare(pending.length, 0);
    }

    function test_submit_rejects_an_invalid_form_without_network() {
        let result = null;
        rb.submit({
            name: "",
            url: "https://a/b"
        }, r => {
            result = r;
        });
        compare(result.status, "error");
        compare(pending.length, 0);
    }
}
