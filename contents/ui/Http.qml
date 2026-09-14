import QtQuick

// Serialised HTTP queue on top of XMLHttpRequest: GET by default, or a
// form-encoded POST through `options`.
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

    // options: {method: "POST", body: "a=b&c=d"}. A POST is never retried on
    // a network error: the reply may have been lost after the server acted on
    // it, and sending again would act twice.
    function request(url, callback, options) {
        const settings = options && typeof options === "object" ? options : {};
        root._queue.push({
            url: url,
            callback: callback,
            method: settings.method === "POST" ? "POST" : "GET",
            body: settings.method === "POST" ? String(settings.body || "") : null,
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
            if (xhr.readyState !== 4 || job.settled || job !== root._current || xhr !== job.xhr)
                return;
            job.settled = true;
            root._finish(job, xhr.status, xhr.responseText);
        };
        xhr.open(job.method, job.url);
        xhr.setRequestHeader("User-Agent", root.userAgent);
        if (job.body !== null)
            xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        timeout.restart();
        if (job.body !== null)
            xhr.send(job.body);
        else
            xhr.send();
    }

    function _finish(job, status, text) {
        timeout.stop();
        if (status === 0 && job.method === "GET" && job.attempts < root.maxAttempts) {
            // job.settled was set true by the caller (onreadystatechange or the
            // timeout) to mark this attempt as processed; reset it here so the
            // deferred check below can tell a still-pending retry (settled
            // false) apart from a job abortAll() has since taken over (settled
            // true again, and _current no longer this job either).
            job.settled = false;
            Qt.callLater(() => {
                if (root._current === job && !job.settled)
                    root._send();
            });
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
