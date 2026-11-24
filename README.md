# docx-word-count

Count characters and words on any system — **macOS, Windows, Linux** — for a whole `.docx` file (no matter which app produced it: Word, Pages export, WPS, Google Docs download) or for just the text you selected.

One counting rule everywhere: **every CJK character counts one**, **every run of Latin letters, digits or apostrophes counts one word**.

| 你在哪 | 怎么用 | 装什么 |
|---|---|---|
| Windows / Linux | 双击 `docxcount.html` 用浏览器打开，拖入 .docx 或粘贴文字 | **什么都不用装** |
| macOS | 上面那招照用；另有 Finder 右键、服务菜单、终端命令 | `bash install.sh`（可选） |

三个入口读同一份测试样例（`tests/cases.json`），数字必须一致。

---

## 一、任何系统：单文件网页

下载仓库里的 **`docxcount.html`**，双击用浏览器打开（Chrome / Edge / Safari / Firefox 都行），然后把 `.docx` 拖进方框——或者把一段文字粘进第二个框，边打边出字数。

- 单选、多选、拖多个文件都可以，多文件末尾给合计。
- 勾「只数正文」就排除页眉页脚、脚注尾注。
- 页面右下角有个「自检 N/N 通过」，是页面自己现造一个 docx 跑完整条路的结果——红字就说明这个浏览器不支持。
- **完全离线**：文件不出本机，没有网络请求，不读剪贴板，不需要任何权限。

Windows 上没有右键菜单，想数别处的选中文字就 **`Ctrl+C` 复制 → 粘进页面的文字框**（`Ctrl+V`）。

## 二、macOS：装成右键菜单（可选）

```bash
git clone https://github.com/ree-29lab/docx-word-count.git
cd docx-word-count
bash install.sh
```

或者下载仓库后双击 `install.command`。`bash install.sh --dry-run` 只打印要做的事，不写任何文件。

装完三个入口：

1. **Finder** 里选中一个或多个 `.docx` › 右键 › **快速操作** › **统计字数** —— 数整篇。
2. 任何 app 里选中一段文字 › 右键 › **服务** › **统计选中字数** —— 只数选中的部分。
3. 终端 `docxcount`：

```bash
docxcount 报告.docx                  # 单个文件，分行明细
docxcount ~/Desktop/*.docx           # 多个文件，末尾给合计
docxcount --body-only 报告.docx      # 只数正文
docxcount --json 报告.docx           # 给脚本用
pbpaste | docxcount --stdin          # 数剪贴板里的文字
docxcount --text "随便一段文字"        # 直接数一段话
```

安装位置：

| 位置 | 是什么 |
|---|---|
| `~/Library/Application Support/DocxWordCount/` | 程序本体 |
| `~/Library/Services/DocxWordCount.workflow` | Finder 的「统计字数」（整篇） |
| `~/Library/Services/CountSelection.workflow` | 「服务」菜单的「统计选中字数」（选中部分） |
| `/usr/local/bin/docxcount`（不可写时退到 `~/bin`） | 终端命令 |

只需要系统自带的 `osascript` 与 `unzip`，不需要 Node、Python、Homebrew。卸载：`bash uninstall.sh`。

## 计数口径

| 内容 | 怎么算 |
|---|---|
| 中文、日文假名、韩文 | 每个字 **1** |
| 英文字母、数字、`'` 连成的串 | 整串算 **1 个词**（`don't`、`2026` 都算 1） |
| 空格、Tab、换行、标点 | 不算字数，只作分隔 |
| 修订中**被删除**的文字 | **不算** |
| 域代码（页码、目录域） | **不算** |
| 页眉、页脚、脚注、尾注 | **默认算**，勾「只数正文」/ `--body-only` 排除 |
| 批注 | 不算 |
| 文本框 | 算 |
| 图片、图表里的文字 | 不算（图片不是文本） |

**字数 = 中文字符 + 英文单词**，就是平时说的「字数」。

与 Word 自带「字数统计」的已知差异（**推断，未在 Word 上逐篇核对**）：

- 连字符词 `state-of-the-art`：这里按 3 个词，Word 算 1 个。
- 「字符数」口径可能与 Word 的「字符数（不计空格）」差个位数字。

## 支持的格式

只吃 **`.docx`**。`.doc`（旧二进制）、`.pages`（另一套 protobuf）、`.pdf` 要先另存为 docx。

## 排错

| 现象 | 处理 |
|---|---|
| 网页右下角红字「自检失败」 | 浏览器太旧，缺 `DecompressionStream`；换 Chrome / Edge / Safari 16.4+ / Firefox 113+ |
| 网页拖入文件报「不是有效的 .docx」 | 文件其实是 `.doc`，或加了打开密码 |
| macOS 右键菜单里没有「统计字数」 | 确认选中的是 `.docx`；`killall Finder` 刷新；菜单在「快速操作」里，可能折叠到「更多…」 |
| 右键菜单里没有「统计选中字数」 | 不同 app 叫法不同（Finder 是「快速操作」，Word / Pages / Safari 是「服务」）；也可以给它配快捷键：系统设置 › 键盘 › 键盘快捷键 › 服务 |
| 终端说 `command not found: docxcount` | 装到了 `~/bin`，把那行 `export PATH` 加进 `~/.zshrc` |
| 数字明显偏小 | 图片、公式、SmartArt 里的不是文本，不算；`--json` 会列出读了哪些部件 |

## 开发

两个实现，一份规则：

| 文件 | 跑在哪 |
|---|---|
| `src/count-core.cjs` | 跨平台核心：ZIP 解析 + OOXML 文本还原 + 计数。浏览器与 Node 共用 |
| `src/page.html` + `tools/build-page.py` | 把核心内联成单文件 `docxcount.html` |
| `src/wordcount.js` | macOS 实现（JXA）：用 `unzip` 与 `NSXMLDocument`，供终端命令与两个右键菜单调用 |
| `tests/cases.json` | 两份实现共同的验收数字 |

```bash
python3 tools/build-page.py     # 改完 page.html 或核心后重建 docxcount.html
bash tests/run.sh               # macOS 实现
node tests/run-node.mjs         # 跨平台核心
node tests/run-page.mjs         # 出货的 docxcount.html 自检
```

`tests/make_fixtures.py` 现造 7 份 docx，分别覆盖：拆成多个 run 的句子、修订删除、Tab 与换行、页眉、域代码、中英混排。

## 还没做的

- **Windows 原生右键菜单**：要在 Windows 上用 PowerShell + 注册表（`HKCU\Software\Classes\...\shell`）实现，本仓库还没有；Windows 目前走单文件网页这条路。做的话需要一台 Windows 机器验证。
- **Windows 上数选中文字**：没有 macOS 那种「服务」菜单，只能 `Ctrl+C` 再粘贴。
- 在 Word 自带统计上逐篇核对口径（见上文两条差异）。

## 授权

MIT，见 [LICENSE](LICENSE)。
