// Loads a QML JavaScript library into a node vm context so its top-level
// functions can be unit-tested without Qt. Strips `.pragma` / `.import`
// lines, which node cannot parse.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));

export function loadQmlJs(relativePath) {
    const file = path.resolve(here, "..", "..", relativePath);
    const source = fs.readFileSync(file, "utf8")
        .replace(/^\s*\.(pragma|import)\b.*$/gm, "");
    const context = { Math, Number, Array, String, JSON, isFinite, Date, console };
    vm.createContext(context);
    vm.runInContext(source, context, { filename: file });
    return context;
}
