# CLAUDE.md

## 项目

用官方 Chromium 源码编出"Chrome iOS 原生界面 + Blink 内核"的浏览器，侧载到用户的 iPhone 上。仓库里是补丁、构建脚本和文档；Chromium 源码本身在仓库外（默认 `~/chromium/src`，用户的 Mac 上放在外置盘 `/Volumes/Chromium-iOS/chromium/src`，见 `scripts/config.local.sh`）。

**当前状态：补丁、脚本、文档是在一个没有 Mac 的云端会话里写的；2026-10-26 开始在用户的 Mac 上实际执行，进度和已验证的结论以 `docs/status.md` 为准。**

## 用户与设备

- 用中文交流。
- 手机：iPhone 13 mini（A15，4 GB 内存），**iOS 27**。
- Mac：MacBook Air（M5，16 GB）。Xcode 27.1 在外置盘上；系统的 `xcode-select` 有意保持 Command Line Tools，**不要改**，脚本通过 `scripts/config.local.sh` 里的 `DEVELOPER_DIR` 用外置盘的 Xcode。网络走本地代理。编译并行数设成 5（`config.local.sh` 里的 `BUILD_JOBS`）：默认的 10 路会把 16 GB 内存耗尽，机器卡死。长时间的编译要脱离会话运行（`setsid`），否则会话一退出就会被连带打断。
- 想要 Chrome iOS 的原生界面；明确不想要 Blinker Fluid 那种自绘界面。

## 已定决策（除非用户提出，不要推翻或重新讨论）

1. **编 `chrome` 目标（Chrome iOS 界面），`use_blink = true`。** Android 界面在 iOS 上跑不了；不在 content_shell 上自己画界面。
2. **固定在 Chromium `3313f827`（159.0.8129.0）**，这是官方 iOS Blink CI（`ios-blink-rel-fyi`）2026-10-28 编译通过的 main 提交（测试只挂了 5 个和 Blink 无关的 Autofill 单测，见 `scripts/config.sh`）。2026-10-29 应用户要求从 `4558926c`/158.0.8127.0 升上来，更早是 `d586be9f`/158.0.8125.0。升级前先问用户（流程见 `docs/build-guide.md` 第 8 节）。
3. **单进程 + V8 免 JIT。** 侧载拿不到 BrowserEngineKit 权限，这是唯一可行的形态（照搬官方 tvOS 的做法）。JIT 放到最后。
4. **侧载安装**（Sideloadly / AltStore / SideStore）。iOS 27 没有 TrollStore。
5. **Blinker Fluid 只作参考。** 不把它的 GPL-3.0 代码放进本仓库；需要时用 `tools/blinker_rebase.py` 现拉现合，只提取语义改动，重写成 `patches/` 里的最小补丁。

## 先读

1. `docs/status.md`：进度和待验证的假设。开始工作前读，结束前更新。
2. `docs/build-guide.md`：每一步的命令、看日志的方法、常见问题。
3. `docs/architecture.md`：Chrome iOS 怎么接到 Blink，以及每个补丁为什么这样改。
4. `docs/patch-triage.md`：遇到内存、视频、输入、JIT 问题时，去这里找 Blinker Fluid 的对应改动。

## 工作方式

- 按 `docs/status.md` 的阶段推进：环境 → 模拟器里跑 Chrome → 真机 → 补强。先在模拟器里把问题解决掉，再上真机。
- **编译报错先查 API 漂移。** 补丁最早是对着 158 的源码手写的，升级 Chromium 后可能碰上接口改动。已经踩过两次：物理内存接口改成了 `base::SysInfo::AmountOfTotalPhysicalMemory().InMiB()`；`kJavaScriptFlags` 挪到了 `blink::switches`，所以补丁里直接写 `"js-flags"`。在 Chromium 的 `src` 里 `git grep` 确认，不要凭记忆。
- **改补丁的流程**（`docs/build-guide.md` 第 7 节）：在 `src` 的 `ios-blink-sideload` 分支上改并提交 → `git format-patch --zero-commit --no-numbered --no-stat --full-index 3313f827..HEAD` → 覆盖 `patches/` 里对应文件 → 重跑 `scripts/02-apply-patches.sh` 验证 → 更新 `docs/status.md` → 提交本仓库。现在没有 V8 补丁（158 上用过的 0201 在 159 上不需要了，上游已修）；以后要改 V8，补丁放 `patches/v8/`，在 `src/v8` 的同名分支上改，基准是 `src/DEPS` 里的 `v8_revision`（现在是 `0388bc74`）。
- 代码改动统一加 `[ios-blink-sideload]` 注释；补丁只放语义改动，不夹带格式化。
- `gclient sync`、首次编译要几十分钟到几小时，放后台跑，并告诉用户大概要等多久。
- 写进文档的结论要标明是"验证过"还是"推测"。
- 不要提交 Chromium 源码、`out/`、`dist/`、IPA（`.gitignore` 已覆盖）。

## 命令速查

```bash
scripts/00-check-env.sh                 # 环境检查（只读）
scripts/01-fetch-chromium.sh            # 拉/同步源码到固定版本
scripts/02-apply-patches.sh             # 重置分支 ios-blink-sideload 并打补丁（--with-optional 连可选的一起）
scripts/03-build.sh sim [targets]       # 模拟器构建，默认目标 chrome；content_shell 可作基线
scripts/04-run-simulator.sh [app] [设备名]  # 安装并启动，终端里看 stdout/stderr
scripts/03-build.sh device              # 真机构建（未签名）
scripts/05-package-ipa.sh               # 打包成 dist/*.ipa（--with-app-groups：临时签名写入应用组声明）
python3 tools/blinker_rebase.py --target-src ~/chromium/src --files <路径>   # 参考 Blinker 的改动
```

设置在 `scripts/config.sh`，都能用环境变量覆盖（`CHROMIUM_DIR`、`BUNDLE_ID_PREFIX` 等）。本机的路径写在不进 git 的 `scripts/config.local.sh`，所有脚本会自动读取。

## 下一步

看 `docs/status.md` 的阶段和日志，从第一个没打勾的步骤接着做。
