#!/usr/bin/env python3
"""Builds the .docx fixtures that tests/run.sh counts.

Development only: needs python3, and only ever writes into the directory it is
given. Each fixture isolates one rule the counter has to get right.
"""

import os
import sys
import zipfile

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
"""


def document(body: str) -> str:
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        "<w:body>" + body + "</w:body></w:document>"
    )


def para(*runs: str) -> str:
    return "<w:p>" + "".join(runs) + "</w:p>"


def run(text: str) -> str:
    return '<w:r><w:t xml:space="preserve">' + text + "</w:t></w:r>"


def build(path: str, parts: dict) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", RELS)
        for name, xml in parts.items():
            z.writestr(name, xml)


def main(target: str) -> None:
    os.makedirs(target, exist_ok=True)

    # One paragraph, mixed script, one number.
    build(os.path.join(target, "simple.docx"), {
        "word/document.xml": document(para(run("你好 world 42"))),
    })

    # Same sentence, split across runs the way Word splits formatting changes.
    build(os.path.join(target, "split-runs.docx"), {
        "word/document.xml": document(
            para(run("你"), run("好"), run(" wo"), run("rld"), run(" 4"), run("2"))
        ),
    })

    # Tracked deletion: the deleted text must not count.
    build(os.path.join(target, "tracked-deletion.docx"), {
        "word/document.xml": document(
            para(
                run("保留"),
                '<w:del w:id="1" w:author="t" w:date="2026-01-01T00:00:00Z">'
                '<w:r><w:delText>删掉</w:delText></w:r></w:del>',
                run("留着"),
            )
        ),
    })

    # Tab and line break separate words; they must not join them.
    build(os.path.join(target, "tab-and-break.docx"), {
        "word/document.xml": document(
            "<w:p>" + run("A") + "<w:r><w:tab/></w:r>" + run("B") + "<w:r><w:br/></w:r>" + run("C") + "</w:p>"
        ),
    })

    # Header counts by default, and drops out with --body-only.
    build(os.path.join(target, "with-header.docx"), {
        "word/document.xml": document(para(run("正文"))),
        "word/header1.xml": document(para(run("页眉"))),
    })

    # A field code (TOC, page number) must not be counted as text.
    build(os.path.join(target, "field-code.docx"), {
        "word/document.xml": document(
            para(run("前面"), "<w:r><w:instrText>PAGE</w:instrText></w:r>", run("后面"))
        ),
    })

    print("fixtures written to " + target)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "fixtures")
