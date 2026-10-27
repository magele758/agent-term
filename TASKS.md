# agent-term 任务清单

给接手的 Agent。先读「现状」，再按剩下的项做。每项写了改哪个文件、做到什么算完。

## 现状（已完成，不要重做）

- 原生 AppKit 终端，SwiftTerm v1.18.0（checkout 在 `/tmp/stprobe/repo`）。一个窗口，可嵌套分屏。分隔条可拖，比例限制在 0.15…0.85。
- 快捷键：`⌘D` 左右分屏，`⌘⇧D` 上下分屏，`⌘⌥方向键` 移动焦点，`⌘W` 关当前面板，`⌘,` 设置，`⌘K` 运行 Agent。这些项也在「窗口」菜单里，动作与 `handle()` 相同。
- 菜单栏：应用菜单（设置、退出）+ 窗口菜单 + Agent 菜单（运行 Agent）。`Sources/TermApp/main.swift` 的 `buildMenu()`。
- 设置窗口是 `NSScrollView`，保存按钮钉在滚动区外面。字段：字体、字号、前景/背景/光标色、透明度、Shell、环境变量、登录 shell、Option 作为 Meta、模型地址、模型名、API Key。
- `config.json` 只存 `modelBaseUrl` 和 `modelName`。API Key 在 Keychain，service `agent-term`，account `modelApiKey`。旧文件里的 `modelApiKey` 会在加载时迁走并改写文件。
- 外观：内置主题（默认、Nord、Dracula、Tokyo Night、Catppuccin、Solarized、Paper、辐射），设置里选等宽字体、行高、光标形状。`⌘=` / `⌘-` / `⌘0` 改字号，`⌘⇧P` 命令面板。缺字形回落到本机的 MesloLGS NF。可选 `~/.agent-term/theme.json` 和 `~/.agent-term/themes/*.json`。
- **辐射 CRT 已完成。** 主题名 `辐射`。磷光绿单色调色板，加上扫描线、隔行、玻璃反光、暗角、圆角管框、滚动刷新条、颗粒、闪烁/渐暗、横跳、开机闪。实现在 `Sources/TermApp/CRTOverlay.swift`，只在选中该主题时叠在面板上，不挡键盘。桶形弯曲和逐字光晕没做：要采样 Metal 帧，SwiftTerm 没交出纹理。
- Shell 以登录方式启动（`zsh -l`）。分屏时新面板继承当前面板的 cwd（`proc_pidinfo` / `PROC_PIDVNODEPATHINFO`，失败则用启动目录）。
- Agent：`agent/run.mjs` 调 `@ppeng/agent-loop` 的 **max** 档。父工具 `read_file`、`list_dir`、`spawn_agent`。子 Agent 另有 `run_shell`，不能再 `spawn_agent`。
- `EchoModel`：消息里已有 `role:'tool'` 就返回文本，不再派 `tool_call`。验收命令的 stderr 里 `spawn_agent` 只出现一次。
- `spawn_agent` 接受 `tasks: string[]`（仍接受单个 `task`），`Promise.all` 并发，结果按派发顺序以 `#0` / `#1` 拼回。`parallel-sleep` 两个 echo 子任务约 0.47s，不是两者之和。
- `run_shell` 把命令 stdin 交给 `.build-direct/headless/gate`（`Gate(rules: []).check`）。`deny` 不执行。`ask` 且没有 `AGENT_ASK_DIR` 时返回 `ask: no approver`，不执行。App 会建 ask 目录，主线程弹「允许 / 拒绝」，把 `allow` 或 `deny` 写进 `<uuid>.res`。
- `⌘K` 的回复在标题为 Agent 的面板里，不调用 `term.send`。
- 真实模型：用 `ppeng-agent-core/.env` 的 OpenAI 兼容端点跑 `读 README 并总结`，进程退出 0，stdout 是总结而不是报错。仓库没有 README，模型改读了 `PLAN.md` / `TASKS.md`。
- `swift build --target TermApp` 可用。先跑一次 `scripts/fix-swiftpm.sh`，它在 `~/.local/bin/swift` 前插一个编译器包装，把旧的 `SwiftVersion` 符号别名到 `SwiftLanguageMode`，并藏掉重复的 `SwiftBridging` modulemap。不要删 `scripts/build.sh`：裸 `swift build` 还会去编 SwiftTerm 带进来的 argument-parser 插件，那份插件源码在本机 Swift 6.1.2 上编不过；App 包和 Metal 仍走 `build.sh`。

## 编译与运行

`scripts/build.sh` 把 headless 模块放到 `.build-direct/headless/`，UI 模块放到 `.build-direct/ui/`，再把 UI 的 `SwiftTerm.swiftmodule` 和 `libSwiftTermUI.dylib` 复制到 `.build-direct/`。两边互不覆盖。脚本末尾会编 App、编 `gate`，并跑 TermCore 测试。

```bash
scripts/build.sh
DYLD_LIBRARY_PATH=.build-direct .build-direct/TermApp
```

只重链 App（UI 模块已经在 `.build-direct/` 时）：

```bash
SDK=$(xcrun --show-sdk-path)
xcrun swiftc -sdk "$SDK" -target arm64-apple-macosx14.0 \
  -vfsoverlay .build-direct/hide-bridging.yaml \
  -I .build-direct -L .build-direct -lSwiftTermUI \
  -emit-executable -o .build-direct/TermApp Sources/TermApp/main.swift
```

## 验证 Agent 接入

```bash
node agent/run.mjs echo echo "列出当前目录" "$PWD"
node agent/run.mjs echo echo parallel-sleep "$PWD"
```

`echo` 不需要 key。真实模型把前两个参数换成 baseUrl 和模型名，并设 `AGENT_API_KEY`。Key 不要写进 `config.json`。

## 剩下的

1. ~~**辐射 CRT 主题。**~~ 已完成，见上面「现状」。
2. ~~**SwiftPM 修复。**~~ manifest 链接已用 `scripts/fix-swiftpm.sh` 接上。`swift build --target TermApp` 能编过。裸 `swift build` 仍会编不兼容的 argument-parser 插件，所以 `scripts/build.sh` 先留着。

## 不要做

- 不要换掉 SwiftTerm，不要引入 Electron。
- 不要把 `@ppeng/agent-loop` 的代码复制进本仓库。它在 `../ppeng-agent-core/packages/agent-loop`，用 `AGENT_CORE` 指向它的 `dist/`。
- 不要给 Agent 无审批的写文件或联网能力。写操作和 shell 走 `Gate`。
