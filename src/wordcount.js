// docx-word-count — count characters and words inside .docx files.
//
//   osascript -l JavaScript wordcount.js FILE... [--body-only] [--json] [--dialog]
//
// A .docx is a zip archive; the text lives in word/document.xml plus optional
// word/header*.xml, word/footer*.xml, word/footnotes.xml, word/endnotes.xml.
// Nothing here depends on which application produced the file.
//
// Counting rules: CJK characters count one each, runs of Latin letters, digits and
// apostrophes count one word each (so "don't" is one word), everything else separates.

ObjC.import("Foundation");

var PARTS_RE = /^word\/(document|header\d*|footer\d*|footnotes|endnotes)\.xml$/;

// doShellScript returns AppleScript text, whose line endings are CR rather than LF.
function shell(command) {
    var app = Application.currentApplication();
    app.includeStandardAdditions = true;
    return app.doShellScript(command).replace(/\r\n?/g, "\n");
}

function quote(path) {
    return "'" + String(path).replace(/'/g, "'\\''") + "'";
}

function writeToStdout(text) {
    var data = $.NSString.alloc.initWithUTF8String(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
    $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

function writeToStderr(text) {
    var data = $.NSString.alloc.initWithUTF8String(text + "\n").dataUsingEncoding($.NSUTF8StringEncoding);
    $.NSFileHandle.fileHandleWithStandardError.writeData(data);
}

function fileExists(path) {
    return $.NSFileManager.defaultManager.fileExistsAtPath(path);
}

// Same counting rule as the Notes panel: CJK per character, Latin per word.
function countText(text) {
    var cjk = 0;
    var words = 0;
    var noSpace = 0;
    var visible = 0;
    var inWord = false;
    for (var i = 0; i < text.length; i++) {
        var c = text.charCodeAt(i);
        if (c !== 10 && c !== 13) visible++;
        if (c !== 32 && c !== 9 && c !== 10 && c !== 13) noSpace++;
        if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF) ||
            (c >= 0x3040 && c <= 0x309F) || (c >= 0x30A0 && c <= 0x30FF) ||
            (c >= 0xAC00 && c <= 0xD7AF) || (c >= 0xF900 && c <= 0xFAFF)) {
            cjk++;
            inWord = false;
        } else if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 39) {
            if (!inWord) {
                words++;
                inWord = true;
            }
        } else {
            inWord = false;
        }
    }
    return { cjk: cjk, words: words, total: cjk + words, charsNoSpace: noSpace, chars: visible };
}

function localNameOf(node) {
    var name = node.name;
    if (!name) return "";
    var value = name.js;
    var colon = value.lastIndexOf(":");
    return colon >= 0 ? value.slice(colon + 1) : value;
}

// Escapes are already decoded by the XML parser; text nodes of w:t are literal.
function walkNode(node, out) {
    if (node.kind !== $.NSXMLElementKind) return;
    var name = localNameOf(node);
    if (name === "del" || name === "instrText" || name === "delText") return;
    if (name === "t") {
        var value = node.stringValue;
        if (value && !(value.isNil && value.isNil())) out.push(String(value.js));
        return;
    }
    if (name === "tab") {
        out.push(" ");
        return;
    }
    if (name === "br" || name === "cr") {
        out.push("\n");
        return;
    }
    var count = node.childCount;
    for (var i = 0; i < count; i++) walkNode(node.childAtIndex(i), out);
    if (name === "p") out.push("\n");
}

function partText(xml) {
    var data = $.NSString.alloc.initWithUTF8String(xml).dataUsingEncoding($.NSUTF8StringEncoding);
    var doc = $.NSXMLDocument.alloc.initWithDataOptionsError(data, 0, null);
    if (!doc || doc.isNil()) return null;
    var out = [];
    walkNode(doc.rootElement, out);
    return out.join("");
}

function readPart(path, entry) {
    return shell("/usr/bin/unzip -p " + quote(path) + " " + quote(entry) + " 2>/dev/null");
}

function countFile(path, bodyOnly) {
    var result = { path: path, ok: false, error: "", parts: [] };
    if (!fileExists(path)) {
        result.error = "文件不存在";
        return result;
    }
    if (!/\.docx$/i.test(path)) {
        result.error = "不是 .docx（只支持 .docx）";
        return result;
    }

    var listing;
    try {
        listing = shell("/usr/bin/unzip -Z1 " + quote(path) + " 2>/dev/null");
    } catch (e) {
        result.error = "读不了这个文件（压缩包损坏或被加密）";
        return result;
    }

    var entries = listing.split("\n").map(function (line) {
        return line.trim();
    }).filter(function (line) {
        return line !== "" && PARTS_RE.test(line);
    });

    if (!bodyOnly) {
        // keep every matching part
    } else {
        entries = entries.filter(function (entry) {
            return entry === "word/document.xml";
        });
    }
    if (entries.indexOf("word/document.xml") < 0) {
        result.error = "这个 .docx 里没有正文（不是有效的 Word 文档？）";
        return result;
    }

    var texts = [];
    for (var i = 0; i < entries.length; i++) {
        var xml;
        try {
            xml = readPart(path, entries[i]);
        } catch (e) {
            continue;
        }
        var part = partText(xml);
        if (part === null) continue;
        texts.push(part);
        result.parts.push(entries[i]);
    }

    var counts = countText(texts.join("\n"));
    result.cjk = counts.cjk;
    result.words = counts.words;
    result.total = counts.total;
    result.charsNoSpace = counts.charsNoSpace;
    result.chars = counts.chars;
    result.ok = true;
    return result;
}

function readStdin() {
    var data = $.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFile;
    if (!data || data.isNil()) return "";
    var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding);
    return (text && !text.isNil()) ? text.js : "";
}

function reportCounts(counts) {
    var lines = [];
    lines.push("中文字符 " + pad(counts.cjk, 6) + "    英文单词 " + pad(counts.words, 5));
    lines.push("字数     " + pad(counts.total, 6) + "    字符数(不计空格) " + pad(counts.charsNoSpace, 6));
    lines.push("字符数(含空格) " + pad(counts.chars, 6));
    return lines.join("\n");
}

function pad(value, width) {
    var text = String(value);
    while (text.length < width) text = " " + text;
    return text;
}

function report(results) {
    var lines = [];
    for (var i = 0; i < results.length; i++) {
        var r = results[i];
        var name = r.path.replace(/^.*\//, "");
        if (!r.ok) {
            lines.push(name + "：统计失败（" + r.error + "）");
            continue;
        }
        lines.push(name);
        lines.push("  中文字符 " + pad(r.cjk, 6) + "    英文单词 " + pad(r.words, 5));
        lines.push("  字数     " + pad(r.total, 6) + "    字符数(不计空格) " + pad(r.charsNoSpace, 6));
        lines.push("  字符数(含空格) " + pad(r.chars, 6));
    }
    if (results.length > 1) {
        var totals = { cjk: 0, words: 0, total: 0, charsNoSpace: 0, chars: 0 };
        var okCount = 0;
        for (var j = 0; j < results.length; j++) {
            if (!results[j].ok) continue;
            okCount++;
            totals.cjk += results[j].cjk;
            totals.words += results[j].words;
            totals.total += results[j].total;
            totals.charsNoSpace += results[j].charsNoSpace;
            totals.chars += results[j].chars;
        }
        if (okCount > 1) {
            lines.push("");
            lines.push("合计 " + okCount + " 个文件：中文字符 " + totals.cjk + " / 英文单词 " + totals.words +
                " / 字数 " + totals.total + " / 字符数(不计空格) " + totals.charsNoSpace);
        }
    }
    return lines.join("\n");
}

function run(argv) {
    ObjC.import("stdlib");

    if (argv.indexOf("--selftest") >= 0) {
        var cases = [
            ["", 0, 0],
            ["你好 world 42", 2, 2],
            ["don't stop", 0, 2],
            ["あア한", 3, 0],
            ["  多   空格  ", 3, 0]
        ];
        var failures = 0;
        for (var i = 0; i < cases.length; i++) {
            var got = countText(cases[i][0]);
            var pass = got.cjk === cases[i][1] && got.words === cases[i][2];
            if (!pass) failures++;
            writeToStdout((pass ? "PASS " : "FAIL ") + JSON.stringify(cases[i][0]) +
                " cjk=" + got.cjk + " words=" + got.words);
        }
        writeToStdout(failures === 0 ? "selftest: all " + cases.length + " cases passed"
            : "selftest: " + failures + " failed");
        $.exit(failures === 0 ? 0 : 1);
    }

    var paths = [];
    var bodyOnly = false;
    var asJson = false;
    var asDialog = false;
    var asStdin = false;
    var literal = null;

    for (var i = 0; i < argv.length; i++) {
        var arg = argv[i];
        if (arg === "--body-only") bodyOnly = true;
        else if (arg === "--json") asJson = true;
        else if (arg === "--dialog") asDialog = true;
        else if (arg === "--stdin") asStdin = true;
        else if (arg === "--text") {
            if (i + 1 >= argv.length) {
                writeToStderr("--text 后面要跟一段文字");
                $.exit(2);
            }
            literal = argv[++i];
        }
        else if (arg === "-h" || arg === "--help") {
            writeToStdout("用法: wordcount 文件.docx [更多文件…] [--body-only] [--json] [--dialog]");
            writeToStdout("  --body-only  只数正文，不含页眉页脚与脚注尾注");
            writeToStdout("  --json       输出 JSON");
            writeToStdout("  --dialog     用弹窗显示结果（快速操作用）");
            writeToStdout("  --stdin      统计管道送进来的文字（选中文字求字数用）");
            writeToStdout("  --text 文字   统计一段直接给出的文字");
            $.exit(0);
        } else if (arg.charAt(0) === "-") {
            writeToStderr("未知参数: " + arg);
            $.exit(2);
        } else {
            paths.push(arg);
        }
    }

    if (asStdin || literal !== null) {
        var input = literal !== null ? literal : readStdin();
        var counts = countText(input);
        if (asJson) {
            writeToStdout(JSON.stringify({
                cjk: counts.cjk,
                words: counts.words,
                total: counts.total,
                charsNoSpace: counts.charsNoSpace,
                chars: counts.chars
            }, null, 2));
        } else if (asDialog) {
            var dialogApp = Application.currentApplication();
            dialogApp.includeStandardAdditions = true;
            dialogApp.displayDialog(reportCounts(counts), {
                withTitle: "统计选中字数",
                buttons: ["好"],
                defaultButton: "好"
            });
        } else {
            writeToStdout(reportCounts(counts));
        }
        $.exit(0);
    }

    if (paths.length === 0) {
        writeToStderr("用法: wordcount 文件.docx [更多文件…] [--body-only] [--json] [--dialog]");
        $.exit(2);
    }

    var results = paths.map(function (path) {
        return countFile(path, bodyOnly);
    });

    if (asJson) {
        writeToStdout(JSON.stringify({ files: results }, null, 2));
    } else if (asDialog) {
        var app = Application.currentApplication();
        app.includeStandardAdditions = true;
        app.displayDialog(report(results), {
            withTitle: "统计字数",
            buttons: ["好"],
            defaultButton: "好"
        });
    } else {
        writeToStdout(report(results));
    }

    var failed = results.filter(function (r) {
        return !r.ok;
    });
    $.exit(failed.length === 0 ? 0 : 1);
}
