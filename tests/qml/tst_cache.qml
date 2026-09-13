import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Cache"

    Ui.Cache {
        id: cache
        databaseName: "radioglobe-test"
    }

    function init() {
        cache.clear();
    }

    function test_roundtrip() {
        cache.set("world", {
            stations: [
                {
                    uuid: "a"
                }
            ]
        }, 1234);
        const entry = cache.get("world");
        compare(entry.savedAt, 1234);
        compare(entry.value.stations[0].uuid, "a");
    }

    function test_missing_key_is_null() {
        compare(cache.get("nope"), null);
    }

    function test_remove_and_overwrite() {
        cache.set("k", 1, 1);
        cache.set("k", 2, 2);
        compare(cache.get("k").value, 2);
        cache.remove("k");
        compare(cache.get("k"), null);
    }

    function test_corrupt_row_is_dropped() {
        cache.debugWriteRaw("bad", "{not json", 5);
        compare(cache.get("bad"), null);
    }
}
