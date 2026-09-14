import QtQuick
import QtLocation
import QtPositioning
import org.kde.kirigami as Kirigami

// OpenStreetMap view where a click drops the station marker. Loaded through a
// Loader by configAddStation.qml, so a machine without the QtLocation QML
// module only loses the map, never the page.
Item {
    id: picker

    property real latitude: 0
    property real longitude: 0
    property bool hasMarker: false
    property string userAgent: "RadioGlobe"

    signal picked(real latitude, real longitude)

    function centreOn(latitude, longitude, zoom) {
        map.center = QtPositioning.coordinate(latitude, longitude);
        map.zoomLevel = zoom;
    }

    Plugin {
        id: osmPlugin
        name: "osm"
        PluginParameter {
            name: "osm.mapping.providersrepository.disabled"
            value: "true"
        }
        PluginParameter {
            name: "osm.mapping.custom.host"
            value: "https://tile.openstreetmap.org/"
        }
        PluginParameter {
            name: "osm.mapping.custom.mapcopyright"
            value: "© OpenStreetMap contributors"
        }
        PluginParameter {
            name: "osm.useragent"
            value: picker.userAgent
        }
    }

    Map {
        id: map
        anchors.fill: parent
        plugin: osmPlugin
        zoomLevel: 1
        minimumZoomLevel: 1
        // The OSM raster set stops at 19; 18 already shows single streets.
        maximumZoomLevel: 18
        copyrightsVisible: false
        // With the providers repository disabled only the custom host works;
        // the plugin lists it after its built-in (now dead) types.
        activeMapType: {
            for (let i = 0; i < supportedMapTypes.length; i++) {
                if (supportedMapTypes[i].name.indexOf("Custom") !== -1)
                    return supportedMapTypes[i];
            }
            return supportedMapTypes.length > 0 ? supportedMapTypes[supportedMapTypes.length - 1] : null;
        }

        MapQuickItem {
            visible: picker.hasMarker
            coordinate: QtPositioning.coordinate(picker.latitude, picker.longitude)
            anchorPoint.x: marker.width / 2
            anchorPoint.y: marker.height / 2
            sourceItem: Rectangle {
                id: marker
                width: Kirigami.Units.iconSizes.small
                height: width
                radius: width / 2
                color: Kirigami.Theme.negativeTextColor
                border.color: "white"
                border.width: 2
            }
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const anchor = map.toCoordinate(point.position, false);
                map.zoomLevel = Math.max(map.minimumZoomLevel, Math.min(map.maximumZoomLevel, map.zoomLevel + event.angleDelta.y / 120));
                map.alignCoordinateToPoint(anchor, point.position);
                event.accepted = true;
            }
        }

        DragHandler {
            target: null
            onTranslationChanged: delta => map.pan(-delta.x, -delta.y)
        }

        TapHandler {
            onTapped: eventPoint => {
                const coordinate = map.toCoordinate(eventPoint.position, false);
                picker.picked(coordinate.latitude, coordinate.longitude);
            }
        }
    }
}
