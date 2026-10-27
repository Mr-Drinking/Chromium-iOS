# 进度与待验证事项

最后更新：2026-10-27（Mac 上：**Chrome 模拟器版编译通过，在模拟器里能显示 Chrome 原生界面且不崩溃**；网页渲染还没验证，因为没法点屏幕；真机版正在后台编译，日志在 `/Volumes/Chromium-iOS/chromium/build-logs/`）。

**每完成一步、每确认或推翻一条假设，都更新这个文件。** 它是项目的唯一进度记录。

## 固定版本

| 项 | 值 | 依据 |
|---|---|---|
| Chromium | `4558926cce232609ce125114e633e0b3a67b793d`（158.0.8127.0，main@{#1726971}，2026-10-26） | 官方 `ios-blink-rel-fyi` CI 第 42241 次构建（ID 8666871797155972657）通过 |
| V8 | `f7be3c62b2a158365e646b8dd4ed8cb61c072cae` | 上面提交的 DEPS |
| ANGLE | `ab90d2a96dea191f14a96d4b2c16b5a50ee73317` | 同上 |
| CI 用的 Xcode | 27a266a（Xcode 27） | 该 builder 的 `properties.json` |
| CI 编译目标 | `all`（`use_blink=true`，模拟器 Release） | 该 builder 的 `targets/chromium.fyi.json` |
| CI 跑测试的模拟器 | iPhone 16 / iOS 27.0 | 同上 |
| 用 Blink 时的最低 iOS | 26.0（`build/config/ios/ios_sdk_overrides.gni`） | 源码 |
| Xcode 最低要求 | 26.0（`ios/build/chrome_build.gni` 里的 assert） | 源码 |

2026-10-26 应用户要求，从 `d586be9f`（158.0.8125.0，main@{#1726673}，CI 构建 ID 8666930859126518865）升到这里，中间相差 298 个提交。以下都验证过：这个 builder 的 `gn-args.json`、`properties.json`、`targets/chromium.fyi.json` 新旧两版完全一样；表里其余几行引用的源码文件也没变。补丁涉及的文件里，只有 `content/browser/renderer_host/render_widget_host_view_ios.{h,mm}` 变了（上游加了一个和补丁无关的 `ClearFocusedElement()`）。全部补丁（含可选的）在新版本的这些文件上用 `git am --3way` 都能干净打上。

## 本机环境（2026-10-26 验证过）

| 项 | 值 |
|---|---|
| Mac | MacBook Air（Mac17,3），Apple M5 10 核（4 性能 + 6 能效），16 GB 内存，macOS 27.2 |
| Xcode | 27.1（27A9275），在外置盘 `/Volumes/Chromium-iOS/Xcode.app`；iPhoneOS / iPhoneSimulator SDK 27.1；模拟器运行时 iOS 27.1；许可已接受，首次启动已完成 |
| 怎么选 Xcode | 系统 `xcode-select` 保持 Command Line Tools（用户有意为之，不要改）。脚本通过 `scripts/config.local.sh` 设 `DEVELOPER_DIR=/Volumes/Chromium-iOS/Xcode.app/Contents/Developer`；没有这个设置的话，`00-check-env.sh` 会报 FAIL |
| 源码位置 | 外置盘：`CHROMIUM_DIR=/Volumes/Chromium-iOS/chromium`，depot_tools 在 `/Volumes/Chromium-iOS/depot_tools`，都写在不进 git 的 `scripts/config.local.sh`。用户 2026-10-26 选的（已提醒外置盘经 hub 只有 5 Gb/s，会拖慢编译） |
| 磁盘 | 内置盘 215 GB 可用；外置盘 `Chromium-iOS` 219 GB 可用（USB，目前经 hub 只跑 5 Gb/s，Owners: Disabled；2026-10-27 起不再被 Spotlight 索引）。5 路并行编译时外置盘只有每秒几 MB 的读写，不是瓶颈（验证过） |
| 编译并行数 | `BUILD_JOBS=5`（写在 `scripts/config.local.sh`）。默认的 10 路会耗尽 16 GB 内存，见日志 2026-10-27 |
| 网络 | 走本地代理（环境变量 `HTTPS_PROXY` 和 git `http.proxy` 都已设置）；googlesource、GCS、CIPD 都能连通，固定提交在 googlesource 上查得到 |
| git 配置 | `~/.gitconfig` 里原来有 `git lfs install` 留下的 `filter.lfs.*`（`required = true`），但没装 git-lfs。用户 2026-10-27 自己删掉了（`git config --global --remove-section filter.lfs`）。`scripts/config.sh` 里的覆盖保留着，以防别的机器上也有这种配置 |

## 阶段

### 阶段 0：环境与基线
- [x] `scripts/00-check-env.sh` 全部通过（2026-10-26，要先设 `DEVELOPER_DIR`，见"本机环境"）
- [x] `scripts/01-fetch-chromium.sh` 完成，`src` 停在固定版本（2026-10-27，`src` 约 26 GB，在外置盘）
- [ ] （可选）未打补丁的 `content_shell` 在模拟器里能打开网页 → 证明工具链和源码没问题。**暂缓**：用 `args/` 的参数时，不打 0004 连 `gn gen` 都过不去；先直接编 Chrome，有需要对照时再编

### 阶段 1：模拟器里跑通 Chrome 界面
- [x] `scripts/02-apply-patches.sh` 打上 0001–0004（2026-10-27）
- [x] 模拟器和真机两套参数的 `gn gen` 都能通过（2026-10-27，需要 0004）
- [x] `scripts/03-build.sh sim` 编译通过（2026-10-27，5 路并行约 3 小时；补丁本身没碰到 API 漂移，只是得关掉 DrumBrake，见风险 13）
- [x] `scripts/04-run-simulator.sh` 启动后能看到 Chrome 界面（2026-10-27，验证过：首次引导页和新标签页都正常显示，持续运行不崩溃；第一次启动的崩溃已经在 0001 里修了，见日志）
- [ ] 能打开网页、滚动、输入文字（地址栏和网页输入框）。怎么点屏幕：模拟器窗口在 DeviceHub 里（Xcode 27 用它取代了 Simulator.app），可以手动操作。Claude 这边的模拟器面板要求系统 `xcode-select` 指向完整的 Xcode（用户不想改）；要让 Claude 自己点，得在 Claude 桌面 app 里打开 Computer Use。另外，用 `simctl openurl chromiums://…` 打开网址会弹出系统确认框
- [ ] 记录明显缺失或异常的功能（下载、查找、文本选择、视频等）

验收：模拟器里用 Chrome 界面正常浏览几个常见网站。

### 阶段 2：真机（iPhone 13 mini，iOS 27）
- [x] `scripts/03-build.sh device` 编译通过（2026-10-27，05:32–09:09，48153 步，没有错误）
- [x] `scripts/05-package-ipa.sh` 生成 IPA（2026-10-27：`dist/Chromium-158.0.8127.0-sideload.ipa`，148 MB，arm64，minos 26.0，SDK 27.1，未签名）
- [ ] 用 Sideloadly / AltStore / SideStore 装上，开发者模式已开
- [ ] 启动不崩，网页能显示
- [ ] 记录内存表现：重网页、多标签是否被系统杀掉

验收：手机上用免 JIT 模式日常浏览可用。

### 阶段 3：补强（按实际问题挑）
- [ ] 内存/地址空间：如遇启动时地址空间预留失败或频繁被杀，参考 `docs/patch-triage.md` 的 memory 类
- [ ] 视频：目前用 `--disable-features=avfoundation-overlays` 绕开，如需原生视频层再移植 `ca_renderer_layer_tree.mm` 的修复
- [ ] 输入、触摸、横屏尺寸等问题：参考 fix 类
- [ ] JIT：见下方风险 7

## 待验证的假设与风险

1. **补丁没编译过。**（2026-10-27 更新：0001–0004 已在模拟器配置下编译通过，验证过；运行时行为还要验证。） 写补丁时已经发现两处 API 漂移（`SysInfo::AmountOfPhysicalMemoryMB` 改成了 `AmountOfTotalPhysicalMemory()`，`--js-flags` 常量挪到了 Blink），还会有。编译报错先查 158 里接口叫什么。
2. **Chrome + Blink 在单进程下能否跑通。** `ios/web/content` 官方标注为原型（`SECURITY.md`："not currently shipped"）。2024 年 Igalia 列过缺失功能：打印预览、下载、文本选择、请求桌面版网站、文字缩放、翻译、页内查找、触摸事件。现在完成度未知。
3. **Chrome 这个 app 目标没有打包 BrowserEngineKit 扩展进程。** `ios/chrome/app/BUILD.gn` 在 `use_blink` 时只加了权限文件，没有像 `content/shell/BUILD.gn` 那样打包 `content_process`/`gpu_process`/`network_process` 扩展。推测官方的 Chrome+Blink 本来就跑不起多进程，单进程反而是唯一可行的路。需要在模拟器里确认。（2026-10-27 推翻，验证过：模拟器版和真机版的 `Chromium.app/Extensions/` 里都有 `chrome_content_process`、`chrome_gpu_process`、`chrome_network_process` 三个 .appex，每个只有 84 KB，代码都在 `chrome_framework` 里。单进程模式下它们不会被启动，模拟器里的日志可以确认；`05-package-ipa.sh` 打包时会把它们删掉，侧载时就不用多占 App ID。）
4. **BrowserEngineKit 的文本输入类在没有权限时是否可用。** `RenderWidgetUIView` 采用 `BETextInput` 协议。Blinker Fluid 在 iOS 17.4 以上用的就是这套，说明大概率可用；如果输入法异常，Blinker 有一个 1240 行的 UITextInput 替代实现（`render_widget_host_view_ios_uiview.mm`，分类里归在 legacy）可以参考。
5. **地址空间。** 侧载 app 未必拿得到 extended-virtual-addressing。`args/device.gn` 已关掉 V8 沙箱和 Oilpan caged heap；如果仍有大块预留失败，需要 memory 类补丁（PartitionAlloc 小内存池等）。
6. **内存上限。** 所有东西挤在一个进程里，4 GB 设备的 jetsam 上限可能被重网页顶到。补丁 0001 已按内存大小限制 V8 堆和 GPU 内存估算。
7. **JIT。** 侧载拿不到 JIT 权限，先用免 JIT（JS 明显变慢）。iOS 26 起，A15 及更新机型（含 13 mini）用 StikDebug 开 JIT 需要 app 自己实现 JIT 脚本协议（LiveContainer 文档："If you are on iOS 26+ and your device uses A15+ or M2+ (included), you'll also need a JIT script for each app"）。iOS 27 上的情况未知。放到最后。
8. **侧载工具对 iOS 27 的支持。** Sideloadly / AltStore / SideStore 在 iOS 27 上的状态要以它们当时的说明为准。免费 Apple ID 每 7 天要重签一次。
9. **应用组权限。** 真机包不签名，就不带任何权限声明；侧载工具可能因此不开通 Chrome 用的两个应用组（`group.<前缀>.chrome`/`.common`）。如果启动崩在共享容器相关代码，用 `scripts/05-package-ipa.sh --with-app-groups` 重新打包（临时签名写入声明）。侧载工具会不会改写应用组名称还不确定。
10. **Google 账号。** Chromium 构建没有 Google API key 和内部组件，登录/同步、Discover、Lens 等大概率不可用。
11. **`DEVELOPER_DIR` 能不能传到构建的每一步。**（2026-10-27：能，验证过。系统 `xcode-select` 指向 CLT 的情况下，模拟器版完整编译成功，包括 actool 等 Xcode 工具步骤。） `xcode-select -p`、`xcodebuild`、`xcrun` 都认它（验证过）；gn 生成时的 SDK 探测、siso 在本地执行的 actool/ibtool 等动作是否都继承这个环境变量，还没验证。如果编译时报找不到 Xcode 工具或 SDK，先在 Chromium 的 `src` 里 `git grep DEVELOPER_DIR build/` 看构建怎么处理它；临时改 `xcode-select` 是最后手段，要先问用户。
12. **本机 Xcode 27.1 比 CI 的 27.0 新。**（2026-10-27：模拟器版编译没有因此出错，验证过。） SDK 小版本不同可能带来少量编译错误。推测概率不高：新版本 SDK 里新加的弃用标记，只有部署目标不低于弃用版本时才会报警告，而这里的部署目标是 26.0。
13. **免 JIT 时没有 WebAssembly。** V8 的 Wasm 解释器 DrumBrake 在固定版本的 V8（`f7be3c62`）上编不过，V8 2026-10-26 的 main（`3c21887f`）也一样（验证过）。原因是上游改了接口，DrumBrake 没跟上：`Managed<T>::raw()` 现在要求传 `DisallowGarbageCollection&`，`TrustedCast<T>` 只允许受信任类型，DrumBrake 却用来转 `Map`、`WasmArray` 等普通对象。上游 CI 显然没编它。所以先 `v8_enable_drumbrake = false`，补丁 0001 也去掉了 `--wasm-jitless`。以后要 Wasm 有两条路：自己给 DrumBrake 写 V8 补丁（工作量未知），或者等 JIT（风险 7）。
14. **模拟器机型受限。** 本机 Xcode 27.1 的 iOS 27.1 模拟器运行时只支持 "iPhone Duo" 一种 iPhone（验证过），CI 用的 iPhone 16 和用户手上的 13 mini 都建不出来（"Incompatible device"）。Xcode 27 不再带 Simulator.app，模拟器窗口换成了 `Xcode.app/Contents/Applications/DeviceHub.app`（`com.apple.dt.Devices`，验证过；`04-run-simulator.sh` 会按路径打开它）。要在 13 mini 的屏幕尺寸上测，得另装一个支持它的模拟器运行时（几 GB，要先问用户）。

## 日志

- 2026-10-26：选定固定版本 `d586be9f`；对比 Blinker Fluid 全部改动并分类；写好补丁 0001–0003 和两个可选补丁，在固定版本的原始文件上验证 `git am --3way` 能干净打上；写好脚本（`bash -n` 和 shellcheck 通过，打补丁脚本在模拟的 checkout 上试跑过）和 `tools/blinker_rebase.py`（对固定版本跑过一遍，结果见 patch-triage.md）。未编译。
- 2026-10-26（Mac，第一次实际执行）：`00-check-env.sh` 不设 `DEVELOPER_DIR` 时报 FAIL，因为 `xcode-select` 指向 Command Line Tools（用户有意保持）；设成外置盘上的 Xcode 后全部通过，只剩"depot_tools 还没装"的提示（`01` 会自己装）。记录了本机环境；检查脚本的 FAIL 提示加上 `DEVELOPER_DIR` 的用法；新增待验证第 11、12 条。还没拉源码。
- 2026-10-26～27（Mac）：用户选外置盘放源码，并要求升到最新版本。按固定规则取官方 iOS Blink CI 最近一次通过的提交（不直接用 main 最新），从 `d586be9f` 升到 `4558926c`（158.0.8127.0），核对结果写在"固定版本"表下面；`config.sh`、`CLAUDE.md`、`README.md` 等处的版本号一起改了。新增 `scripts/config.local.sh`（不进 git）存本机路径，`config.sh` 会自动读取。开始在后台拉源码，下完自动编未打补丁的模拟器版 `content_shell` 作基线。
- 2026-10-27（Mac）：第一次 `gclient sync`。`src` 按提交号浅克隆成功（验证过 googlesource 支持；中途经代理断了 3 次，gclient 自己重试成功了），约 26 GB。依赖 `third_party/litert/src` 检出失败，报 `git-lfs: command not found`：全局 git 配置要求必须有 LFS 过滤器，本机却没装 git-lfs。脚本原来的"浅克隆失败就改下完整历史"随即启动，被我停掉了，因为失败跟历史无关，继续下去会白下几十 GB。修复：`config.sh` 让脚本里的 git 把 LFS 文件检出成指针（LiteRT 的 LFS 文件是 23 个预编译库，Chromium 的 `BUILD.gn` 不用）；`01-fetch-chromium.sh` 去掉了自动回退，失败就退出，要完整历史可以手动设 `FULL_HISTORY=1`。手动修好 LiteRT 的检出后重新开始同步。
- 2026-10-27（Mac）：同步续上后两分半就完成了，hooks 全部跑通，`src` 停在 `4558926c`。接着编 `content_shell` 基线，结果 `gn gen` 报错：`ios/chrome/app/BUILD.gn:1009` 的 `_extension_toolchain` 是 "Assignment had no effect"，因为 `args/` 把 Chrome 的 app 扩展全关了，上游没测过这种配置。新增补丁 0004（`not_needed`），按第 7 节的流程在 `ios-blink-sideload` 分支上提交后导出。`02-apply-patches.sh` 从头打 0001–0004 成功，模拟器和真机两套参数的 `gn gen` 都通过了（验证过）。"不打补丁的基线"已经做不成，所以暂缓，改为直接在后台编 Chrome 模拟器版。
- 2026-10-27（Mac）：Chrome 模拟器版编译（共约 6.4 万步）被打断了两次：00:54 和 01:08，正好都是会话退出、连带杀掉后台进程的时候（日志里是 "interrupt by signal"）；失败的步骤一直是 0，没有编译错误。中途编译慢得反常，几个本来 10 秒左右的小文件编了 9–10 分钟。用户看到机器卡、以为内存泄漏。实测（验证过）：空闲内存只剩 2%，交换区涨到约 3 GB。原因是默认的 10 路并行，再加上 Blink 的 `generate_bindings.py` 每次调用都按 CPU 核数开 10 个 `multiprocessing` 进程（每个 110–180 MB），同时还有 siso 自己的约 2.3 GB。修复：`config.sh` 新增 `BUILD_JOBS`（`03-build.sh` 把它传给 autoninja 的 `-j`），本机设为 5；编译改成用 `setsid` 脱离会话运行，日志放在 `/Volumes/Chromium-iOS/chromium/build-logs/`。之后（验证过）：生成绑定那一波 Python 进程跑完后，空闲内存回到约 77%，交换区不再增长，每分钟约 280 步；外置盘读写每秒只有几 MB。
- 2026-10-27（Mac）：5 路并行重新开编后速度正常了（平均每秒约 2.9 步，内存稳定）。37 分钟、6524 步时第一次出现编译错误：3 个 DrumBrake 文件（`v8/src/wasm/interpreter/wasm-interpreter{,-runtime,-objects}.cc`）编不过，原因见风险 13，跟我们的补丁无关。处理：两份 `args/` 都改成 `v8_enable_drumbrake = false`；补丁 0001 去掉 `--wasm-jitless`（没有 DrumBrake 时它是未知参数，V8 会忽略它后面的 `--max-old-space-size` 等参数）。改了补丁文件，用 `02-apply-patches.sh` 重新打上后，从分支重新导出 0001；两套参数的 `gn gen` 都通过。02:00 起继续编译。
- 2026-10-27（Mac）：**Chrome 模拟器版第一次编译通过**（02:00–05:08，约 3 小时，5 路并行，产物 `Chromium.app` 541 MB，代码在 `chrome_framework.framework` 里）。`04-run-simulator.sh` 第一次实际跑，修了两处：本机运行时建不出 iPhone 16（见风险 14），改成自动换用现有的 iPhone 模拟器；没有 Simulator.app 时不再中断。**在 iPhone Duo 模拟器里，Chrome 界面成功启动**，日志显示 0001 的参数全部生效（`--single-process`、`--js-flags=--jitless --max-old-space-size=512 …` 等）。约 1 秒后，在地址栏的第一个搜索建议请求上崩溃：`mojo::SimpleWatcher` 的 DCHECK `task_runner_->RunsTasksInCurrentSequence()`。根因（读源码确认）：单进程时 content 的网络服务在进程内专用线程上，`NetTaskScheduler` 把该线程的队列装成全进程的 `net::GetTaskRunner()`，而 ios/web 的 `NetworkContext` 在 IO 线程上创建 `URLLoader`。修复：0001 里追加 `--disable-features=NetTaskScheduler`（详见 architecture.md 的 0001 一节）；按改补丁的流程把修改合进 0001 提交并重新导出，`02-apply-patches.sh` 重新打上，开始增量编译。
- 2026-10-27（Mac）：修好 NetTaskScheduler 的增量编译只用了 80 秒（重新链接 `chrome_framework` 约 0.7 分钟）。再次在 iPhone Duo 模拟器里启动：**不再崩溃，持续运行**，日志里只剩几条 ios/web/content 原型本来就有的 "Not implemented reached"（Cookie 变更订阅、`GetDisplayNearestWindow`、`SetCustomOpenPanelSupported`），以及几次 SSL 握手失败（`net_error -100`，推测是直连 Google 被墙；Chromium 的网络栈在模拟器里是否走 Mac 的系统代理还没查）。截图（验证过）：先是 Chrome 原生的"默认使用 Chromium"首次引导页（中文），用 `xcrun simctl spawn <udid> defaults write <bundle id> FirstRunForceDisabled -bool YES` 跳过引导后，是完整的 Chrome 新标签页（地址栏、AI 模式/无痕模式、常用网站、快捷方式、底部工具栏）。iPhone Duo 是折叠屏机型，有两块屏；`simctl reboot` 之后默认截到的屏是黑的，`shutdown` 再 `boot` 就恢复了。**还没验证网页渲染**（补丁 0002 的关键）：模拟器面板不可用，`simctl` 没有点击命令，`openurl chromiums://example.com` 会弹系统确认框。05:32 起在后台编真机版（`scripts/03-build.sh device`）。
- 2026-10-27（Mac）：更正前面"这个 Xcode 没有 Simulator.app、被精简过"的说法：当时那条 `find` 有 bug（在顶层包就停下了）。实际上开发者工具都在，只是 Xcode 27 把它们挪到了 `Xcode.app/Contents/Applications/`（Instruments、Accessibility Inspector、FileMerge 等），并用 **DeviceHub.app** 取代了 Simulator.app。已按路径打开 DeviceHub；`04-run-simulator.sh` 也改成在 Xcode 27 上打开它。
- 2026-10-27（Mac）：**真机版编译通过**（05:32–09:09，5 路并行，48153 步，没有失败），`05-package-ipa.sh` 第一次实际运行就成功了：`dist/Chromium-158.0.8127.0-sideload.ipa`（148 MB）。打包时发现 Chrome 目标其实打包了 BrowserEngineKit 的三个扩展进程（风险 3 被推翻），脚本已经把它们删掉。还没装到手机上。
- 2026-10-27（Mac）：应用户要求，把 IPA 放进 GitHub Release。仓库是公开的，所以先建成**草稿 + 预发布**（https://github.com/Mr-Drinking/Chromium-iOS/releases ，标签名 `chromium-158.0.8127.0-sideload-1`，草稿只有仓库管理员能看到）；IPA 的 SHA-256 是 `2a033de2…443a5d`。公开发布前要先确认：许可（README 的"许可"一节）；源码先提交并推送，让标签对上产出这个 IPA 的源码。签名方面查过，这台 Mac 的钥匙串里没有任何代码签名证书、没有描述文件，`devicectl` 也看不到手机。
- 2026-10-27（Mac）：用户确认公开发布。本轮改动提交后推送到 GitHub，Release `chromium-158.0.8127.0-sideload-1` 改为公开（仍标为预发布），标签指向这次提交，也就是产出这个 IPA 的源码。
