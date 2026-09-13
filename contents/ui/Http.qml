import QtQuick

// Serialised HTTP GET queue on top of XMLHttpRequest.
// Qt's QML XHR has no working timeout, so a Timer aborts the request; abort()
// is never called from inside the request's own onreadystatechange (that
// re-enters the dying reply and can crash plasmashell). One request at a time
// keeps the connection alive: fresh TLS connections to Radio Browser
// intermittently get reset.
Item {
    id: root

    visible: false

    property string userAgent: "RadioGlobe"
    property int timeoutMs: 12000
    property int maxAttempts: 2
    property var xhrFactory: function () {
        return new XMLHttpRequest();
    }

    readonly property bool busy: root._current !== null
    property var _queue: []
    property var _current: null

    function request(url, callback) {
        root._queue.push({
            url: url,
            callback: callback,
            attempts: 0,
            settled: false,
            xhr: null
        });
        root._next();
    }

    function abortAll() {
        const pending = root._queue;
        root._queue = [];
        const current = root._current;
        root._current = null;
        timeout.stop();
        if (current) {
            current.settled = true;
            try {
                current.xhr.abort();
            } catch (error) {}
            root._deliver(current, 0, "");
        }
        for (const job of pending)
            root._deliver(job, 0, "");
    }

    function _next() {
        if (root._current !== null || root._queue.length === 0)
            return;
        root._current = root._queue.shift();
        root._send();
    }

    function _send() {
        const job = root._current;
        if (!job)
            return;
        job.attempts += 1;
        job.settled = false;
        const xhr = root.xhrFactory();
        job.xhr = xhr;
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4 || job.settled || job !== root._current)
                return;
            job.settled = true;
            root._finish(job, xhr.status, xhr.responseText);
        };
        xhr.open("GET", job.url);
        xhr.setRequestHeader("User-Agent", root.userAgent);
        timeout.restart();
        xhr.send();
    }

    function _finish(job, status, text) {
        timeout.stop();
        if (status === 0 && job.attempts < root.maxAttempts) {
            Qt.callLater(root._send);
            return;
        }
        root._current = null;
        root._deliver(job, status, text);
        root._next();
    }

    function _deliver(job, status, text) {
        try {
            job.callback(status, text);
        } catch (error) {
            console.warn("[RadioGlobe] http callback failed for", job.url, error);
        }
    }

    Timer {
        id: timeout
        interval: root.timeoutMs
        onTriggered: {
            const job = root._current;
            if (!job || job.settled)
                return;
            job.settled = true;
            try {
                job.xhr.abort();
            } catch (error) {}
            root._finish(job, 0, "");
        }
    }

    Component.onDestruction: abortAll()
}
