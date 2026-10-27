# iOS Blink Chromium（侧载版）

用官方 Chromium 源码编出"**Chrome iOS 原生界面 + Blink 内核**"的浏览器，侧载到没有越狱、也没有 Apple 浏览器引擎权限的 iPhone 上。目标设备：iPhone 13 mini（A15，4 GB 内存），iOS 27。

> **当前状态：补丁、脚本和文档已经写好，但还没有在 Mac 上编译验证过。**
> 补丁是对照固定版本的官方源码手写的，能用 `git am --3way` 干净打上，能不能编过、跑起来要在 Mac 上验证。进度见 [docs/status.md](docs/status.md)。

## 原理

- **界面来自官方**：Chromium 官方支持 `use_blink = true` 编 `chrome` 目标（官方文档 `docs/ios/build_instructions.md`）。Chrome iOS 的界面代码（`ios/chrome`）不直接调用 WebKit，而是通过 `ios/web` 接口；打开 `use_blink` 后这层接口换成 `ios/web/content` 实现，下面接的就是 Blink。界面一行不用改，就是现在 Chrome iOS 的样子（含 iOS 26 的 Liquid Glass 设计）。
- **难点在权限**：官方的 iOS Blink 默认多进程，靠 BrowserEngineKit 拉起渲染、GPU、网络扩展进程，需要 `com.apple.developer.web-browser-engine.host` 等权限。这些权限只有 Apple 批准的厂商才有，侧载签名拿不到。
- **本项目的做法**：照官方 tvOS 版 Blink 的方式改成单进程。补丁 0001 加 `--single-process` 和免 JIT 参数；补丁 0002 让 GPU 线程把渲染出的图层直接挂到网页视图上，不再走 BrowserEngineKit 的跨进程交接；补丁 0003 在 GPU 初始化前等 Metal 设备就绪。V8 走免 JIT 模式。原计划让 WebAssembly 走 DrumBrake 解释器，但它在当前 V8 上编不过，所以暂时没有 WebAssembly（见 `docs/status.md`）。
- 思路参考了社区项目 [Blinker Fluid](https://github.com/Nodesclock/Blinker-Fluid)（GPL-3.0）。本仓库**不收录**它的代码，核心补丁是按同样思路在新版 Chromium 上重写的最小改动。

## 目录

| 路径 | 内容 |
|---|---|
| `CLAUDE.md` | 给后续 Claude 会话的交接说明（背景、已定决策、工作流） |
| `docs/status.md` | 当前进度、待验证的假设、风险 |
| `docs/build-guide.md` | 在 Mac 上从零编译、跑模拟器、打包、侧载的完整步骤 |
| `docs/architecture.md` | Chrome iOS + Blink 的结构，以及每个补丁改了什么、为什么 |
| `docs/background.md` | 调研结论：社区项目现状、官方路线、iOS 限制（附来源） |
| `docs/patch-triage.md` | Blinker Fluid 所有引擎改动的逐文件分类，以及合并到 158 的结果 |
| `patches/` | 补丁系列（`series` 定义顺序；`optional/` 为可选补丁） |
| `args/` | GN 构建参数：`simulator.gn`、`device.gn` |
| `scripts/` | Mac 上用的脚本：环境检查 → 拉源码 → 打补丁 → 编译 → 模拟器 → 打包 IPA |
| `tools/blinker_rebase.py` | 把 Blinker Fluid 的某个改动三方合并到指定 Chromium 版本，供移植参考 |

## 快速开始（在 Mac 上）

固定版本：Chromium `4558926c`（158.0.8127.0，2026-10-26 官方 iOS Blink CI 通过的提交）。需要 Xcode 26 或更新（推荐 Xcode 27）、约 200 GB 磁盘。

```bash
scripts/00-check-env.sh                  # 检查 Xcode、磁盘、内存
scripts/01-fetch-chromium.sh             # 拉固定版本源码到 ~/chromium（几十 GB）
scripts/03-build.sh sim content_shell    # 可选：先编未打补丁的 content_shell 验证工具链
scripts/04-run-simulator.sh content_shell
scripts/02-apply-patches.sh              # 在 src 上建分支 ios-blink-sideload 并打补丁
scripts/03-build.sh sim                  # 编 Chrome（模拟器）
scripts/04-run-simulator.sh              # 装到模拟器并启动，终端里看日志
scripts/03-build.sh device               # 编真机版（未签名）
scripts/05-package-ipa.sh                # 生成 dist/Chromium-158.0.8127.0-sideload.ipa
```

IPA 用 Sideloadly、AltStore 或 SideStore 安装，手机需要打开开发者模式。细节和排错见 [docs/build-guide.md](docs/build-guide.md)。

## 许可

- `patches/` 下的补丁修改的是 Chromium（BSD 许可），新增文件沿用 Chromium 的 BSD 许可头。
- 核心补丁的思路，以及 `-attachContentLayer:` 这个方法名，来自 Blinker Fluid（GPL-3.0），代码是重写的。如果将来要公开分发编译产物，建议先评估这一点。
- `tools/blinker_rebase.py` 运行时才下载 Blinker Fluid 的文件，产物写在 `out/`，不进仓库。
