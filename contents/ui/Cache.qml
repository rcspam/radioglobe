import QtQuick
import QtQuick.LocalStorage

// Small key/value cache on top of QtQuick.LocalStorage (SQLite). The database
// lives in plasmashell's offline storage path and is shared by every plasmoid
// of the process, hence the specific database name.
QtObject {
    id: root

    property string databaseName: "radioglobe"
    property var _db: null

    function _open() {
        if (root._db)
            return root._db;
        root._db = LocalStorage.openDatabaseSync(root.databaseName, "1.0", "RadioGlobe cache", 20 * 1024 * 1024);
        root._db.transaction(tx => {
            tx.executeSql("CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, value TEXT NOT NULL, savedAt INTEGER NOT NULL)");
        });
        return root._db;
    }

    function get(key) {
        let result = null;
        try {
            _open().readTransaction(tx => {
                const rows = tx.executeSql("SELECT value, savedAt FROM cache WHERE key = ?", [key]).rows;
                if (rows.length === 0)
                    return;
                result = {
                    value: JSON.parse(rows.item(0).value),
                    savedAt: Number(rows.item(0).savedAt)
                };
            });
        } catch (error) {
            console.warn("[RadioGlobe] cache read failed for", key, error);
            remove(key);
            return null;
        }
        return result;
    }

    function set(key, value, nowMs) {
        debugWriteRaw(key, JSON.stringify(value), Number(nowMs) || 0);
    }

    // Raw write primitive, exposed so tests can inject a corrupt row; not
    // meant to be called by anything other than set().
    function debugWriteRaw(key, text, savedAt) {
        try {
            _open().transaction(tx => {
                tx.executeSql("INSERT OR REPLACE INTO cache(key, value, savedAt) VALUES(?, ?, ?)", [key, text, savedAt]);
            });
        } catch (error) {
            console.warn("[RadioGlobe] cache write failed for", key, error);
        }
    }

    function remove(key) {
        try {
            _open().transaction(tx => {
                tx.executeSql("DELETE FROM cache WHERE key = ?", [key]);
            });
        } catch (error) {
            console.warn("[RadioGlobe] cache delete failed", error);
        }
    }

    function clear() {
        try {
            _open().transaction(tx => {
                tx.executeSql("DELETE FROM cache");
            });
        } catch (error) {
            console.warn("[RadioGlobe] cache clear failed, dropping table", error);
            root._db = null;
        }
    }
}
