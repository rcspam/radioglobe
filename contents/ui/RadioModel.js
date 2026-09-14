// Pure helpers shared by the QML views and the node tests.
// Origin: Radio Atlas (MIT, Akshar Patel). Keep this file free of Qt globals
// and at ES2016 level (+ ?? and ?.) so both engines load it.

var radians = Math.PI / 180
var degrees = 180 / Math.PI
var estimatedLocationCache = ({})

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function wrapLongitude(value) {
  var wrapped = (value + 180) % 360
  if (wrapped < 0) wrapped += 360
  return wrapped - 180
}

function limitKineticVelocity(x, y, maximumSpeed) {
  var velocityX = Number(x)
  var velocityY = Number(y)
  var limit = Number(maximumSpeed)
  if (!isFinite(velocityX) || !isFinite(velocityY) || !isFinite(limit) || limit <= 0)
    return { x: 0, y: 0, speed: 0 }

  var speed = Math.sqrt(velocityX * velocityX + velocityY * velocityY)
  if (!isFinite(speed) || speed <= 0) return { x: 0, y: 0, speed: 0 }
  if (speed <= limit) return { x: velocityX, y: velocityY, speed: speed }

  var ratio = limit / speed
  return { x: velocityX * ratio, y: velocityY * ratio, speed: limit }
}

function kineticLaunchVelocity(x, y, minimumSpeed, maximumSpeed) {
  var limited = limitKineticVelocity(x, y, maximumSpeed)
  var threshold = Math.max(0, Number(minimumSpeed) || 0)
  return {
    x: limited.speed >= threshold ? limited.x : 0,
    y: limited.speed >= threshold ? limited.y : 0,
    active: limited.speed >= threshold
  }
}

function kineticReleaseVelocity(nativeX, nativeY, sampledX, sampledY,
                                sampleAgeMilliseconds, maximumSampleAgeMilliseconds) {
  var nativeVelocityX = Number(nativeX)
  var nativeVelocityY = Number(nativeY)
  var sampledVelocityX = Number(sampledX)
  var sampledVelocityY = Number(sampledY)
  if (!isFinite(nativeVelocityX)) nativeVelocityX = 0
  if (!isFinite(nativeVelocityY)) nativeVelocityY = 0
  if (!isFinite(sampledVelocityX)) sampledVelocityX = 0
  if (!isFinite(sampledVelocityY)) sampledVelocityY = 0

  var nativeSpeed = Math.sqrt(
    nativeVelocityX * nativeVelocityX + nativeVelocityY * nativeVelocityY)
  var sampledSpeed = Math.sqrt(
    sampledVelocityX * sampledVelocityX + sampledVelocityY * sampledVelocityY)
  var sampleAge = Number(sampleAgeMilliseconds)
  var maximumSampleAge = Math.max(0, Number(maximumSampleAgeMilliseconds) || 0)
  var sampleIsFresh = isFinite(sampleAge) && sampleAge >= 0
    && sampleAge <= maximumSampleAge
  var sampleIsAligned = nativeSpeed === 0
    || nativeVelocityX * sampledVelocityX + nativeVelocityY * sampledVelocityY > 0
  if (sampleIsFresh && sampledSpeed > nativeSpeed && sampleIsAligned) {
    return { x: sampledVelocityX, y: sampledVelocityY }
  }
  return { x: nativeVelocityX, y: nativeVelocityY }
}

function advanceKineticRotation(state, elapsedSeconds, options) {
  var current = state || ({})
  var config = options || ({})
  var longitude = Number(current.longitude)
  var latitude = Number(current.latitude)
  var velocityX = Number(current.velocityX)
  var velocityY = Number(current.velocityY)
  var elapsed = Number(elapsedSeconds)
  if (!isFinite(longitude)) longitude = 0
  if (!isFinite(latitude)) latitude = 0
  if (!isFinite(velocityX)) velocityX = 0
  if (!isFinite(velocityY)) velocityY = 0

  var speed = Math.sqrt(velocityX * velocityX + velocityY * velocityY)
  if (!isFinite(speed) || speed <= 0 || !isFinite(elapsed) || elapsed <= 0) {
    return {
      longitude: wrapLongitude(longitude),
      latitude: latitude,
      velocityX: velocityX,
      velocityY: velocityY,
      active: speed > 0
    }
  }

  var deceleration = Number(config.deceleration)
  if (!isFinite(deceleration) || deceleration < 0) deceleration = 0
  var activeTime = deceleration > 0 ? Math.min(elapsed, speed / deceleration) : elapsed
  var nextSpeed = Math.max(0, speed - deceleration * activeTime)
  var distance = (speed + nextSpeed) * activeTime / 2
  var directionX = velocityX / speed
  var directionY = velocityY / speed
  var deltaX = directionX * distance
  var deltaY = directionY * distance

  var scale = Number(config.scale)
  if (!isFinite(scale) || scale <= 0) scale = 1
  var longitudeSensitivity = Number(config.longitudeSensitivity)
  var latitudeSensitivity = Number(config.latitudeSensitivity)
  if (!isFinite(longitudeSensitivity)) longitudeSensitivity = 0
  if (!isFinite(latitudeSensitivity)) latitudeSensitivity = 0
  var minimumLatitude = Number(config.minimumLatitude)
  var maximumLatitude = Number(config.maximumLatitude)
  if (!isFinite(minimumLatitude)) minimumLatitude = -78
  if (!isFinite(maximumLatitude)) maximumLatitude = 78

  var nextLongitude = wrapLongitude(longitude - deltaX * longitudeSensitivity / scale)
  var nextLatitude = clamp(
    latitude + deltaY * latitudeSensitivity / scale,
    minimumLatitude, maximumLatitude)
  var nextVelocityX = directionX * nextSpeed
  var nextVelocityY = directionY * nextSpeed
  if ((nextLatitude >= maximumLatitude && nextVelocityY > 0)
      || (nextLatitude <= minimumLatitude && nextVelocityY < 0))
    nextVelocityY = 0

  var remainingSpeed = Math.sqrt(
    nextVelocityX * nextVelocityX + nextVelocityY * nextVelocityY)
  return {
    longitude: nextLongitude,
    latitude: nextLatitude,
    velocityX: nextVelocityX,
    velocityY: nextVelocityY,
    active: remainingSpeed > 1e-9
  }
}

function project(latitude, longitude, centreLatitude, centreLongitude) {
  var phi = Number(latitude) * radians
  var lambda = wrapLongitude(Number(longitude) - Number(centreLongitude)) * radians
  var phi0 = Number(centreLatitude) * radians
  var cosPhi = Math.cos(phi)
  var sinPhi = Math.sin(phi)
  var cosPhi0 = Math.cos(phi0)
  var sinPhi0 = Math.sin(phi0)

  return {
    x: cosPhi * Math.sin(lambda),
    y: cosPhi0 * sinPhi - sinPhi0 * cosPhi * Math.cos(lambda),
    z: sinPhi0 * sinPhi + cosPhi0 * cosPhi * Math.cos(lambda)
  }
}

function unproject(x, y, centreLatitude, centreLongitude) {
  var rho2 = x * x + y * y
  if (rho2 > 1) return null

  var z = Math.sqrt(Math.max(0, 1 - rho2))
  var phi0 = Number(centreLatitude) * radians
  var cosPhi0 = Math.cos(phi0)
  var sinPhi0 = Math.sin(phi0)
  var latitude = Math.asin(y * cosPhi0 + z * sinPhi0)
  var longitude = Number(centreLongitude) * radians
    + Math.atan2(x, z * cosPhi0 - y * sinPhi0)

  return {
    latitude: latitude * degrees,
    longitude: wrapLongitude(longitude * degrees)
  }
}

function pointInRing(longitude, latitude, ring) {
  var inside = false
  if (!Array.isArray(ring) || ring.length < 3) return false

  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    var xi = Number(ring[i][0])
    var yi = Number(ring[i][1])
    var xj = Number(ring[j][0])
    var yj = Number(ring[j][1])
    var crosses = (yi > latitude) !== (yj > latitude)
      && longitude < (xj - xi) * (latitude - yi) / ((yj - yi) || 1e-12) + xi
    if (crosses) inside = !inside
  }
  return inside
}

function pointInPolygon(longitude, latitude, polygon) {
  if (!Array.isArray(polygon) || polygon.length === 0) return false
  if (!pointInRing(longitude, latitude, polygon[0])) return false

  for (var i = 1; i < polygon.length; i++) {
    if (pointInRing(longitude, latitude, polygon[i])) return false
  }
  return true
}

function countryAt(features, latitude, longitude) {
  var rows = Array.isArray(features) ? features : []
  for (var i = 0; i < rows.length; i++) {
    var feature = rows[i]
    if (!feature || !feature.geometry) continue
    var geometry = feature.geometry
    var polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates
    if (!Array.isArray(polygons)) continue

    for (var p = 0; p < polygons.length; p++) {
      if (pointInPolygon(longitude, latitude, polygons[p])) return feature.properties || null
    }
  }
  return null
}

function countryCentre(features, code) {
  var rows = Array.isArray(features) ? features : []
  var wanted = String(code || "").toUpperCase()

  for (var i = 0; i < rows.length; i++) {
    var feature = rows[i]
    if (!feature || !feature.geometry || !feature.properties) continue
    if (String(feature.properties.code || "").toUpperCase() !== wanted) continue

    var geometry = feature.geometry
    var polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates
    if (!Array.isArray(polygons)) return null

    var best = null
    for (var p = 0; p < polygons.length; p++) {
      var ring = polygons[p] && polygons[p][0]
      if (!Array.isArray(ring) || ring.length < 3) continue

      var points = []
      var previousLongitude = Number(ring[0][0])
      for (var n = 0; n < ring.length; n++) {
        var longitude = Number(ring[n][0])
        var latitude = Number(ring[n][1])
        if (!isFinite(longitude) || !isFinite(latitude)) continue
        if (points.length > 0) {
          while (longitude - previousLongitude > 180) longitude -= 360
          while (longitude - previousLongitude < -180) longitude += 360
        }
        points.push([longitude, latitude])
        previousLongitude = longitude
      }
      if (points.length < 3) continue

      var crossSum = 0
      var longitudeSum = 0
      var latitudeSum = 0
      for (var pointIndex = 0, previous = points.length - 1;
           pointIndex < points.length; previous = pointIndex++) {
        var first = points[previous]
        var second = points[pointIndex]
        var cross = first[0] * second[1] - second[0] * first[1]
        crossSum += cross
        longitudeSum += (first[0] + second[0]) * cross
        latitudeSum += (first[1] + second[1]) * cross
      }

      var area = Math.abs(crossSum)
      if (area < 1e-9 || (best && area <= best.area)) continue
      best = {
        area: area,
        latitude: latitudeSum / (3 * crossSum),
        longitude: wrapLongitude(longitudeSum / (3 * crossSum))
      }
    }

    return best ? { latitude: best.latitude, longitude: best.longitude } : null
  }

  return null
}

function estimatedCountryLocation(features, code, key) {
  var rows = Array.isArray(features) ? features : []
  var wanted = String(code || "").toUpperCase()
  var cacheKey = "$" + wanted + ":" + String(key || wanted)
  if (estimatedLocationCache[cacheKey] !== undefined)
    return estimatedLocationCache[cacheKey]
  var bestRing = null
  var bestArea = 0

  for (var i = 0; i < rows.length; i++) {
    var feature = rows[i]
    if (!feature || !feature.geometry || !feature.properties) continue
    if (String(feature.properties.code || "").toUpperCase() !== wanted) continue

    var geometry = feature.geometry
    var polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates
    if (!Array.isArray(polygons)) break
    for (var p = 0; p < polygons.length; p++) {
      var ring = polygons[p] && polygons[p][0]
      if (!Array.isArray(ring) || ring.length < 3) continue
      var points = []
      var previousLongitude = Number(ring[0][0])
      for (var pointIndex = 0; pointIndex < ring.length; pointIndex++) {
        var longitude = Number(ring[pointIndex][0])
        var latitude = Number(ring[pointIndex][1])
        if (!isFinite(longitude) || !isFinite(latitude)) continue
        if (points.length > 0) {
          while (longitude - previousLongitude > 180) longitude -= 360
          while (longitude - previousLongitude < -180) longitude += 360
        }
        points.push([longitude, latitude])
        previousLongitude = longitude
      }
      if (points.length < 3) continue

      var area = 0
      for (var n = 0, previous = points.length - 1; n < points.length; previous = n++)
        area += points[previous][0] * points[n][1] - points[n][0] * points[previous][1]
      area = Math.abs(area)
      if (area > bestArea) {
        bestArea = area
        bestRing = points
      }
    }
    break
  }

  if (!bestRing) return null
  var minimumLongitude = Infinity
  var maximumLongitude = -Infinity
  var minimumLatitude = Infinity
  var maximumLatitude = -Infinity
  for (var boundIndex = 0; boundIndex < bestRing.length; boundIndex++) {
    minimumLongitude = Math.min(minimumLongitude, bestRing[boundIndex][0])
    maximumLongitude = Math.max(maximumLongitude, bestRing[boundIndex][0])
    minimumLatitude = Math.min(minimumLatitude, bestRing[boundIndex][1])
    maximumLatitude = Math.max(maximumLatitude, bestRing[boundIndex][1])
  }

  var seed = 2166136261
  var source = String(key || wanted)
  for (var character = 0; character < source.length; character++) {
    seed ^= source.charCodeAt(character)
    seed = Math.imul(seed, 16777619)
  }
  seed >>>= 0

  function random() {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
    return seed / 4294967296
  }

  for (var attempt = 0; attempt < 96; attempt++) {
    var candidateLongitude = minimumLongitude
      + random() * (maximumLongitude - minimumLongitude)
    var candidateLatitude = minimumLatitude
      + random() * (maximumLatitude - minimumLatitude)
    if (pointInRing(candidateLongitude, candidateLatitude, bestRing)) {
      var location = {
        latitude: candidateLatitude,
        longitude: wrapLongitude(candidateLongitude)
      }
      estimatedLocationCache[cacheKey] = location
      return location
    }
  }
  var centre = countryCentre(features, wanted)
  if (centre) estimatedLocationCache[cacheKey] = centre
  return centre
}

function stationPosition(station, width, height, scale, centreLatitude, centreLongitude) {
  if (!station || station.latitude === null || station.longitude === null) return null
  var point = project(station.latitude, station.longitude, centreLatitude, centreLongitude)
  if (point.z < 0) return null
  var radius = Math.min(width, height) * 0.44 * scale
  return {
    x: width / 2 + point.x * radius,
    y: height / 2 - point.y * radius,
    z: point.z
  }
}

// Centre that keeps the geographic point under the cursor in place across a
// zoom from oldScale to newScale. The centre is refined by successive
// corrections (the offset between the wanted point and the one the cursor
// lands on); three passes are enough at any zoom. Off the sphere, the
// centre stays and the zoom is plain.
function zoomAnchoredCentre(cursorX, cursorY, width, height, oldScale, newScale, centreLatitude, centreLongitude) {
  var current = { latitude: Number(centreLatitude), longitude: Number(centreLongitude) }
  var oldRadius = Math.min(width, height) * 0.44 * oldScale
  var newRadius = Math.min(width, height) * 0.44 * newScale
  if (!(oldRadius > 0) || !(newRadius > 0)) return current
  var anchor = unproject((cursorX - width / 2) / oldRadius, -(cursorY - height / 2) / oldRadius,
    current.latitude, current.longitude)
  if (!anchor) return current
  var targetX = (cursorX - width / 2) / newRadius
  var targetY = -(cursorY - height / 2) / newRadius
  for (var pass = 0; pass < 3; pass++) {
    var under = unproject(targetX, targetY, current.latitude, current.longitude)
    if (!under) break
    current = {
      latitude: clamp(current.latitude + anchor.latitude - under.latitude, -78, 78),
      longitude: wrapLongitude(current.longitude + anchor.longitude - under.longitude)
    }
  }
  return current
}

function nearestVisibleStation(stations, centreLatitude, centreLongitude, excludedUuid,
                               width, height, scale) {
  var rows = Array.isArray(stations) ? stations : []
  var excluded = String(excludedUuid || "")
  var viewportWidth = Number(width)
  var viewportHeight = Number(height)
  var viewportScale = Number(scale)
  var constrainToViewport = isFinite(viewportWidth) && viewportWidth > 0
    && isFinite(viewportHeight) && viewportHeight > 0
    && isFinite(viewportScale) && viewportScale > 0
  var viewportRadius = constrainToViewport
    ? Math.min(viewportWidth, viewportHeight) * 0.44 * viewportScale : 0
  var nearest = null
  var nearestDepth = -Infinity
  var preferred = null
  var preferredDepth = -Infinity

  for (var i = 0; i < rows.length; i++) {
    var station = rows[i]
    if (!station || station.latitude === null || station.longitude === null) continue
    var latitude = Number(station.latitude)
    var longitude = Number(station.longitude)
    if (!isFinite(latitude) || !isFinite(longitude)) continue
    var point = project(latitude, longitude, centreLatitude, centreLongitude)
    if (!isFinite(point.z) || point.z < 0) continue
    if (constrainToViewport) {
      var screenX = viewportWidth / 2 + point.x * viewportRadius
      var screenY = viewportHeight / 2 - point.y * viewportRadius
      if (screenX < 0 || screenX > viewportWidth
          || screenY < 0 || screenY > viewportHeight)
        continue
    }
    if (point.z > nearestDepth) {
      nearest = station
      nearestDepth = point.z
    }
    if (String(station.uuid || "") !== excluded && point.z > preferredDepth) {
      preferred = station
      preferredDepth = point.z
    }
  }

  return preferred || nearest
}

function stationAt(stations, x, y, width, height, scale, centreLatitude, centreLongitude, hitRadius) {
  var rows = Array.isArray(stations) ? stations : []
  var nearest = null
  var nearestDistance = Number(hitRadius || 12)

  for (var i = 0; i < rows.length; i++) {
    var position = stationPosition(rows[i], width, height, scale, centreLatitude, centreLongitude)
    if (!position) continue
    var dx = position.x - x
    var dy = position.y - y
    var distance = Math.sqrt(dx * dx + dy * dy)
    if (distance > nearestDistance) continue
    nearest = rows[i]
    nearestDistance = distance
  }
  return nearest
}

function mergeGeoStations(primary, secondary, countries) {
  var rows = mergeStations(primary, secondary, 5500)
  var output = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (row.latitude === null || row.longitude === null) {
      var estimate = estimatedCountryLocation(countries, row.countryCode, row.uuid)
      if (!estimate) continue
      var estimated = ({})
      for (var key in row) estimated[key] = row[key]
      estimated.latitude = estimate.latitude
      estimated.longitude = estimate.longitude
      estimated.estimatedLocation = true
      output.push(estimated)
    } else {
      output.push(row)
    }
    if (output.length >= 5500) break
  }
  return output
}

function combineStations(groups, maximum, replaceDuplicates) {
  var output = []
  var seen = ({})
  var limit = Math.max(1, Number(maximum || 500))

  for (var g = 0; g < groups.length; g++) {
    var rows = Array.isArray(groups[g]) ? groups[g] : []
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      if (!row || !row.uuid) continue
      var key = "$" + row.uuid
      if (seen[key] !== undefined) {
        if (replaceDuplicates && g > 0) output[seen[key]] = row
        continue
      }
      if (output.length >= limit) continue
      seen[key] = output.length
      output.push(row)
    }
  }
  return output
}

function mergeStations(primary, secondary, maximum) {
  return combineStations([primary, secondary], maximum, true)
}

function prioritizeStations(priority, fallback, maximum) {
  return combineStations([priority, fallback], maximum, false)
}

function searchStations(stations, query, maximum) {
  var rows = Array.isArray(stations) ? stations : []
  var wanted = String(query || "").trim().toLowerCase()
  if (!wanted) return []

  var output = []
  var limit = Math.max(1, Number(maximum || 150))
  for (var i = 0; i < rows.length && output.length < limit; i++) {
    var station = rows[i]
    if (!station) continue
    var fields = [
      station.name,
      station.country,
      station.countryCode,
      station.state,
      station.language,
      station.tags,
      station.codec
    ]
    for (var fieldIndex = 0; fieldIndex < fields.length; fieldIndex++) {
      if (String(fields[fieldIndex] || "").toLowerCase().indexOf(wanted) < 0) continue
      output.push(station)
      break
    }
  }
  return output
}

function stationsForCountry(stations, code, maximum) {
  var rows = Array.isArray(stations) ? stations : []
  var wanted = String(code || "").toUpperCase()
  if (!wanted) return []

  var output = []
  var limit = Math.max(1, Number(maximum || 150))
  for (var i = 0; i < rows.length && output.length < limit; i++) {
    if (String(rows[i] && rows[i].countryCode || "").toUpperCase() === wanted)
      output.push(rows[i])
  }
  return output
}

function stationWindow(stations, uuid, maximum) {
  var rows = Array.isArray(stations) ? stations : []
  var index = indexByUuid(rows, uuid)
  if (index < 0) return []

  var limit = Math.min(rows.length, Math.max(1, Number(maximum || 500)))
  var before = Math.floor((limit - 1) / 2)
  var start = (index - before + rows.length) % rows.length
  var output = []
  for (var i = 0; i < limit; i++) output.push(rows[(start + i) % rows.length])
  return output
}

function compactTags(tags, maximum) {
  var raw = String(tags || "")
  var parts = raw.split(",")
  var output = []
  var limit = Math.max(1, Number(maximum || 2))
  for (var i = 0; i < parts.length && output.length < limit; i++) {
    var part = parts[i].trim()
    if (part && output.indexOf(part) === -1) output.push(part)
  }
  return output.join(" · ")
}

function stationMeta(station) {
  if (!station) return ""
  var parts = []
  if (station.countryCode) parts.push(station.countryCode)
  if (station.codec) parts.push(station.codec)
  if (Number(station.bitrate) > 0) parts.push(Number(station.bitrate) + " kbps")
  return parts.join(" · ")
}

function indexByUuid(stations, uuid) {
  var rows = Array.isArray(stations) ? stations : []
  for (var i = 0; i < rows.length; i++) if (rows[i].uuid === uuid) return i
  return -1
}

function cleanText(value, limit) {
    var text = String(value === null || value === undefined ? "" : value)
        .replace(/[\r\n\t]/g, " ")
        .replace(/ {2,}/g, " ")
        .trim();
    return text.slice(0, limit);
}

function webUrlOrEmpty(value, limit) {
    var url = cleanText(value, limit || 2048);
    return /^https?:\/\//i.test(url) ? url : "";
}

function finiteInRange(value, minimum, maximum) {
    var number = Number(value);
    if (value === null || value === undefined || value === "" || !isFinite(number)) return null;
    if (number < minimum || number > maximum) return null;
    return number;
}

function normalizeStation(raw) {
    if (!raw || typeof raw !== "object") return null;
    var uuid = cleanText(raw.stationuuid, 64);
    if (!uuid) return null;
    var url = webUrlOrEmpty(raw.url_resolved) || webUrlOrEmpty(raw.url);
    if (!url) return null;
    var name = cleanText(raw.name, 160) || "Unknown station";
    var bitrate = Number(raw.bitrate) || 0;
    if (bitrate >= 8000) bitrate = Math.round(bitrate / 1000);
    var latitude = finiteInRange(raw.geo_lat, -90, 90);
    var longitude = finiteInRange(raw.geo_long, -180, 180);
    if (latitude === null || longitude === null) {
        latitude = null;
        longitude = null;
    }
    var station = {
        uuid: uuid,
        name: name,
        url: url,
        homepage: webUrlOrEmpty(raw.homepage),
        favicon: webUrlOrEmpty(raw.favicon),
        country: cleanText(raw.country, 100),
        countryCode: cleanText(raw.countrycode, 2).toUpperCase(),
        state: cleanText(raw.state, 100),
        language: cleanText(raw.language, 120),
        tags: cleanText(raw.tags, 500),
        codec: cleanText(raw.codec, 32),
        bitrate: bitrate,
        latitude: latitude,
        longitude: longitude,
        clicks: Number(raw.clickcount) || 0,
        hls: Number(raw.hls) === 1
    };
    // The list delegate would otherwise call stationMeta() on every row of
    // every refresh. Rows that come from an older cache have no meta field,
    // so the delegate keeps a fallback.
    station.meta = stationMeta(station);
    return station;
}

function normalizeStations(rows, maximum) {
    var output = [];
    var seen = ({});
    var limit = Math.max(1, Number(maximum || 500));
    var list = Array.isArray(rows) ? rows : [];
    for (var i = 0; i < list.length && output.length < limit; i++) {
        var station = normalizeStation(list[i]);
        if (!station || seen["$" + station.uuid] !== undefined) continue;
        seen["$" + station.uuid] = true;
        output.push(station);
    }
    return output;
}

function cleanTags(value) {
    return cleanText(value, 500).split(",").map(function (tag) {
        return tag.trim();
    }).filter(function (tag) {
        return tag !== "";
    }).join(",");
}

// Coordinates typed in the add form: both, or neither. `valid` is false when
// only one is given or one is not a number in range.
function formCoordinates(fields) {
    var latText = cleanText(fields.latitude, 32);
    var longText = cleanText(fields.longitude, 32);
    if (latText === "" && longText === "") return { latitude: null, longitude: null, valid: true };
    var latitude = finiteInRange(latText, -90, 90);
    var longitude = finiteInRange(longText, -180, 180);
    if (latitude === null || longitude === null) return { latitude: null, longitude: null, valid: false };
    return { latitude: latitude, longitude: longitude, valid: true };
}

// Builds a station from the "Add a station" form with the same cleaning as
// normalizeStation. Returns null when a mandatory field is missing or bad.
function stationFromForm(fields, uuid) {
    var source = fields && typeof fields === "object" ? fields : {};
    var id = cleanText(uuid, 64);
    var name = cleanText(source.name, 160);
    var url = webUrlOrEmpty(source.url);
    var coordinates = formCoordinates(source);
    if (!id || !name || !url || !coordinates.valid) return null;
    var station = {
        uuid: id,
        name: name,
        url: url,
        homepage: webUrlOrEmpty(source.homepage),
        favicon: "",
        country: "",
        countryCode: cleanText(source.countryCode, 2).toUpperCase(),
        state: "",
        language: "",
        tags: cleanTags(source.tags),
        codec: "",
        bitrate: 0,
        latitude: coordinates.latitude,
        longitude: coordinates.longitude,
        clicks: 0,
        hls: false
    };
    station.meta = stationMeta(station);
    return station;
}

// Radio Browser /json/add parameters for the same form. Empty values are
// left out so the server applies its own defaults.
function submitParams(fields) {
    var station = stationFromForm(fields, "pending");
    if (!station) return null;
    var params = { name: station.name, url: station.url };
    if (station.homepage) params.homepage = station.homepage;
    if (station.countryCode) params.countrycode = station.countryCode;
    if (station.tags) params.tags = station.tags;
    if (station.latitude !== null) {
        params.geo_lat = station.latitude;
        params.geo_long = station.longitude;
    }
    return params;
}

// Nominatim is OpenStreetMap's geocoder. Its usage policy asks for an
// identifiable User-Agent (Http sets it), no autocomplete and at most one
// request per second: the page only calls it on Enter.
function nominatimUrl(query) {
    var text = cleanText(query, 200);
    if (!text) return "";
    return "https://nominatim.openstreetmap.org/search?q=" + encodeURIComponent(text) + "&format=jsonv2&limit=5";
}

// Parses a Nominatim JSON answer into [{name, latitude, longitude, zoom}].
// The zoom comes from the bounding box: a country fits in 4-5, a street sits
// around 16. Rows without usable coordinates are dropped.
function parseNominatim(text) {
    var rows = null;
    try {
        rows = JSON.parse(String(text || ""));
    } catch (error) {
        return [];
    }
    if (!Array.isArray(rows)) return [];
    var output = [];
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (!row || typeof row !== "object") continue;
        var latitude = finiteInRange(row.lat, -90, 90);
        var longitude = finiteInRange(row.lon, -180, 180);
        if (latitude === null || longitude === null) continue;
        var zoom = 14;
        var box = Array.isArray(row.boundingbox) ? row.boundingbox.map(Number) : [];
        if (box.length === 4 && box.every(isFinite)) {
            var span = Math.max(Math.abs(box[1] - box[0]), Math.abs(box[3] - box[2]), 0.0005);
            // 360 degrees fit at zoom 0; each level halves the span.
            zoom = clamp(Math.floor(Math.log(360 / span) / Math.LN2) - 1, 2, 18);
        }
        output.push({
            name: cleanText(row.display_name, 300) || (latitude + ", " + longitude),
            latitude: latitude,
            longitude: longitude,
            zoom: zoom
        });
    }
    return output;
}

function dedupeByUrl(stations) {
    var rows = Array.isArray(stations) ? stations : [];
    var byUrl = ({});
    var order = [];
    for (var i = 0; i < rows.length; i++) {
        var station = rows[i];
        if (!station || !station.url) continue;
        var key = "$" + station.url;
        var existing = byUrl[key];
        if (existing === undefined) {
            byUrl[key] = station;
            order.push(key);
        } else if ((Number(station.clicks) || 0) > (Number(existing.clicks) || 0)) {
            byUrl[key] = station;
        }
    }
    var output = [];
    for (var n = 0; n < order.length; n++) output.push(byUrl[order[n]]);
    return output;
}

function pickRandomStation(stations, recentUuids, random) {
    var rows = Array.isArray(stations) ? stations : [];
    if (rows.length === 0) return null;
    var recent = ({});
    var list = Array.isArray(recentUuids) ? recentUuids : [];
    for (var i = 0; i < list.length; i++) recent["$" + list[i]] = true;
    var candidates = [];
    for (var n = 0; n < rows.length; n++) {
        if (rows[n] && recent["$" + rows[n].uuid] === undefined) candidates.push(rows[n]);
    }
    if (candidates.length === 0) candidates = rows;
    var pick = typeof random === "function" ? random() : Math.random();
    var index = Math.min(candidates.length - 1, Math.max(0, Math.floor(pick * candidates.length)));
    return candidates[index];
}

function neighbourStation(stations, uuid, delta) {
    var rows = Array.isArray(stations) ? stations : [];
    if (rows.length === 0) return null;
    var index = indexByUuid(rows, uuid);
    if (index < 0) return null;
    var step = Number(delta) || 0;
    return rows[((index + step) % rows.length + rows.length) % rows.length];
}

function toggleFavorite(favorites, station) {
    var rows = Array.isArray(favorites) ? favorites : [];
    if (!station || !station.uuid) return rows.slice();
    var output = [];
    var removed = false;
    for (var i = 0; i < rows.length; i++) {
        if (rows[i] && rows[i].uuid === station.uuid) {
            removed = true;
            continue;
        }
        output.push(rows[i]);
    }
    if (!removed) output.push(station);
    return output;
}

function pushHistory(history, station, nowMs, maximum) {
    var rows = Array.isArray(history) ? history : [];
    if (!station || !station.uuid) return rows.slice();
    var limit = Math.max(1, Number(maximum || 20));
    var entry = ({});
    for (var key in station) entry[key] = station[key];
    entry.playedAt = Number(nowMs) || 0;
    var output = [entry];
    for (var i = 0; i < rows.length && output.length < limit; i++) {
        if (rows[i] && rows[i].uuid !== station.uuid) output.push(rows[i]);
    }
    return output;
}

function isRawTitle(track, url) {
    var title = String(track || "").trim();
    if (!title) return true;
    var stream = String(url || "");
    if (title === stream) return true;
    var path = stream.split("?")[0];
    var segment = path.slice(path.lastIndexOf("/") + 1);
    return segment !== "" && title === segment;
}

// Single-quotes a value for /bin/sh: nothing inside can be expanded, and an
// embedded quote is closed, escaped and reopened.
function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function validMirrorName(name) {
    return /^[a-z0-9-]+\.api\.radio-browser\.info$/.test(String(name || ""));
}

function buildQuery(params) {
    var parts = [];
    for (var key in params) {
        var value = params[key];
        if (value === undefined || value === null) continue;
        if (typeof value === "boolean") value = value ? "true" : "false";
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
    }
    return parts.join("&");
}

// Several stations of one broadcaster often share one exact point; place the
// duplicates on a small ring (about 0.08 degrees) so each stays clickable.
function spreadOverlapping(stations) {
    var rows = Array.isArray(stations) ? stations : [];
    var seen = ({});
    var output = [];
    for (var i = 0; i < rows.length; i++) {
        var station = rows[i];
        if (!station || station.latitude === null || station.longitude === null
            || station.latitude === undefined || station.longitude === undefined) {
            output.push(station);
            continue;
        }
        var key = "$" + Number(station.latitude).toFixed(4) + "," + Number(station.longitude).toFixed(4);
        var count = seen[key] || 0;
        seen[key] = count + 1;
        if (count === 0) {
            output.push(station);
            continue;
        }
        var copy = ({});
        for (var field in station) copy[field] = station[field];
        var angle = count * 2.399963;
        var ring = 0.08 * (1 + Math.floor((count - 1) / 8));
        copy.latitude = clamp(Number(station.latitude) + Math.sin(angle) * ring, -89.9, 89.9);
        copy.longitude = wrapLongitude(Number(station.longitude) + Math.cos(angle) * ring);
        output.push(copy);
    }
    return output;
}

// Ranks the world list before it is cut down to the configured cap: the
// stations of the user's home country come first, whatever their popularity,
// then everything else by click count. Ties keep their input order (the sort
// runs on decorated indices, so it does not rely on the engine being stable)
// and the input array is left untouched.
function sortWorld(stations, homeCountry) {
    var rows = Array.isArray(stations) ? stations : [];
    var home = String(homeCountry || "").toUpperCase();
    var decorated = [];
    for (var i = 0; i < rows.length; i++) {
        decorated.push({
            station: rows[i],
            index: i,
            home: home !== "" && rows[i] && String(rows[i].countryCode || "").toUpperCase() === home,
            clicks: Number(rows[i] && rows[i].clicks) || 0
        });
    }
    decorated.sort(function (a, b) {
        if (a.home !== b.home) return a.home ? -1 : 1;
        if (a.clicks !== b.clicks) return b.clicks - a.clicks;
        return a.index - b.index;
    });
    var output = [];
    for (var n = 0; n < decorated.length; n++) output.push(decorated[n].station);
    return output;
}
