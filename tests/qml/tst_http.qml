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
                this.url = url;
                this.readyState = 1;
            },
            setRequestHeader: function (name, value) {
                this.headers[name] = value;
            },
            send: function () {},
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
}
