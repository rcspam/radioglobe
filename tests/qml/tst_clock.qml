import QtQuick
import QtTest
import "../../contents/ui" as Ui
import "../../contents/ui/TimeZones.js" as TimeZones

TestCase {
    name: "LocalClock"

    property var execLog: []
    property var execReplies: []

    // Commands are logged; each one is answered with the next queued reply,
    // or "+0200" when the queue is empty.
    function fakeExec(cmd, callback) {
        execLog.push(cmd);
        const reply = execReplies.length ? execReplies.shift() : {
            code: 0,
            out: "+0200\n"
        };
        callback(reply.code, reply.out);
    }

    readonly property var table: TimeZones.parseZoneTable("FR,MC\t+4852+00220\tEurope/Paris\n" + "US\t+404251-0740023\tAmerica/New_York\tEastern\n" + "US\t+340308-1181434\tAmerica/Los_Angeles\tPacific\n")

    readonly property var fip: ({
            uuid: "fip",
            name: "FIP",
            url: "https://s/fip.mp3",
            countryCode: "FR",
            latitude: 48.85,
            longitude: 2.35
        })
    readonly property var kcrw: ({
            uuid: "kcrw",
            name: "KCRW",
            url: "https://s/kcrw.mp3",
            countryCode: "US",
            latitude: 34.02,
            longitude: -118.49
        })

    // 12:00 UTC on 18 September 2026.
    readonly property real noonUtc: Date.UTC(2026, 8, 18, 12, 0, 0)

    Ui.LocalClock {
        id: clock
        exec: fakeExec
        zones: table
        fixedNowMs: noonUtc
    }

    function init() {
        execLog = [];
        execReplies = [];
        clock.station = null;
    }

    function test_idle_shows_nothing() {
        compare(clock.zone, "");
        compare(clock.text, "");
        compare(clock.description, "");
        compare(execLog.length, 0);
    }

    function test_station_asks_date_for_its_zone_and_shows_the_time() {
        clock.station = fip;
        compare(clock.zone, "Europe/Paris");
        compare(execLog.length, 1);
        compare(execLog[0], "TZ='Europe/Paris' date +%z");
        compare(clock.offsetMinutes, 120);
        compare(clock.text, "14:00");
        compare(clock.description, "Europe/Paris, UTC+2");
    }

    function test_changing_zone_asks_again_and_same_zone_does_not() {
        clock.station = fip;
        execReplies = [
            {
                "code": 0,
                "out": "-0700\n"
            }
        ];
        clock.station = kcrw;
        compare(clock.zone, "America/Los_Angeles");
        compare(execLog.length, 2);
        compare(execLog[1], "TZ='America/Los_Angeles' date +%z");
        compare(clock.text, "05:00");
        compare(clock.description, "America/Los_Angeles, UTC-7");
        // Another station in the same zone: no new process.
        clock.station = ({
                uuid: "kcsn",
                name: "KCSN",
                url: "https://s/kcsn.mp3",
                countryCode: "US",
                latitude: 34.24,
                longitude: -118.53
            });
        compare(execLog.length, 2);
        compare(clock.text, "05:00");
    }

    function test_failed_date_shows_nothing() {
        execReplies = [
            {
                "code": 127,
                "out": ""
            }
        ];
        clock.station = fip;
        compare(clock.zone, "Europe/Paris");
        compare(clock.text, "");
        compare(clock.description, "");
    }

    function test_station_without_zone_shows_nothing() {
        clock.station = ({
                uuid: "x",
                name: "X",
                url: "https://s/x.mp3"
            });
        compare(clock.zone, "");
        compare(clock.text, "");
        compare(execLog.length, 0);
    }

    function test_clearing_the_station_clears_the_time() {
        clock.station = fip;
        compare(clock.text, "14:00");
        clock.station = null;
        compare(clock.zone, "");
        compare(clock.text, "");
    }

    function test_zones_arriving_after_the_station() {
        clock.zones = [];
        clock.station = fip;
        compare(clock.zone, "");
        clock.zones = table;
        compare(clock.zone, "Europe/Paris");
        compare(clock.text, "14:00");
    }

    function test_refresh_reads_the_offset_again() {
        clock.station = fip;
        compare(execLog.length, 1);
        execReplies = [
            {
                "code": 0,
                "out": "+0100\n"
            }
        ];
        clock.refreshOffset();
        compare(execLog.length, 2);
        compare(clock.text, "13:00");
    }
}
