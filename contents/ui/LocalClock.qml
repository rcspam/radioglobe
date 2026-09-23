import QtQuick
import "RadioModel.js" as RadioModel
import "TimeZones.js" as TimeZones

// The local time where the current station broadcasts. The zone comes from
// zone1970.tab (TimeZones.zoneFor); its UTC offset from one `date +%z` per
// zone change, read again every half hour so daylight-saving switches show
// up. In between, a timer ticks the display once a minute with no process.
Item {
    id: root

    visible: false

    property var station: null
    // Parsed zone1970.tab, see TimeZones.parseZoneTable.
    property var zones: []
    // function (command, callback(exitCode, stdout)), see Exec.qml.
    property var exec: null
    property int offsetRefreshMs: 30 * 60 * 1000
    // Tests pin the clock; negative means Date.now().
    property real fixedNowMs: -1
    // Qt time format (main.qml's clockFormat), see TimeZones.formatClock.
    property string format: "HH:mm"
    property string amText: Qt.locale().amText
    property string pmText: Qt.locale().pmText

    readonly property string zone: root._zone
    // Minutes east of UTC, or null while unknown.
    readonly property var offsetMinutes: root._offset
    readonly property string text: root._text
    // "Europe/Paris, UTC+2", for a tooltip; "" while unknown.
    readonly property string description: root._zone !== "" && root._offset !== null ? root._zone + ", " + TimeZones.formatOffset(root._offset) : ""

    property string _zone: ""
    property var _offset: null
    property string _text: ""
    // Replies to a `date` run for a previous zone are dropped.
    property int _epoch: 0

    onStationChanged: root._pickZone()
    onZonesChanged: root._pickZone()
    onFormatChanged: root._tick()
    onAmTextChanged: root._tick()
    onPmTextChanged: root._tick()

    function _pickZone() {
        const next = TimeZones.zoneFor(root.zones, root.station);
        if (next === root._zone)
            return;
        root._zone = next;
        root._offset = null;
        root._text = "";
        root._epoch += 1;
        root.refreshOffset();
    }

    function refreshOffset() {
        if (root._zone === "" || !root.exec)
            return;
        const epoch = root._epoch;
        root.exec("TZ=" + RadioModel.shellQuote(root._zone) + " date +%z", (exitCode, stdout) => {
            if (epoch !== root._epoch)
                return;
            const offset = exitCode === 0 ? TimeZones.parseUtcOffset(stdout) : null;
            root._offset = offset;
            root._tick();
        });
    }

    function _now() {
        return root.fixedNowMs >= 0 ? root.fixedNowMs : Date.now();
    }

    function _tick() {
        root._text = TimeZones.formatLocalTime(root._now(), root._offset, root.format, root.amText, root.pmText);
    }

    // Fires just after each minute boundary.
    Timer {
        id: minuteTimer
        running: root._offset !== null && root.fixedNowMs < 0
        repeat: true
        interval: 60000 - (Date.now() % 60000) + 50
        // Restarted for a new zone, it would keep the phase of an old minute.
        onRunningChanged: if (running)
            interval = 60000 - (Date.now() % 60000) + 50
        onTriggered: {
            root._tick();
            interval = 60000 - (Date.now() % 60000) + 50;
        }
    }

    Timer {
        running: root._zone !== "" && root.fixedNowMs < 0
        repeat: true
        interval: root.offsetRefreshMs
        onTriggered: root.refreshOffset()
    }
}
