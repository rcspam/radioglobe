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

// The time at the given offset, written with a Qt time format (see
// formatClock; "HH:mm" when none is given), or "" without an offset.
function formatLocalTime(nowMs, offsetMinutes, format, amText, pmText) {
    if (offsetMinutes === null || offsetMinutes === undefined || !isFinite(offsetMinutes))
        return "";
    var shifted = new Date(Number(nowMs) + offsetMinutes * 60000);
    return formatClock(format || "HH:mm", shifted.getUTCHours(), shifted.getUTCMinutes(), amText || "AM", pmText || "PM");
}

// Whether a Qt time format ("h:mm Ap", "HH:mm") shows AM/PM. Quoted text
// ("HH 'h' mm") is not a marker.
function usesTwelveHour(format) {
    return /a/i.test(String(format || "").replace(/'[^']*'/g, ""));
}

// The format for the "timeFormat" setting: "24", "12", or anything else for
// the system's own short format (seconds dropped, the clocks tick by minute).
function clockFormat(setting, systemFormat) {
    if (setting === "24")
        return "HH:mm";
    if (setting === "12")
        return "h:mm Ap";
    var format = String(systemFormat || "").replace(/[:.]ss?/g, "");
    return format || "HH:mm";
}

// Hours and minutes written with a Qt time format: H/HH (0-23), h/hh (1-12
// when the format shows AM/PM), m/mm, AP/A (upper case), ap/a (lower case),
// Ap (as the locale writes it), 'quoted text'. JavaScript cannot convert to
// another zone, so Qt's own formatting is of no use for a station's time.
function formatClock(format, hours, minutes, amText, pmText) {
    var text = String(format || "");
    var twelve = usesTwelveHour(text);
    var marker = hours < 12 ? String(amText) : String(pmText);
    var hour12 = hours % 12 === 0 ? 12 : hours % 12;
    var out = "";
    var i = 0;
    while (i < text.length) {
        var c = text.charAt(i);
        var pair = text.substr(i, 2);
        if (c === "'") {
            var end = text.indexOf("'", i + 1);
            if (end < 0)
                end = text.length;
            out += text.substring(i + 1, end);
            i = end + 1;
        } else if (pair === "AP") {
            out += marker.toUpperCase();
            i += 2;
        } else if (pair === "ap") {
            out += marker.toLowerCase();
            i += 2;
        } else if (pair === "Ap" || pair === "aP") {
            out += marker;
            i += 2;
        } else if (c === "A" || c === "a") {
            out += c === "A" ? marker.toUpperCase() : marker.toLowerCase();
            i += 1;
        } else if (c === "H" || c === "h" || c === "m") {
            var value = c === "m" ? minutes : (c === "h" && twelve ? hour12 : hours);
            var padded = pair === c + c;
            out += padded ? pad2(value) : String(value);
            i += padded ? 2 : 1;
        } else {
            out += c;
            i += 1;
        }
    }
    return out;
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
