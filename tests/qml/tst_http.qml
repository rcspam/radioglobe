import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "Http"

    property var created: []

    function makeFakeXhr() {
        const xhr = {
            readyState: 0,
            status: 0,
            responseText: "",
            headers: ({}),
            url: "",
            aborted: false,
            onreadystatechange: null,
            open: function (method, url) {
                this.method = method;
                this.url = url;
                this.readyState = 1;
            },
            setRequestHeader: function (name, value) {
                this.headers[name] = value;
            },
            send: function (body) {
                this.body = body;
            },
            abort: function () {
                this.aborted = true;
                this.readyState = 4;
                this.status = 0;
                if (this.onreadystatechange)
                    this.onreadystatechange();
                this.readyState = 0;
            },
            respond: function (status, text) {
                this.readyState = 4;
                this.status = status;
                this.responseText = text;
                this.onreadystatechange();
            }
        };
        created.push(xhr);
        return xhr;
    }

    Ui.Http {
        id: http
        userAgent: "RadioGlobe/test"
        timeoutMs: 40
        xhrFactory: makeFakeXhr
    }

    function init() {
        created = [];
    }

    function test_sets_user_agent_and_delivers_response() {
        let got = null;
        http.request("https://a/x", (status, text) => {
            got = {
                status,
                text
            };
        });
        compare(created.length, 1);
        compare(created[0].headers["User-Agent"], "RadioGlobe/test");
        compare(created[0].url, "https://a/x");
        created[0].respond(200, "[1]");
        compare(got.status, 200);
        compare(got.text, "[1]");
        compare(http.busy, false);
    }

    function test_requests_are_serialised() {
        http.request("https://a/1", () => {});
        http.request("https://a/2", () => {});
        compare(created.length, 1);
        created[0].respond(200, "");
        compare(created.length, 2);
        compare(created[1].url, "https://a/2");
        created[1].respond(200, "");
    }

    function test_post_sends_body_and_never_retries() {
        let got = null;
        http.request("https://a/add", (status, text) => {
            got = status;
        }, {
            method: "POST",
            body: "name=x&url=y"
        });
        compare(created.length, 1);
        compare(created[0].method, "POST");
        compare(created[0].body, "name=x&url=y");
        compare(created[0].headers["Content-Type"], "application/x-www-form-urlencoded");
        // A lost reply after a POST that did arrive would add the station
        // twice: the caller gets the failure instead of a silent retry.
        created[0].respond(0, "");
        compare(got, 0);
        wait(20);
        compare(created.length, 1);
    }

    function test_get_ignores_body_and_keeps_retrying() {
        http.request("https://a/x", () => {});
        compare(created[0].method, "GET");
        compare(created[0].body, undefined);
        compare(created[0].headers["Content-Type"], undefined);
        created[0].respond(0, "");
        tryCompare(created, "length", 2);
        created[1].respond(200, "");
    }

    function test_network_error_is_retried_once_then_reported() {
        let got = -1;
        http.request("https://a/x", status => {
            got = status;
        });
        created[0].respond(0, "");
        tryCompare(created, "length", 2);
        compare(got, -1);
        created[1].respond(0, "");
        compare(got, 0);
    }

    function test_timeout_aborts_and_retries() {
        let got = -1;
        http.request("https://a/slow", status => {
            got = status;
        });
        tryVerify(() => created[0].aborted, 500);
        tryCompare(created, "length", 2);
        created[1].respond(200, "ok");
        compare(got, 200);
    }

    function test_abortAll_reports_zero_and_clears_queue() {
        let statuses = [];
        http.request("https://a/1", s => statuses.push(s));
        http.request("https://a/2", s => statuses.push(s));
        http.abortAll();
        compare(statuses, [0, 0]);
        compare(http.busy, false);
        compare(created.length, 1);
    }

    function test_stale_xhr_from_first_attempt_is_ignored_after_retry() {
        let got = -1;
        http.request("https://a/x", status => {
            got = status;
        });
        created[0].respond(0, "");
        tryCompare(created, "length", 2);
        created[0].respond(200, "stale");
        compare(got, -1);
        compare(http.busy, true);
        created[1].respond(200, "fresh");
        compare(got, 200);
    }

    function test_pending_retry_does_not_resend_a_new_request_after_abortAll() {
        let got = -1;
        http.request("https://a/1", () => {});
        created[0].respond(0, "");
        http.abortAll();
        http.request("https://a/2", status => {
            got = status;
        });
        // Short wait: long enough for the stale Qt.callLater to run, well
        // under timeoutMs (40) so the fresh /2 request's own timeout does
        // not fire and mask the assertion with a legitimate retry.
        wait(10);
        compare(created.length, 2);
        compare(created[1].url, "https://a/2");
        created[1].respond(200, "ok");
        compare(got, 200);
    }
}
