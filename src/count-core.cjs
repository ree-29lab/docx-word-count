// docx-word-count core: character and word counting for .docx and plain text.
//
// Platform independent on purpose. It runs in a browser page, in Node, and in any
// other JavaScript host that has TextDecoder, Blob, Response and DecompressionStream.
// Nothing here touches the DOM, the filesystem, or an OS API.
//
// Counting follows the convention word processors use, which is also what most
// counters and application word limits mean:
//   - each CJK character is one word
//   - a run of letters, digits and combining marks is one word, and stays one word
//     across apostrophes, hyphens and underscores (don't, state-of-the-art) and
//     across the separators inside numbers (1,000 / 3.14)
//   - everything else separates words
//   - text Word marks deleted (w:del / w:delText) and field codes (w:instrText) are skipped

(function (root, factory) {
    if (typeof module === "object" && module.exports) {
        module.exports = factory();
    } else {
        root.DocxCountCore = factory();
    }
}(typeof globalThis !== "undefined" ? globalThis : this, function () {
    "use strict";

    var TEXT_PARTS = /^word\/(document|header\d*|footer\d*|footnotes|endnotes)\.xml$/;
    var SKIP_SUBTREES = { del: 1, instrText: 1, delText: 1 };
    var TAG = /<(\/?)([A-Za-z0-9_.:-]+)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>/g;

    var CJK_CHAR = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Bopomofo}]/u;
    var TOKEN = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Bopomofo}]|\p{Nd}+(?:[.,]\p{Nd}+)*|[\p{L}\p{N}\p{M}]+(?:['\u2019\-\u2010\u2011_][\p{L}\p{N}\p{M}]+)*/gu;

    function decodeEntities(text) {
        if (text.indexOf("&") < 0) return text;
        return text
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&apos;/g, "'")
            .replace(/&#x([0-9a-fA-F]+);/g, function (_, hex) {
                return String.fromCodePoint(parseInt(hex, 16));
            })
            .replace(/&#(\d+);/g, function (_, dec) {
                return String.fromCodePoint(parseInt(dec, 10));
            })
            .replace(/&amp;/g, "&");
    }

    function isSpace(code) {
        return code === 32 || code === 9 || code === 10 || code === 13 ||
            code === 0xA0 || code === 0x3000;
    }

    function countText(text) {
        var cjk = 0;
        var words = 0;
        var noSpace = 0;
        var visible = 0;
        var match;

        TOKEN.lastIndex = 0;
        while ((match = TOKEN.exec(text)) !== null) {
            var token = match[0];
            if (token.length === 1 && CJK_CHAR.test(token)) cjk++;
            else words++;
            if (TOKEN.lastIndex === match.index) TOKEN.lastIndex++;
        }

        for (var i = 0; i < text.length; i++) {
            var code = text.charCodeAt(i);
            if (code !== 10 && code !== 13) visible++;
            if (!isSpace(code)) noSpace++;
        }

        return {
            cjk: cjk,
            words: words,
            total: cjk + words,
            chars: visible,
            charsNoSpace: noSpace
        };
    }

    // Turns one OOXML part into plain text, keeping the word boundaries intact.
    function partToText(xml) {
        var out = [];
        var skipName = null;
        var skipDepth = 0;
        var textStart = -1;
        var match;

        TAG.lastIndex = 0;
        while ((match = TAG.exec(xml)) !== null) {
            var closing = match[1] === "/";
            var name = match[2];
            var local = name.indexOf(":") >= 0 ? name.slice(name.indexOf(":") + 1) : name;
            var selfClosing = match[4] === "/";

            if (skipDepth > 0) {
                if (!selfClosing && local === skipName) skipDepth += closing ? -1 : 1;
                continue;
            }

            if (!closing && !selfClosing && SKIP_SUBTREES[local]) {
                skipName = local;
                skipDepth = 1;
                continue;
            }

            if (local === "t") {
                if (closing) {
                    if (textStart >= 0) {
                        out.push(decodeEntities(xml.slice(textStart, match.index)));
                        textStart = -1;
                    }
                } else if (!selfClosing) {
                    textStart = TAG.lastIndex;
                }
                continue;
            }

            if (closing) {
                if (local === "p") out.push("\n");
                continue;
            }

            if (selfClosing || local === "tab" || local === "br" || local === "cr") {
                if (local === "tab") out.push(" ");
                else if (local === "br" || local === "cr") out.push("\n");
            }
        }
        return out.join("");
    }

    function findEndOfCentralDirectory(view, bytes) {
        var lowest = Math.max(0, bytes.length - 22 - 65535);
        for (var i = bytes.length - 22; i >= lowest; i--) {
            if (view.getUint32(i, true) === 0x06054b50) return i;
        }
        return -1;
    }

    function listEntries(buffer) {
        var bytes = new Uint8Array(buffer);
        var view = new DataView(buffer);
        var eocd = findEndOfCentralDirectory(view, bytes);
        if (eocd < 0) {
            throw new Error("不是有效的 .docx（压缩包结构找不到；旧版 .doc 或加密文件会这样）");
        }
        var count = view.getUint16(eocd + 10, true);
        var offset = view.getUint32(eocd + 16, true);
        var entries = [];
        for (var index = 0; index < count; index++) {
            if (view.getUint32(offset, true) !== 0x02014b50) break;
            var nameLength = view.getUint16(offset + 28, true);
            var extraLength = view.getUint16(offset + 30, true);
            var commentLength = view.getUint16(offset + 32, true);
            entries.push({
                name: new TextDecoder().decode(bytes.subarray(offset + 46, offset + 46 + nameLength)),
                method: view.getUint16(offset + 10, true),
                compressedSize: view.getUint32(offset + 20, true),
                localOffset: view.getUint32(offset + 42, true)
            });
            offset += 46 + nameLength + extraLength + commentLength;
        }
        return entries;
    }

    async function entryBytes(buffer, entry) {
        var bytes = new Uint8Array(buffer);
        var view = new DataView(buffer);
        if (view.getUint32(entry.localOffset, true) !== 0x04034b50) {
            throw new Error("压缩包结构异常");
        }
        var nameLength = view.getUint16(entry.localOffset + 26, true);
        var extraLength = view.getUint16(entry.localOffset + 28, true);
        var start = entry.localOffset + 30 + nameLength + extraLength;
        var raw = bytes.subarray(start, start + entry.compressedSize);
        if (entry.method === 0) return raw;
        if (entry.method !== 8) {
            throw new Error("不支持的压缩方式：" + entry.method);
        }
        if (typeof DecompressionStream === "undefined") {
            throw new Error("这个浏览器太旧，解压不了 docx；请用较新的 Chrome / Edge / Safari / Firefox");
        }
        var stream = new Blob([raw]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
        return new Uint8Array(await new Response(stream).arrayBuffer());
    }

    // Counts a whole .docx. bodyOnly drops headers, footers, footnotes and endnotes.
    async function countDocxBuffer(buffer, options) {
        var bodyOnly = !!(options && options.bodyOnly);
        var entries = listEntries(buffer).filter(function (entry) {
            if (!TEXT_PARTS.test(entry.name)) return false;
            return bodyOnly ? entry.name === "word/document.xml" : true;
        });
        if (!entries.some(function (entry) {
            return entry.name === "word/document.xml";
        })) {
            throw new Error("这个文件里没有正文（不是 Word 文档？）");
        }

        var parts = [];
        var texts = [];
        var decoder = new TextDecoder("utf-8");
        for (var index = 0; index < entries.length; index++) {
            var bytes = await entryBytes(buffer, entries[index]);
            parts.push(entries[index].name);
            texts.push(partToText(decoder.decode(bytes)));
        }

        var counts = countText(texts.join("\n"));
        counts.parts = parts;
        return counts;
    }

    return {
        countText: countText,
        partToText: partToText,
        countDocxBuffer: countDocxBuffer,
        listEntries: listEntries
    };
}));
