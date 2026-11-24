// Loads the built docxcount.html, runs its scripts against a minimal DOM stub, and
// checks the page's own self-test badge. This proves the shipped page — not just
// the core — counts correctly, without needing a browser session.
//
//   node tests/run-page.mjs

import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const htmlPath = path.resolve(here, "..", "docxcount.html");
const html = fs.readFileSync(htmlPath, "utf8");

const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
if (scripts.length !== 2) {
    console.error(`expected 2 script blocks in the page, found ${scripts.length}`);
    process.exit(1);
}

function element(id) {
    return {
        id,
        textContent: "",
        className: "",
        value: "",
        checked: false,
        style: {},
        classList: { add() {}, remove() {} },
        addEventListener() {},
        appendChild() {},
        click() {}
    };
}

const nodes = new Map();
const query = (selector) => {
    if (!nodes.has(selector)) nodes.set(selector, element(selector));
    return nodes.get(selector);
};

const sandbox = {
    console,
    TextEncoder,
    TextDecoder,
    Blob,
    Response,
    DecompressionStream,
    setTimeout,
    Uint8Array,
    Uint32Array,
    ArrayBuffer,
    DataView,
    document: {
        getElementById: query,
        querySelector: query,
        createElement: () => element("created")
    },
    addEventListener() {}
};
// In a browser window === globalThis; mirror that so the UMD core and the page agree.
sandbox.window = sandbox;
sandbox.self = sandbox;

const context = vm.createContext(sandbox);
vm.runInContext(scripts[0], context, { filename: "count-core" });
const coreExposed = typeof sandbox.DocxCountCore === "object" && sandbox.DocxCountCore !== null;
if (!coreExposed) {
    console.error("FAIL  页面里的核心没有挂到 window.DocxCountCore");
    process.exit(1);
}
vm.runInContext(scripts[1], context, { filename: "page-ui" });

const badge = query("badge");
let waited = 0;
while (waited < 3000 && !/通过|失败|出错/.test(badge.textContent)) {
    await new Promise((resolve) => setTimeout(resolve, 25));
    waited += 25;
}

const text = badge.textContent || "(空)";
if (text === "自检 5/5 通过") {
    console.log("PASS  页面自检：" + text);
    process.exit(0);
}
console.error("FAIL  页面自检结果：" + text);
process.exit(1);
