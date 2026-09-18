.pragma library

// Finds a station's IANA time zone from the system's zone1970.tab and formats
// its local time. QML's JavaScript cannot convert to an arbitrary zone, so
// the UTC offset itself comes from `TZ=<zone> date +%z` (see LocalClock.qml);
// this file only does the pure parts, which the node tests cover.

// Parses /usr/share/zoneinfo/zone1970.tab: one line per zone, tab-separated
// country codes, ISO 6709 coordinates of a reference city, zone name,
// optional comment. Lines that do not fit are skipped.
function parseZoneTable(text) {
    var zones = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "" || line.charAt(0) === "#")
            continue;
        var fields = line.split("\t");
        if (fields.length < 3)
            continue;
        var point = parseCoordinates(fields[1]);
        if (!point)
            continue;
        var countries = fields[0].split(",");
        for (var c = 0; c < countries.length; c++)
            countries[c] = countries[c].trim().toUpperCase();
        zones.push({
            countries: countries,
            latitude: point.latitude,
            longitude: point.longitude,
            zone: fields[2].trim()
        });
    }
    return zones;
}

// "+4852+00220" or "+404251-0740023" (degrees, minutes, optional seconds).
function parseCoordinates(text) {
    var match = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(String(text || "").trim());
    if (!match)
        return null;
    var latitude = Number(match[2]) + Number(match[3]) / 60 + Number(match[4] || 0) / 3600;
    var longitude = Number(match[6]) + Number(match[7]) / 60 + Number(match[8] || 0) / 3600;
    return {
        latitude: match[1] === "-" ? -latitude : latitude,
        longitude: match[5] === "-" ? -longitude : longitude
    };
}

// The zone name for a station, or "" when nothing points to one. Zones that
// list the station's country first are its own; those where it is only a
// guest (Liechtenstein on Europe/Zurich) come next; with no country match at
// all, the nearest reference city anywhere. Within a rank, the nearest wins,
// and without coordinates the first listed, which the table puts first on
// purpose (most areas / most populous).
function zoneFor(zones, station) {
    var rows = Array.isArray(zones) ? zones : [];
    if (!station || rows.length === 0)
        return "";
    var country = String(station.countryCode || "").toUpperCase();
    var latitude = Number(station.latitude);
    var longitude = Number(station.longitude);
    var located = isFinite(latitude) && isFinite(longitude)
        && station.latitude !== null && station.longitude !== null
        && station.latitude !== undefined && station.longitude !== undefined;

    var own = [];
    var guest = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (country === "" || !row.countries)
            continue;
        if (row.countries[0] === country)
            own.push(row);
        else if (row.countries.indexOf(country) >= 0)
            guest.push(row);
    }
    var candidates = own.length ? own : guest;
    if (candidates.length === 0) {
        if (!located)
            return "";
        candidates = rows;
    }
    if (!located || candidates.length === 1)
        return candidates[0].zone;

    var best = candidates[0];
    var bestDistance = Infinity;
    for (var n = 0; n < candidates.length; n++) {
        var distance = angularDistance(latitude, longitude, candidates[n].latitude, candidates[n].longitude);
        if (distance < bestDistance) {
            bestDistance = distance;
            best = candidates[n];
        }
    }
    return best.zone;
}

// Great-circle distance in radians (haversine); the radius does not matter
// for ranking.
function angularDistance(lat1, lon1, lat2, lon2) {
    var toRadians = Math.PI / 180;
    var dLat = (lat2 - lat1) * toRadians;
    var dLon = (lon2 - lon1) * toRadians;
    var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
        + Math.cos(lat1 * toRadians) * Math.cos(lat2 * toRadians) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    return 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// Minutes east of UTC from `date +%z` output ("+0200", "-0330"), or null.
function parseUtcOffset(text) {
    var match = /^([+-])(\d{2})(\d{2})\s*$/.exec(String(text || ""));
    if (!match)
        return null;
    var minutes = Number(match[2]) * 60 + Number(match[3]);
    return match[1] === "-" ? -minutes : minutes;
}

// "HH:MM" at the given offset, or "" without one.
function formatLocalTime(nowMs, offsetMinutes) {
    if (offsetMinutes === null || offsetMinutes === undefined || !isFinite(offsetMinutes))
        return "";
    var shifted = new Date(Number(nowMs) + offsetMinutes * 60000);
    return pad2(shifted.getUTCHours()) + ":" + pad2(shifted.getUTCMinutes());
}

// "UTC", "UTC+2", "UTC-3:30", or "" without an offset.
function formatOffset(offsetMinutes) {
    if (offsetMinutes === null || offsetMinutes === undefined || !isFinite(offsetMinutes))
        return "";
    if (offsetMinutes === 0)
        return "UTC";
    var sign = offsetMinutes < 0 ? "-" : "+";
    var total = Math.abs(offsetMinutes);
    var hours = Math.floor(total / 60);
    var minutes = total % 60;
    return "UTC" + sign + hours + (minutes ? ":" + pad2(minutes) : "");
}

function pad2(value) {
    return (value < 10 ? "0" : "") + value;
}
