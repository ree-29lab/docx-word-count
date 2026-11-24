// Explains where the gap between 字数 and 字符数 comes from for one .docx.
//   node tools/explain.js FILE.docx
const fs = require("node:fs");
const { execFileSync } = require("node:child_process");
const path = require("node:path");
const core = require("../src/count-core.cjs");

const file = process.argv[2];
const buffer = fs.readFileSync(file);
const arrayBuffer = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);

const entries = core.listEntries(arrayBuffer);
const parts = entries.filter((entry) =>
    /^word\/(document|header\d*|footer\d*|footnotes|endnotes)\.xml$/.test(entry.name));

const texts = parts.map((part) =>
    core.partToText(execFileSync("/usr/bin/unzip", ["-p", file, part.name], { maxBuffer: 1 << 28 }).toString("utf8")));
const text = texts.join("\n");

const counts = core.countText(text);
const cjk = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Bopomofo}]/u;
const punctMap = {};
const otherMap = {};
let latin = 0;
let digits = 0;
let space = 0;

const tokens = text.match(/\p{Script=Han}|\p{Script=Hiragana}|\p{Script=Katakana}|\p{Script=Hangul}|\p{Script=Bopomofo}|\p{Nd}+(?:[.,]\p{Nd}+)*|[\p{L}\p{N}\p{M}]+(?:['\u2019\-\u2010\u2011_][\p{L}\p{N}\p{M}]+)*/gu) || [];
const nonCjkTokens = tokens.filter((token) => !(token.length === 1 && cjk.test(token)));

for (const ch of text) {
    if (ch === "\n" || ch === "\r") continue;
    if (ch === " " || ch === "\t" || ch === "\u3000" || ch === "\u00a0") { space++; continue; }
    if (cjk.test(ch)) continue;
    if (/\p{L}|\p{N}/u.test(ch)) { if (/\p{N}/u.test(ch)) digits++; else latin++; continue; }
    if (/\p{P}/u.test(ch)) punctMap[ch] = (punctMap[ch] || 0) + 1;
    else otherMap[ch] = (otherMap[ch] || 0) + 1;
}

const punct = Object.values(punctMap).reduce((a, b) => a + b, 0);
const other = Object.values(otherMap).reduce((a, b) => a + b, 0);
const format = (map) => Object.entries(map).sort((a, b) => b[1] - a[1]).map(([c, n]) => `${c}×${n}`).join(" ");

console.log("文件:", path.basename(file));
console.log("读到的部件:", parts.map((p) => p.name).join(", "));
console.log("");
console.log("中文（字数）      :", counts.cjk);
console.log("英文词 + 数字词    :", counts.words, nonCjkTokens.length ? "(" + nonCjkTokens.slice(0, 8).join(", ") + ")" : "");
console.log("字数合计          :", counts.total);
console.log("");
console.log("汉字              :", counts.cjk);
console.log("标点              :", punct, format(punctMap).slice(0, 90));
console.log("字母/数字          :", latin + digits);
console.log("其他符号          :", other, format(otherMap).slice(0, 60));
console.log("不计空格的字符数    :", counts.charsNoSpace);
console.log("含空格的字符数      :", counts.chars, "（空格", space, "个）");
console.log("差（字符 − 字数）  :", counts.charsNoSpace - counts.total);
