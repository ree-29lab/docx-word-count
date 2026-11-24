# docx-word-count

Count characters and words on any system — **macOS, Windows, Linux** — for a whole `.docx` file (no matter which app produced it: Word, Pages export, WPS, Google Docs download) or for just the text you selected.

One counting rule everywhere: **every CJK character counts one**, **every run of Latin letters, digits or apostrophes counts one word**.

完整的中文说明（安装、用法、卸载、排错）见 **[使用说明.md](使用说明.md)**。

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

### 手机上能用吗？

| 你想用的 | iPhone / iPad / Android |
|---|---|
| `docxcount.html`（本仓库） | **能用**：iOS 16.4+ / 较新的 Chrome 都支持所需接口，在页面里选「文件」里的 .docx 即可 |
| `notes-wordcount`（另一个仓库，备忘录浮窗） | **不能用**。它靠 macOS 的 launchd + osascript 读 Mac 版备忘录，手机上没有对应接口 |

手机上直接开本地 html 文件很别扭，最省事的办法是把它放到网上：开启 GitHub Pages 后手机打开
`https://ree-29lab.github.io/docx-word-count/docxcount.html` 即可（页面本身不联网、不上传文件）。

## 二、macOS：选中就自动出数（浮窗）

装完之后会有一个常驻小面板：**在任何一个 app 里选中文字，右下角立刻跳出这段的字数**，不用右键、不用按键。

```
选中: 中 25字 英 10词 | 共 35
字符数 66（不计空格）／75（含空格）
```

第一次使用要给一次权限（只给一次，之后永久）：

1. 打开 **系统设置 › 隐私与安全性 › 辅助功能**
2. 在列表里找到 **SelectionCount**，把开关打开
3. 列表里没有它，就点 `+`，选 `~/Applications/SelectionCount.app`

**为什么必须要这个权限**：读「当前选中的文字」只有辅助功能接口能做。它不读剪贴板、不记录、不联网，选中什么只算数不保存。不想要就 `bash uninstall.sh`，或直接在系统设置里把开关关掉。

那个面板的名字叫 SelectionCount，装在 `~/Applications/SelectionCount.app`，由 `~/Library/LaunchAgents/com.docxwordcount.selectionpanel.plist` 开机自启。判断它有没有拿到权限：

```bash
~/Applications/SelectionCount.app/Contents/MacOS/SelectionCount --check-access
```

## 三、macOS：装成右键菜单（可选）

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
| 英文字母、数字、组合符连成的串 | 整串算 **1 个词**（`don't`、`2026` 都算 1） |
| 词内连字符、撇号、下划线 | **不断词**：`state-of-the-art` = 1，`well-known e-mail` = 2 |
| 数字里的分隔符 | **不断词**：`1,000` = 1，`3.14` = 1 |
| 带重音的字母 | 算词的一部分：`café` = 1 |
| 空格、Tab、换行、标点 | 不算字数，只作分隔 |
| 修订中**被删除**的文字 | **不算** |
| 域代码（页码、目录域） | **不算** |
| 页眉、页脚、脚注、尾注 | **默认算**，勾「只数正文」/ `--body-only` 排除 |
| 批注 | 不算 |
| 文本框 | 算 |
| 图片、图表里的文字 | 不算（图片不是文本） |

**字数 = 中文字符 + 英文单词**，就是平时说的「字数」。

### 为什么「字数」和「字符数」差几百？

字数不数标点，字符数把标点也算进去。拿 `合欢树` 举例：

| 项 | 数 |
|---|---|
| 汉字 | 1643 |
| 标点 | 236（`，`×121 `。`×70 `“`×12 `”`×12 `？`×7 `：`×6 `！`×4 `、`×3 `；`×1） |
| 空格 | 3 |
| 字数 | **1643**（只数汉字） |
| 字符数（不计空格） | **1879**（汉字 + 标点） |
| 字符数（含空格） | **1882** |

所以差的那两百多，全是标点。Word 的「字数」同样不含标点，口径一致。想自己拆开看：

```bash
node tools/explain.cjs 报告.docx
```

这一套就是 Word / WPS 「字数统计」的通行口径：英文按词、中文按字、连字符词不断开。

**未核的部分（如实说）**：我没能在本机拿 Word 的数字逐串比对——Word 的自动化权限被 macOS 拒了（`-10004`）。所以这里是按通行规则实现，行为由 `tests/cases.json` 锁住，不是逐条对着 Word 抄的。唯一已知可能差一处的：Word 的「字符数（不计空格）」对段落标记的算法，可能与我这里差个位数。

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
