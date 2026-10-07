import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { loadQmlJs } from "./qmljs.mjs";

const model = loadQmlJs("contents/ui/RadioModel.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// Runs the probe script the way the executable engine does, with PATH limited
// to a scratch directory holding only the fake commands a case needs.
function runProbe(script, commands) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "radioglobe-probe-"));
    for (const [name, body] of Object.entries(commands)) {
        const file = path.join(dir, name);
        fs.writeFileSync(file, "#!/bin/sh\n" + body + "\n");
        fs.chmodSync(file, 0o755);
    }
    try {
        const stdout = execFileSync("/bin/sh", ["-c", script], { env: { PATH: dir }, encoding: "utf8" });
        return { exitCode: 0, stdout, dir };
    } catch (error) {
        return { exitCode: error.status, stdout: String(error.stdout || ""), dir };
    }
}

test("the probe finds mpv on PATH first, even with the Flatpak installed", () => {
    const run = runProbe(model.mpvProbeScript(""), { mpv: "exit 0", flatpak: "exit 0" });
    assert.deepEqual(plain(model.parseMpvProbe("", run.exitCode, run.stdout)), { kind: "path", path: path.join(run.dir, "mpv") });
});

test("the probe falls back to the mpv Flatpak when mpv is not on PATH", () => {
    const run = runProbe(model.mpvProbeScript(""), { flatpak: '[ "$1 $2" = "info io.mpv.Mpv" ]' });
    assert.deepEqual(plain(model.parseMpvProbe("", run.exitCode, run.stdout)), { kind: "flatpak", path: "" });
});

test("the probe reports nothing when flatpak exists without the mpv Flatpak", () => {
    const run = runProbe(model.mpvProbeScript(""), { flatpak: "exit 1" });
    assert.deepEqual(plain(model.parseMpvProbe("", run.exitCode, run.stdout)), { kind: "missing", path: "" });
});

test("the probe reports nothing without mpv or flatpak", () => {
    const run = runProbe(model.mpvProbeScript(""), {});
    assert.deepEqual(plain(model.parseMpvProbe("", run.exitCode, run.stdout)), { kind: "missing", path: "" });
});

test("a custom path is the only mpv considered, with no fallback", () => {
    const missing = runProbe(model.mpvProbeScript("/opt/none/mpv.AppImage"), { mpv: "exit 0", flatpak: "exit 0" });
    assert.deepEqual(plain(model.parseMpvProbe("/opt/none/mpv.AppImage", missing.exitCode, missing.stdout)), { kind: "missing", path: "" });
    const found = runProbe(model.mpvProbeScript(" /bin/sh "), {});
    assert.deepEqual(plain(model.parseMpvProbe(" /bin/sh ", found.exitCode, found.stdout)), { kind: "custom", path: "/bin/sh" });
});

test("the launch command starts the probed mpv detached and prints its PID", () => {
    const options = ["--idle=yes", "--user-agent=It's mine"];
    assert.equal(model.mpvLaunchCommand({ kind: "path", path: "/usr/bin/mpv" }, options),
        "sh -c " + model.shellQuote("setsid '/usr/bin/mpv' '--idle=yes' '--user-agent=It'\\''s mine' >/dev/null 2>&1 & echo $!"));
    assert.equal(model.mpvLaunchCommand({ kind: "flatpak", path: "" }, ["--idle=yes"]),
        "sh -c " + model.shellQuote("setsid 'flatpak' 'run' 'io.mpv.Mpv' '--idle=yes' >/dev/null 2>&1 & echo $!"));
});

test("only the bus names mpv-mpris gives RadioGlobe's mpv carry the tag", () => {
    assert.equal(model.isRadioGlobeBusName("mpv.RadioGlobe"), true);
    assert.equal(model.isRadioGlobeBusName("mpv.RadioGlobe.instance-x7k2"), true);
    for (const name of ["mpv", "mpv.instance1234", "mpv.RadioGlobeX", "mpv.Other", "RadioGlobe", "", undefined, null])
        assert.equal(model.isRadioGlobeBusName(name), false, String(name));
});
