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
scripts/04-run-simulator.sh          # 默认 "iPhone 16"，建不出来就自动用现有的 iPhone 模拟器；第二个参数可换
```

- `02-apply-patches.sh` 会在 `src` 里新建（或重置）分支 `ios-blink-sideload`，然后按 `patches/series` 依次 `git am --3way`。重跑会从固定版本重新打一遍。
- 第一次完整编译要几个小时，之后是增量编译。
- **16 GB 内存的 Mac 要限制并行数**：在 `scripts/config.local.sh` 写上 `: "${BUILD_JOBS=5}"`。默认按 CPU 核数（10 路），加上 siso 自己的约 2 GB，会把内存耗尽、机器卡死，编译反而慢几十倍（验证过）。
- 编译要跑几个小时，最好让它脱离启动它的终端或会话运行（比如用 `nohup`，或者在单独的终端窗口里跑），否则那边一关，编译就会被打断。重跑会从断点继续。
- 跳过 Chrome 的首次引导：`xcrun simctl spawn <udid> defaults write <bundle id> FirstRunForceDisabled -bool YES`，然后重启 app（验证过）。不开窗口也能用 `xcrun simctl io <udid> screenshot x.png` 截图。
- `04-run-simulator.sh` 用 `simctl launch --console-pty` 启动，app 的 stdout/stderr 直接显示在终端里。也可以用编译产物里的 `iossim`：`out/Release-iphonesimulator-blink/iossim -i out/Release-iphonesimulator-blink/Chromium.app`。

想确认补丁生效：日志里能看到 renderer、GPU 都是本进程里的线程，不会尝试启动扩展进程。

### 在模拟器里自动测试（AXe）

没有窗口也能测（验证过）：[AXe](https://github.com/cameroncooke/AXe) 用无障碍和 HID 接口操作模拟器，配合 `DEVELOPER_DIR` 就能用，不需要改 `xcode-select`。

```bash
brew tap cameroncooke/axe && brew trust --formula cameroncooke/axe/axe && brew install cameroncooke/axe/axe
```

- `axe describe-ui --udid <udid>`：读界面结构（带无障碍 id 和坐标）；`axe tap --id <id>` / `--label <文字>` / `-x -y`：点击；`axe type '<文字>'`：输入；`axe swipe`：滑动；`axe screenshot --output x.png`：截图。
- 打开网址最稳的办法：`xcrun simctl openurl <udid> 'chromium://example.com'`（`chromiums://` 是 https），然后 `axe tap --label '打开'` 点系统确认框。直接在地址栏里输入，容易被键盘的自动修正气泡挡住建议行。
- 模拟器里的 app 能直接访问 Mac 的 `localhost`，本地起个 `python3 -m http.server` 放测试页就行。
- 注意：AXe 会激活无障碍功能，可能触发只有开 VoiceOver 才会碰到的 bug（补丁 0007 就是这么发现的）。
- **iPhone 13 mini 模拟器上 AXe 的点击坐标偏大约 4%**：屏幕实际是 360×780 点的分辨率，iOS 却按 375×812 点排版，AXe 按前者换算，`axe tap -x 188 -y 704` 实际落在 (196, 733)，越靠下偏得越多。UIKit 坐标（`describe-ui` 给出的就是）要先乘 0.96 再交给 `axe tap`；从截图量的坐标（截图像素除以 3）不用换算（2026-10-27 用记录命中视图的调试版查明，点编辑菜单项时又确认过）。
- 网页里的文字不在 AXe 读到的界面结构里，要看网页状态就截图，或者让测试页把要看的数据画在页面顶部。
- 查 Chrome 网页脚本的问题：Blink 版所有注入脚本都跑在网页自己的 JS 环境里，测试页可以直接检查 `window.__gCrWeb`，还能包一层 `__gCrWeb.callFunctionInGcrWeb`（原生调网页）和 `window.webkitMessageHandler.postMessage`（网页发给原生）把往来记下来（补丁 0008 的翻译问题就是这么查的）。
- 查触摸和滚动：测试页监听 `touchstart`/`touchmove`/`touchend`/`touchcancel` 和 `scroll`，把计数和 `scrollY` 画在固定的浮层里，再用 `axe swipe --duration 1 --delta 4` 慢拖、`--duration 0.15` 快划（补丁 0011 就是这么查出来的）。
- 长按：`axe touch -x <x> -y <y> --down --up --delay 1.2`；组合键：`axe key-combo --modifiers 227 --key 6`（Cmd+C；227 是左 Command，225 是左 Shift，字母键码 a=4…z=29，回车是 `axe key 40`）。中文输入法开着时，在地址栏输完网址要按两次回车（第一次只是上屏）。
- 测屏幕键盘：AXe 的 `type`/`key` 发的是实体键盘事件，用过之后模拟器就认为接着实体键盘，屏幕键盘不再弹出。要测屏幕键盘，先 `xcrun simctl spawn <udid> defaults write com.apple.keyboard.preferences HardwareKeyboardLastSeen -bool NO`（再把 `AutomaticMinimizationEnabled` 也设成 NO），重启模拟器（`simctl shutdown` 再 `boot`），之后只用点击，按屏幕键盘上的键打字（键的位置从 `describe-ui` 读）。打开网页用 `simctl openurl`，不要在地址栏里用 `axe type`（补丁 0017 就是这么测的）。
- 查下载：下好的文件在 `xcrun simctl get_app_container <udid> <bundle id> data` 下的 `Documents/`，下载中的临时文件在同一目录的 `tmp/downloads/<UUID>/*.crdownload`。测"下载中途"要一个慢的服务器，本地写个每 0.2 秒发 20 KB 的 HTTP 服务就行，它还能记下对方是否中途断开（补丁 0013 就是这么测的）。
- 查 UIKit 和 BrowserEngineKit 的内部状态：用 lldb 附加到模拟器里的 app，不用重编（补丁 0019 就是这么查的）。`xcrun lldb --batch -o "process attach --pid $(pgrep -f Chromium.app/Chromium)" -o 'expr -l objc -O -- (id)[[[[[[UIApplication sharedApplication] connectedScenes] anyObject] windows] firstObject] recursiveDescription]' -o detach` 打印视图层级；`[对象 _ivarDescription]` 打印私有成员；也能直接调方法看结果（返回结构体的要先 `expr -l objc -- @import UIKit`）。附加期间 app 是暂停的，`detach` 后继续。Release 版里打断点不好用：链接器把代码相同的函数合并了，按名字设的断点会命中一堆无关函数，还把 app 拖得很慢。
- 看系统调了自己的哪些方法：给自己写的 Objective-C 方法下断点（这类方法代码各不相同，不会被合并），断点挂 Python 回调，把参数和调用栈写进文件后接着运行（`breakpoint command add -F 模块.函数`），app 不用停下来（补丁 0022 就是这么看出系统查找栏每次搜索后会自己调一次"下一个"的）。回调里第一次求值（`frame.EvaluateExpression`）要等几十秒。
- 对比颜色：`axe screenshot` 截图后直接读 PNG 的像素取色，和 Safari 同一页面、同一位置比（补丁 0023 就是这么对的选区、拖柄和光标颜色）。截图里的颜色和 UIKit 的取值差几个单位，比如系统蓝 `#0088FF` 截出来是 (0, 139, 255)，所以要两边都截图比，不要拿截图去比设计值。
- 测键盘时测试页要同时监听 `scroll` 和 `visualViewport` 的 `resize`、`scroll`：键盘出现后滚动的是可视视口，`window` 不会收到 `scroll`（补丁 0020 测试时漏了这一点，误以为没滚动）。
- 测网站权限：测试页把结果用 `fetch('/log?m=…')` 发回本地服务器，服务器把它打印出来，不用截图就能读结果（补丁 0026 就是这么测的）。定位先用 `xcrun simctl location <udid> set 31.2304,121.4737` 设一个模拟位置；iOS 的系统提示（定位、粘贴）也能按文字点（`describe-ui` 里有）。模拟器没有摄像头，content 找不到设备时直接报 `NotFoundError`、不会来问权限；启动时加 `--use-fake-device-for-media-stream`（`xcrun simctl launch <udid> <bundle id> --use-fake-device-for-media-stream`）就有一个虚拟摄像头。
- 切换深色/浅色：`xcrun simctl ui <udid> appearance dark`（或 `light`），网页开着也会立刻收到变化。
- 模拟器里的 Chromium 走 Mac 的系统代理（补丁 0009），系统代理开着就能打开 Google；需要对照时，`xcrun simctl openurl` 打开 http(s) 网址会用模拟器里的 Safari。

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
| 编译时机器卡顿、一大堆 `python3` 进程、内存几乎用光（遇到过） | Blink 的 `generate_bindings.py` 每次调用会按 CPU 核数开 `multiprocessing` 进程，几个这样的步骤同时跑，就是几十个各占 100–200 MB 的进程。这个阶段只在完整编译时出现一次；配合 `BUILD_JOBS=5`，16 GB 的机器撑得住 |
| `gn gen` 报 `Assignment had no effect`，指向 `ios/chrome/app/BUILD.gn` 的 `_extension_toolchain`（遇到过） | 扩展全关时上游 GN 会报这个错，补丁 0004 修的就是它；确认 0004 已经打上 |
| Chrome 在模拟器里启动约 1 秒就崩，日志是 `simple_watcher.cc` 的 DCHECK `RunsTasksInCurrentSequence()`，栈里有 `network::URLLoader` 和 `BrowserProcessIOThread`（遇到过） | 单进程下 `NetTaskScheduler` 造成的线程错配（见 architecture.md 的 0001 一节）。确认 0001 里有 `--disable-features=…NetTaskScheduler` |
| 创建模拟器报 `Incompatible device`（遇到过） | 当前模拟器运行时不支持这个机型（本机 iOS 27.1 运行时只支持 "iPhone Duo"）。`xcrun simctl list runtimes -j` 里的 `supportedDeviceTypes` 列出了可用机型；`04-run-simulator.sh` 会自动改用现有的 iPhone 模拟器 |
| `Unable to find application named 'Simulator'`（遇到过） | Xcode 27 不再带 Simulator.app，模拟器窗口换成了 `Xcode.app/Contents/Applications/DeviceHub.app`。`04-run-simulator.sh` 现在会按路径打开它。不开窗口也不影响运行，可以用 `xcrun simctl io booted screenshot x.png` 截图 |
| `gclient sync` 报 `git-lfs: command not found`（遇到过，在 `third_party/litert/src`） | 全局 git 配置里有 `git lfs install` 留下的"必需"过滤器，但没装 git-lfs。`scripts/config.sh` 已经让脚本里的 git 把 LFS 文件检出成指针，跟官方构建机一样（LiteRT 里的 LFS 文件是用不到的预编译库）。在终端里手动跑 `gclient` 前，先 `source scripts/config.sh` |

## 7. 修改补丁

1. 在 `~/chromium/src` 的 `ios-blink-sideload` 分支上直接改代码、编译、测试。
2. 修改完提交到对应补丁的 commit（`git commit --fixup` 加 `git rebase -i --autosquash`，或新开一个 commit 作为新补丁）。
3. 导出：`git format-patch --zero-commit --no-numbered --no-stat --full-index 4558926c..HEAD -o /tmp/new-patches`（这组选项让没改过的补丁导出后逐字节不变；早期手写的 0002、0003 例外，格式不同、内容等价，别替换），把改过的补丁覆盖到本仓库的 `patches/`（保持文件名和编号），需要时更新 `patches/series`。V8 的补丁（`patches/v8/`）在 `src/v8` 的同名分支上改，基准是 `src/DEPS` 里的 `v8_revision`（现在是 `f7be3c62`）：`git -C src/v8 format-patch --zero-commit --no-numbered --no-stat --full-index f7be3c62..HEAD -o /tmp/new-v8-patches`，文件名按 `v8/0201-…` 起。
4. 重跑 `scripts/02-apply-patches.sh` 确认能从头打上。只想核对 `patches/` 和分支是否一致时，也可以不碰工作区（重置分支会刷新补丁涉及文件的时间戳，引起不少重编）：设一个临时的 `GIT_INDEX_FILE`，`git read-tree 4558926c` 后按 `series` 依次 `git apply --cached`，再比较 `git write-tree` 和 `git rev-parse 'ios-blink-sideload^{tree}'`。
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
