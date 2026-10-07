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

// Runs a launch command with PATH limited to fake commands that log how they
// were called. The fake mpv logs its own arguments, so quoting is checked on
// what actually arrives. Returns the PID printed and the log once it is in.
function runLaunch(probeFor, commands) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), "radioglobe-launch-"));
    const log = path.join(dir, "log");
    const fake = {
        sh: 'exec /bin/sh "$@"',
        mpv: 'for a in "$@"; do printf "%s\\n" "mpv:$a" >> "' + log + '"; done',
        setsid: 'printf "%s\\n" "setsid:$1" >> "' + log + '"; exec "$@"',
        ...commands(log)
    };
    for (const [name, body] of Object.entries(fake)) {
        const file = path.join(dir, name);
        fs.writeFileSync(file, "#!/bin/sh\n" + body + "\n");
        fs.chmodSync(file, 0o755);
    }
    const command = model.mpvLaunchCommand(probeFor(dir), ["--idle=yes", "--user-agent=It's mine"]);
    assert.equal(command.indexOf("sh -c "), 0, command);
    const stdout = execFileSync("/bin/sh", ["-c", command], { env: { PATH: dir }, encoding: "utf8" });
    let lines = [];
    for (let i = 0; i < 100 && !lines.includes("mpv:--user-agent=It's mine"); i++) {
        execFileSync("/bin/sleep", ["0.02"]);
        lines = fs.existsSync(log) ? fs.readFileSync(log, "utf8").split("\n").filter(Boolean) : [];
    }
    return { pid: stdout.trim(), lines, dir };
}

const withSystemd = log => ({
    systemctl: '[ "$1 $2" = "--user show-environment" ]',
    "systemd-run": 'printf "%s\\n" "systemd-run:$1 $2 $3 $4" >> "' + log + '"; shift 4; exec "$@"'
});

test("mpv is started in a scope of its own when the user's systemd answers", () => {
    const run = runLaunch(dir => ({ kind: "path", path: path.join(dir, "mpv") }), withSystemd);
    assert.match(run.pid, /^[0-9]+$/);
    assert.deepEqual(run.lines, ["setsid:systemd-run", "systemd-run:--user --scope --quiet --",
        "mpv:--idle=yes", "mpv:--user-agent=It's mine"]);
});

test("without systemd-run, mpv is started the plain way", () => {
    const run = runLaunch(dir => ({ kind: "path", path: path.join(dir, "mpv") }), () => ({}));
    assert.match(run.pid, /^[0-9]+$/);
    assert.deepEqual(run.lines, ["setsid:" + path.join(run.dir, "mpv"), "mpv:--idle=yes", "mpv:--user-agent=It's mine"]);
});

test("with no user systemd running, mpv is started the plain way", () => {
    const run = runLaunch(dir => ({ kind: "path", path: path.join(dir, "mpv") }),
        log => ({ ...withSystemd(log), systemctl: "exit 1" }));
    assert.deepEqual(run.lines, ["setsid:" + path.join(run.dir, "mpv"), "mpv:--idle=yes", "mpv:--user-agent=It's mine"]);
});

test("the mpv Flatpak is started through flatpak run", () => {
    const run = runLaunch(() => ({ kind: "flatpak", path: "" }), log => ({
        ...withSystemd(log),
        flatpak: 'printf "%s\\n" "flatpak:$1 $2" >> "' + log + '"; shift 2; exec mpv "$@"'
    }));
    assert.deepEqual(run.lines, ["setsid:systemd-run", "systemd-run:--user --scope --quiet --",
        "flatpak:run io.mpv.Mpv", "mpv:--idle=yes", "mpv:--user-agent=It's mine"]);
});

test("only the bus names mpv-mpris gives RadioGlobe's mpv carry the tag", () => {
    assert.equal(model.isRadioGlobeBusName("mpv.RadioGlobe"), true);
    assert.equal(model.isRadioGlobeBusName("mpv.RadioGlobe.instance-x7k2"), true);
    for (const name of ["mpv", "mpv.instance1234", "mpv.RadioGlobeX", "mpv.Other", "RadioGlobe", "", undefined, null])
        assert.equal(model.isRadioGlobeBusName(name), false, String(name));
});
