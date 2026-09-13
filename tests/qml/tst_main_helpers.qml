import QtQuick
import QtTest
import "../../contents/ui" as Ui

TestCase {
    name: "MainHelpers"

    function test_mpris_source_loads() {
        const component = Qt.createComponent(Qt.resolvedUrl("../../contents/ui/MprisSource.qml"));
        compare(component.status, Component.Ready, component.errorString());
    }

    Ui.Exec {
        id: exec
    }

    // The bundled GeoJSON is read through Exec because Qt blocks XMLHttpRequest
    // on local files unless QML_XHR_ALLOW_FILE_READ is set, which plasmashell
    // does not set. Guards that path end to end.
    function test_exec_reads_the_bundled_countries_file() {
        let result = null;
        const path = decodeURIComponent(String(Qt.resolvedUrl("../../contents/data/countries.json")).replace(/^file:\/\//, ""));
        exec.run("cat '" + path + "'", (code, out) => {
            result = {
                code,
                out
            };
        });
        tryVerify(() => result !== null, 5000);
        compare(result.code, 0);
        verify(JSON.parse(result.out).features.length > 100);
    }

    function test_exec_runs_a_command_and_reports_exit_code() {
        let result = null;
        exec.run("printf hello; exit 3", (code, out) => {
            result = {
                code,
                out
            };
        });
        tryVerify(() => result !== null, 5000);
        compare(result.code, 3);
        compare(result.out, "hello");
    }
}
