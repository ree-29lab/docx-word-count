# docx-word-count

Count characters and words on macOS — either **a whole `.docx` file** (no matter which application produced it: Word, Pages export, WPS, Google Docs download) or **just the text you selected in any app**. Three ways: right-click a file in Finder, select text and use the Services menu, or run one command in the terminal.

Counting rules match the way Chinese and English are usually budgeted for: **every CJK character counts one**, **every run of Latin letters, digits or apostrophes counts one word**.

## 用法

### 1. Finder 右键

在 Finder 里选中一个（或多个）`.docx` › 右键 › **快速操作** › **统计字数**，结果用弹窗显示：

```
报告.docx
  中文字符   1643    英文单词     0
  字数       1643    字符数(不计空格)   1880
  字符数(含空格)   1881
```

### 2. 选中一段文字

在任何 app 里选中一段文字（Word、Pages、备忘录、Safari、TextEdit 都行）› 右键 › **服务** › **统计选中字数**，只数你选中的那部分：

```
中文字符    309    英文单词    12
字数        321    字符数(不计空格)    338
```

这样就能回答「这一段够不够 350 词」这类问题，不用把整篇文档算一遍。想更快：系统设置 › 键盘 › 键盘快捷键 › **服务** › 给「统计选中字数」配一个快捷键（比如 `⌃⌥W`）。

### 3. 终端

```bash
docxcount 报告.docx                  # 单个文件，分行明细
docxcount ~/Desktop/*.docx           # 多个文件，末尾给合计
docxcount --body-only 报告.docx      # 只数正文，不含页眉页脚、脚注尾注
docxcount --json 报告.docx           # 给脚本用

pbpaste | docxcount --stdin          # 数剪贴板里的文字
docxcount --text "随便一段文字"        # 直接数一段话
```

## 安装

```bash
git clone https://github.com/ree-29lab/docx-word-count.git
cd docx-word-count
bash install.sh
```

或者下载仓库后双击 `install.command`。`bash install.sh --dry-run` 只打印要做的事，不写任何文件。

安装会放三处东西：

| 位置 | 是什么 |
|---|---|
| `~/Library/Application Support/DocxWordCount/` | 程序本体 |
| `~/Library/Services/DocxWordCount.workflow` | Finder 的「统计字数」快速操作（整篇） |
| `~/Library/Services/CountSelection.workflow` | 「服务」菜单里的「统计选中字数」（选中部分） |
| `/usr/local/bin/docxcount`（不可写时退到 `~/bin`） | 终端命令 |

只需要系统自带的 `osascript` 与 `unzip`，不需要 Node、Python、Homebrew。

## 计数口径

| 内容 | 怎么算 |
|---|---|
| 中文、日文假名、韩文 | 每个字 **1** |
| 英文字母、数字、`'` 连成的串 | 整串算 **1 个词**（`don't`、`2026` 都算 1） |
| 空格、Tab、换行、标点 | 不算字数，只作分隔 |
| 修订中**被删除**的文字 | **不算**（`w:delText` 直接跳过） |
| 域代码（页码、目录域） | **不算** |
| 页眉、页脚、脚注、尾注 | **默认算**，加 `--body-only` 排除 |
| 批注 | 不算 |
| 文本框 | 算（Word 把它的文字也放在 `w:p` 里） |
| 图片、图表里的文字 | 不算（图片不是文本，图表另存为嵌入的表格时会算） |

**字数 = 中文字符 + 英文单词**，这一列就是平时说的「字数」。

与 Word 自带「字数统计」的已知差异（**推断，未在 Word 上逐篇核对**）：

- 连字符词 `state-of-the-art`：这里按 3 个词，Word 算 1 个。
- 「字符数」按文本字符数算，Word 的「字符数（不计空格）」是否含段落标记口径略有出入，可能差个位数字。

## 支持的格式

只吃 **`.docx`**。这些要先另存为 docx：

- `.doc`（旧二进制格式）
- `.pages`（内部是另一套 protobuf）
- `.pdf`

## 卸载

```bash
bash uninstall.sh
```

## 排错

| 现象 | 处理 |
|---|---|
| 右键菜单里没有「统计字数」 | 先确认选中的是 `.docx`；执行 `killall Finder` 刷新菜单；菜单在「快速操作」子菜单里，可能被折叠到「更多…」 |
| 右键菜单里没有「统计选中字数」 | 先确认选中的是文字（不是图片）；不同 app 叫法不同：Finder 里是「快速操作」，Word / Pages / Safari / TextEdit 里是「服务」，有的 app 需要点「服务 › 更多…」；实在没有就给它在 系统设置 › 键盘 › 键盘快捷键 › 服务 里配个快捷键，配好的快捷键不依赖右键菜单 |
| 选中字数的结果和整篇对不上 | 预期如此：选中只数你选中的文字；把整篇全选再数，应该和文件的 `--body-only` 结果一致 |
| 终端说 `command not found: docxcount` | 安装时 `/usr/local/bin` 不可写，装到了 `~/bin`，把那行 `export PATH` 加进 `~/.zshrc` |
| 弹窗说「找不到已安装的程序」 | 快速操作还在但程序被删了：重新 `bash install.sh` |
| 数字明显偏小 | 可能这篇文档用的是文本框之外的对象（图片、公式、SmartArt），这些不是文本；用 `docxcount --json` 看 `parts` 里读了哪些部件 |

## 开发

主程序是 macOS 的 JavaScript for Automation（`src/wordcount.js`），用 `unzip` 取出 `word/*.xml`，再用 `NSXMLDocument` 遍历节点拼回纯文本：

- `w:t` → 文字
- `w:tab` → 空格，`w:br` / `w:cr` → 换行，段落结束 → 换行（词不会因此粘连）
- `w:del` 子树、`w:instrText`、`w:delText` → 整块跳过

跑测试（会现造 7 份 docx 覆盖换行、拆 run、修订删除、域代码、页眉等情形，另加选中文字模式）：

```bash
bash tests/run.sh
```

选中文字模式（服务用的就是这条管道）：

```bash
printf '你好 world' | ./bin/docxcount --stdin --json
```

只看计数逻辑、不碰文件：

```bash
./bin/docxcount --selftest
```

## 授权

MIT，见 [LICENSE](LICENSE)。
