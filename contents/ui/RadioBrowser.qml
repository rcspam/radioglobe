import QtQuick
import "RadioModel.js" as RadioModel

// Radio Browser client: mirror discovery, world / country / search queries,
// click reporting and a 24 h cache. Every outside dependency is injected so
// the component runs under qmltestrunner with fakes.
Item {
    id: root

    visible: false

    property var request: null
    property var cache: null
    property var countries: []
    property var now: function () {
        return Date.now();
    }
    property var random: function () {
        return Math.random();
    }
    property int worldLimit: 3000
    property int cacheTtlMs: 24 * 3600 * 1000
    property bool sendClicks: true
    property string userAgentVersion: "0.0.0"

    readonly property string allMirror: "https://all.api.radio-browser.info"
    readonly property var worldStations: root._world
    readonly property bool worldFromCache: root._worldFromCache
    readonly property bool expanding: root._expanding
    readonly property string lastError: root._lastError

    signal worldUpdated

    property var _world: []
    property bool _worldFromCache: false
    property bool _expanding: false
    property string _lastError: ""
    property var _mirrors: []
    property bool _discovered: false
    property var _afterDiscovery: []
    property int _dryRounds: 0
    property int _searchGeneration: 0
    property bool _started: false

    function reset() {
        root._world = [];
        root._worldFromCache = false;
        root._expanding = false;
        root._lastError = "";
        root._mirrors = [];
        root._discovered = false;
        root._afterDiscovery = [];
        root._dryRounds = 0;
        root._searchGeneration = 0;
        root._started = false;
    }

    function start() {
        if (root._started)
            return;
        root._started = true;
        const cached = root.cache ? root.cache.get("world") : null;
        if (cached && Array.isArray(cached.value) && cached.value.length > 0) {
            root._world = cached.value;
            root._worldFromCache = true;
            root.worldUpdated();
            if (root.now() - cached.savedAt < root.cacheTtlMs)
                return;
        }
        root._api("/json/stations/search", {
            has_geo_info: true,
            hidebroken: true,
            order: "clickcount",
            reverse: true,
            limit: 500
        }, rows => {
            if (rows === null)
                return;
            root._absorb(rows, false);
        });
    }

    function expandWorld() {
        if (root._expanding || root._world.length >= root.worldLimit)
            return;
        root._expanding = true;
        root._dryRounds = 0;
        root._expandRound();
    }

    function loadCountry(code, callback) {
        const wanted = String(code || "").toUpperCase();
        if (!wanted)
            return;
        const local = RadioModel.stationsForCountry(root._world, wanted, 200);
        if (local.length > 0)
            callback(local, "local");
        const key = "country:" + wanted;
        const cached = root.cache ? root.cache.get(key) : null;
        if (cached && Array.isArray(cached.value) && root.now() - cached.savedAt < root.cacheTtlMs) {
            callback(cached.value, "cache");
            return;
        }
        root._api("/json/stations/bycountrycodeexact/" + wanted, {
            hidebroken: true,
            order: "clickcount",
            reverse: true,
            limit: 25
        }, rows => {
            if (rows === null)
                return;
            const stations = root._locate(RadioModel.normalizeStations(rows, 25));
            if (root.cache)
                root.cache.set(key, stations, root.now());
            callback(stations, "network");
        });
    }

    function search(query, callback) {
        const text = String(query || "").trim();
        if (!text)
            return;
        root._searchGeneration += 1;
        const generation = root._searchGeneration;
        callback(RadioModel.searchStations(root._world, text, 80), false);
        const groups = [null, null, null];
        let remaining = 3;
        const common = {
            hidebroken: true,
            order: "clickcount",
            reverse: true,
            limit: 80
        };
        const variants = [
            {
                name: text
            },
            {
                country: text
            },
            {
                tag: text.toLowerCase()
            }
        ];
        variants.forEach((filter, index) => {
            const params = Object.assign({}, common, filter);
            root._api("/json/stations/search", params, rows => {
                groups[index] = rows === null ? [] : RadioModel.normalizeStations(rows, 80);
                remaining -= 1;
                if (remaining > 0 || generation !== root._searchGeneration)
                    return;
                const merged = RadioModel.combineStations(groups, 240, false);
                merged.sort((a, b) => (Number(b.clicks) || 0) - (Number(a.clicks) || 0));
                callback(root._locate(merged), true);
            });
        });
    }

    function click(uuid) {
        if (!root.sendClicks || !uuid)
            return;
        const base = root._mirrors.length > 0 ? root._mirrors[0] : root.allMirror;
        root.request(base + "/json/url/" + encodeURIComponent(String(uuid)), function () {});
    }

    function _expandRound() {
        if (root._dryRounds >= 3 || root._world.length >= root.worldLimit) {
            root._expanding = false;
            return;
        }
        root._api("/json/stations/search", {
            has_geo_info: true,
            hidebroken: true,
            order: "random",
            limit: 500,
            _: Math.floor(root.random() * 1e9) + "" + root._world.length
        }, rows => {
            const before = root._world.length;
            if (rows !== null && rows.length > 0)
                root._absorb(rows, true);
            if (rows === null || root._world.length === before)
                root._dryRounds += 1;
            else
                root._dryRounds = 0;
            root._expandRound();
        });
    }

    function _absorb(rows, background) {
        const fresh = RadioModel.dedupeByUrl(RadioModel.normalizeStations(rows, 500));
        const merged = RadioModel.mergeGeoStations(fresh, root._world, root.countries);
        root._world = RadioModel.spreadOverlapping(merged.slice(0, Math.max(1, root.worldLimit)));
        root._worldFromCache = false;
        if (root.cache)
            root.cache.set("world", root._world, root.now());
        root.worldUpdated();
    }

    function _locate(stations) {
        return RadioModel.mergeGeoStations(stations, [], root.countries);
    }

    // Calls callback(rows) with the parsed JSON array, or callback(null) when
    // every mirror failed. Mirrors are tried in order on status 0, 429, 5xx.
    function _api(path, params, callback) {
        if (!root._discovered) {
            root._afterDiscovery.push(() => root._api(path, params, callback));
            root._discover();
            return;
        }
        const query = RadioModel.buildQuery(params);
        const mirrors = root._mirrors.slice();
        const attempt = index => {
            if (index >= mirrors.length) {
                root._lastError = "offline";
                callback(null);
                return;
            }
            root.request(mirrors[index] + path + (query ? "?" + query : ""), (status, text) => {
                if (status === 0 || status === 429 || status >= 500) {
                    attempt(index + 1);
                    return;
                }
                let rows = null;
                try {
                    rows = status === 200 ? JSON.parse(text) : null;
                } catch (error) {
                    rows = null;
                }
                if (!Array.isArray(rows)) {
                    attempt(index + 1);
                    return;
                }
                root._lastError = "";
                callback(rows);
            });
        };
        attempt(0);
    }

    function _discover() {
        if (root._afterDiscovery.length > 1)
            return;
        root.request(root.allMirror + "/json/servers", (status, text) => {
            const names = [];
            try {
                const rows = status === 200 ? JSON.parse(text) : [];
                for (const row of rows) {
                    const name = String(row && row.name || "");
                    if (RadioModel.validMirrorName(name) && names.indexOf(name) < 0)
                        names.push(name);
                }
            } catch (error) {}
            root._mirrors = names.map(name => "https://" + name).concat([root.allMirror]);
            root._discovered = true;
            const queued = root._afterDiscovery;
            root._afterDiscovery = [];
            for (const run of queued)
                run();
        });
    }
}
