// Runs the platform-independent core (src/count-core.cjs) against the shared
// expectations in tests/cases.json. This is the suite that also backs
// docxcount.html, since the page embeds exactly the same core.
//
//   node tests/run-node.mjs
//
// Fixtures are built with python3 (tests/make_fixtures.py) because generating a
// zip by hand in JavaScript would be more code than the thing under test.

import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const core = require(path.join(root, "src/count-core.cjs"));
const cases = JSON.parse(fs.readFileSync(path.join(here, "cases.json"), "utf8"));

const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "docxcount-"));
const fixtures = path.join(workDir, "fixtures");
execFileSync("python3", [path.join(here, "make_fixtures.py"), fixtures], { stdio: "ignore" });

let checks = 0;
let failures = 0;

function report(label, got, wantCjk, wantWords) {
    checks++;
    if (got.cjk === wantCjk && got.words === wantWords) {
        console.log(`PASS  ${label.padEnd(34)} cjk=${wantCjk} words=${wantWords}`);
    } else {
        failures++;
        console.log(`FAIL  ${label.padEnd(34)} want cjk=${wantCjk} words=${wantWords}, got cjk=${got.cjk} words=${got.words}`);
    }
}

for (const testCase of cases.docx) {
    const buffer = fs.readFileSync(path.join(fixtures, testCase.fixture));
    const file = fs.readFileSync(path.join(fixtures, testCase.fixture));
    const counts = await core.countDocxBuffer(
        file.buffer.slice(file.byteOffset, file.byteOffset + file.byteLength),
        { bodyOnly: testCase.bodyOnly }
    );
    void buffer;
    report(`${testCase.fixture}${testCase.bodyOnly ? " (bodyOnly)" : ""}`, counts, testCase.cjk, testCase.words);
}

for (const testCase of cases.text) {
    report(`text ${JSON.stringify(testCase.text)}`, core.countText(testCase.text), testCase.cjk, testCase.words);
}

// A non-zip file must fail instead of reporting zeroes.
checks++;
const notDocx = Buffer.from("this is not a docx");
try {
    await core.countDocxBuffer(notDocx.buffer.slice(notDocx.byteOffset, notDocx.byteOffset + notDocx.byteLength), {});
    failures++;
    console.log("FAIL  non-docx input was accepted");
} catch {
    console.log("PASS  non-docx input rejected");
}

fs.rmSync(workDir, { recursive: true, force: true });

console.log("");
if (failures === 0) {
    console.log(`全部 ${checks} 项通过`);
    process.exit(0);
}
console.log(`${failures} / ${checks} 项失败`);
process.exit(1);
