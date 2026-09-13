import QtQuick
import org.kde.plasma.plasma5support as P5Support

// Runs shell commands through the plasma5support "executable" engine and
// delivers exit code and stdout to a callback. The only place RadioGlobe
// executes anything: mpv detection, launch and kill, plus reading the bundled
// GeoJSON, which XMLHttpRequest refuses to open from a local file.
Item {
    id: root

    visible: false

    property var _callbacks: ({})

    function run(cmd, callback) {
        if (root._callbacks[cmd] === undefined)
            root._callbacks[cmd] = [];
        root._callbacks[cmd].push(callback);
        source.connectSource(cmd);
    }

    P5Support.DataSource {
        id: source
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            const waiting = root._callbacks[sourceName] || [];
            delete root._callbacks[sourceName];
            const exitCode = Number(data["exit code"]);
            const stdout = String(data["stdout"] || "");
            for (const callback of waiting) {
                try {
                    callback(exitCode, stdout);
                } catch (error) {
                    console.warn("[RadioGlobe] exec callback failed", error);
                }
            }
        }
    }
}
