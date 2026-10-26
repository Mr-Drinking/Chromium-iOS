# 在 Mac 上编译、运行和侧载

脚本都在 `scripts/`，共享设置在 `scripts/config.sh`，所有设置都能用环境变量覆盖，例如把源码放到外置盘：

```bash
export CHROMIUM_DIR=/Volumes/Build/chromium
export BUNDLE_ID_PREFIX=com.yourname.iosblink   # 换成你自己的反向域名
```

本机固定不变的设置可以写进 `scripts/config.local.sh`（不进 git，`config.sh` 会自动读取），省得每次都 export。写成 `: "${CHROMIUM_DIR:=/Volumes/Build/chromium}"` 这种形式，环境变量仍然优先。

## 0. 准备

- Apple 芯片的 Mac，建议 32 GB 内存（16 GB 也能编，但慢）；约 200 GB 可用磁盘。
- Xcode：固定版本要求 **Xcode 26 或更新**；官方 CI 用的是 Xcode 27（27a266a），跟 iOS 27 的手机最配，推荐 Xcode 27。装好后执行：
  ```bash
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
  ```
  在 Xcode › Settings › Components 里装上 iOS 模拟器运行时。
- 不想改系统的 `xcode-select`（比如 Xcode 放在外置盘，系统保持 Command Line Tools）：跑脚本前 `export DEVELOPER_DIR=<Xcode.app 的路径>/Contents/Developer`。`xcode-select -p`、`xcodebuild`、`xcrun` 都认这个变量（验证过）；Chromium 构建的每一步是否都继承它还没验证（`docs/status.md` 第 11 条）。
- 检查环境：
  ```bash
  scripts/00-check-env.sh
  ```

## 1. 拉源码

```bash
scripts/01-fetch-chromium.sh
```

- 会在 `~/depot_tools` 装 depot_tools（已有就跳过），在 `~/chromium` 写好只针对 iOS 的 `.gclient`（这两个是默认位置），然后浅克隆固定版本（`scripts/config.sh` 里的 `CHROMIUM_REV`）并运行 hooks。
- 第一次要下载几十 GB，耗时取决于网速。googlesource 支持按提交号浅克隆（2026-10-27 验证过）。同步失败时脚本直接报错退出，重跑会接着上次的进度同步；不会自动改用完整历史，因为那要多下几十 GB，而失败原因多半跟历史无关。确实需要完整历史时用 `FULL_HISTORY=1 scripts/01-fetch-chromium.sh`。
- 结束时会校验 `src` 确实停在固定版本。

## 2. 基线（可选，推荐）

先编未打补丁的 `content_shell`，确认工具链和源码没问题：

```bash
scripts/03-build.sh sim content_shell
scripts/04-run-simulator.sh content_shell
```

官方 CI 每天在 iOS 27 模拟器上跑基于 content_shell 的测试，这一步理论上应该能成功。如果这里就失败，问题在环境，不在补丁。

注意：`args/` 关掉了 Chrome 的全部 app 扩展，不打补丁 0004 的话，`gn gen` 就会报错（验证过）。要做"代码不打补丁"的基线，先只打 0004（`git -C <src> am --3way patches/0004-*.patch`），它只改 GN，不改运行时代码。

## 3. 打补丁，模拟器里跑 Chrome

```bash
scripts/02-apply-patches.sh          # 加 --with-optional 会连可选补丁一起打
scripts/03-build.sh sim              # 默认目标就是 chrome，产物 Chromium.app
scripts/04-run-simulator.sh          # 默认 "iPhone 16" 模拟器，第二个参数可换
```

- `02-apply-patches.sh` 会在 `src` 里新建（或重置）分支 `ios-blink-sideload`，然后按 `patches/series` 依次 `git am --3way`。重跑会从固定版本重新打一遍。
- 第一次完整编译要几个小时，之后是增量编译。
- `04-run-simulator.sh` 用 `simctl launch --console-pty` 启动，app 的 stdout/stderr 直接显示在终端里。也可以用编译产物里的 `iossim`：`out/Release-iphonesimulator-blink/iossim -i out/Release-iphonesimulator-blink/Chromium.app`。

想确认补丁生效：日志里能看到 renderer、GPU 都是本进程里的线程，不会尝试启动扩展进程。

## 4. 真机

```bash
scripts/03-build.sh device
scripts/05-package-ipa.sh            # → dist/Chromium-158.0.8127.0-sideload.ipa
```

产物未签名（如需让侧载工具开通 Chrome 的两个应用组，加 `--with-app-groups`，见第 6 节）。安装方式三选一：

- **Sideloadly**（电脑端，最简单）：用 USB 或 Wi-Fi 连手机，拖入 IPA，填 Apple ID。
- **AltStore**（电脑上跑 AltServer）：在手机 AltStore 里选 IPA 安装。
- **SideStore**（手机端自签，需要配对文件和 LocalDevVPN 一类的回环 VPN）。

注意：

- 手机要打开**开发者模式**（设置 › 隐私与安全性 › 开发者模式）；第一次运行还要在 设置 › 通用 › VPN 与设备管理 里信任你的开发者证书。
- 免费 Apple ID 签的 app **每 7 天过期**，需要重签；同时最多 3 个侧载 app。付费开发者账号是 1 年。
- 各工具对 iOS 27 的支持以它们当时的说明为准。
- 也可以完全不用侧载工具，自己用 `codesign` 加描述文件签名，再用 `xcrun devicectl device install app` 安装，但需要先在 Xcode 里给同一个 bundle id 生成描述文件，步骤繁琐，先不推荐。

## 5. 看日志和崩溃

- **模拟器**：`04-run-simulator.sh` 的终端输出；或 Console.app 里选模拟器。
- **真机**：
  - Console.app 选中手机，按进程名 `Chromium` 过滤。
  - 崩溃报告：手机 设置 › 隐私与安全性 › 分析与改进 › 分析数据，找 `Chromium-*.ips`；或在 Xcode › Window › Devices and Simulators › View Device Logs 里导出。
  - 用开发证书签名的包（免费 Apple ID 的就是），可以试 `xcrun devicectl device process launch --console --device <UDID> <bundle id>` 直接看 stdout/stderr。
- 把日志或 `.ips` 交给 Claude 定位问题时，带上你当时做了什么操作。

## 6. 常见问题（预判，未经验证）

| 现象 | 先怀疑 |
|---|---|
| 编译错误，报某个函数/常量不存在 | 补丁里的 API 在 158 改名了（已遇到过两次），对照该版本源码改补丁 |
| 模拟器里 Chrome 界面出来了，网页区域白屏或黑屏 | 0002 的图层挂接没生效：确认 `attachContentLayer:` 被调用、视图 handle 能查到 provider |
| 启动即崩、日志里有 GL/EGL/ANGLE 错误 | Metal 设备没拿到；看 0003 打印的 "No Metal device" 日志，可临时打 `optional/0101` 看完整报错 |
| 启动即崩、日志里有地址空间预留失败（mmap / reserve） | 地址空间不够，参考 `docs/patch-triage.md` 的 memory 类 |
| 能打开网页但没法打字 | BrowserEngineKit 文本输入在无权限时不工作（status.md 第 4 条） |
| 用一会儿被系统杀掉 | jetsam 内存上限：调低 0001 里的堆和 GPU 内存参数，少开标签页 |
| 视频黑屏 | 原生视频层；0001 已默认关闭 `avfoundation-overlays`，若仍黑屏需移植 `ca_renderer_layer_tree.mm` 的修复 |
| 启动时崩在 app group / 共享容器相关代码 | 未签名的包不带权限声明，侧载工具没开通应用组：用 `scripts/05-package-ipa.sh --with-app-groups` 重新打包再装 |
| `gn gen` 报 `Assignment had no effect`，指向 `ios/chrome/app/BUILD.gn` 的 `_extension_toolchain`（遇到过） | 扩展全关时上游 GN 会报这个错，补丁 0004 修的就是它；确认 0004 已经打上 |
| `gclient sync` 报 `git-lfs: command not found`（遇到过，在 `third_party/litert/src`） | 全局 git 配置里有 `git lfs install` 留下的"必需"过滤器，但没装 git-lfs。`scripts/config.sh` 已经让脚本里的 git 把 LFS 文件检出成指针，跟官方构建机一样（LiteRT 里的 LFS 文件是用不到的预编译库）。在终端里手动跑 `gclient` 前，先 `source scripts/config.sh` |

## 7. 修改补丁

1. 在 `~/chromium/src` 的 `ios-blink-sideload` 分支上直接改代码、编译、测试。
2. 修改完提交到对应补丁的 commit（`git commit --fixup` 加 `git rebase -i --autosquash`，或新开一个 commit 作为新补丁）。
3. 导出：`git format-patch 4558926c..HEAD -o /tmp/new-patches`，把结果覆盖到本仓库的 `patches/`（保持文件名和编号），需要时更新 `patches/series`。
4. 重跑 `scripts/02-apply-patches.sh` 确认能从头打上。
5. 更新 `docs/status.md`，提交本仓库。

补丁正文里统一用 `[ios-blink-sideload]` 标注改动，方便 `git grep` 找到。

## 8. 升级 Chromium 版本

1. 选一个官方 iOS Blink CI 通过的新提交：
   ```bash
   curl -sS -X POST 'https://cr-buildbucket.appspot.com/prpc/buildbucket.v2.Builds/SearchBuilds' \
     -H 'Content-Type: application/json' -H 'Accept: application/json' \
     -d '{"predicate":{"builder":{"project":"chromium","bucket":"ci","builder":"ios-blink-rel-fyi"},"status":"SUCCESS"},"pageSize":1,"fields":"builds.*.input.gitilesCommit"}' | tail -c +5
   ```
2. 改 `scripts/config.sh` 里的 `CHROMIUM_REV` 和 `CHROMIUM_VERSION`。
3. `scripts/01-fetch-chromium.sh`，再 `scripts/02-apply-patches.sh`；有冲突就解决，然后按第 7 节重新导出补丁。
4. 同步更新 `args/` 里的参数（新版本可能改名或新增开关）和 `docs/status.md` 的固定版本表。
5. 用 `git grep` 搜旧版本的短哈希和版本号，把 `CLAUDE.md`、`README.md`、本文件等处写死的引用一起改掉。

还没拉源码时，可以先不下载就检查补丁：对比新旧版本里补丁涉及文件的 blob ID（gitiles 目录的 `?format=JSON`）；有变化的，在只放这些文件的临时 git 仓库里先提交旧版、再提交新版，然后 `git am --3way` 试打。2026-10-26 那次升级就是这样做的。

## 9. 以后的方向

- **JIT**：iOS 26 起 A15 及更新机型需要 app 自己适配 StikDebug 的 JIT 脚本协议，Blinker Fluid 的 V8 "RX 映射 + RW 镜像" 改动可作参考（patch-triage.md 的 jit 类）。工作量大，放最后。
- **瘦身**：参考 tvOS 配置开 `v8_enable_lite_mode`、关 `v8_enable_turbofan`。
