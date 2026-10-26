# 进度与待验证事项

最后更新：2026-10-27（Mac 上：环境检查通过；固定版本升到 `4558926c`；正在拉源码，下完自动编 content_shell 基线）。

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
| 磁盘 | 内置盘 215 GB 可用；外置盘 `Chromium-iOS` 219 GB 可用（USB，目前经 hub 只跑 5 Gb/s，Owners: Disabled，Spotlight 在索引） |
| 网络 | 走本地代理（环境变量 `HTTPS_PROXY` 和 git `http.proxy` 都已设置）；googlesource、GCS、CIPD 都能连通，固定提交在 googlesource 上查得到 |

## 阶段

### 阶段 0：环境与基线
- [x] `scripts/00-check-env.sh` 全部通过（2026-10-26，要先设 `DEVELOPER_DIR`，见"本机环境"）
- [ ] `scripts/01-fetch-chromium.sh` 完成，`src` 停在固定版本
- [ ] （可选）未打补丁的 `content_shell` 在模拟器里能打开网页 → 证明工具链和源码没问题

### 阶段 1：模拟器里跑通 Chrome 界面
- [ ] `scripts/02-apply-patches.sh` 打上 0001–0003
- [ ] `scripts/03-build.sh sim` 编译通过（预计会有因 API 漂移导致的编译错误要修）
- [ ] `scripts/04-run-simulator.sh` 启动后能看到 Chrome 界面
- [ ] 能打开网页、滚动、输入文字（地址栏和网页输入框）
- [ ] 记录明显缺失或异常的功能（下载、查找、文本选择、视频等）

验收：模拟器里用 Chrome 界面正常浏览几个常见网站。

### 阶段 2：真机（iPhone 13 mini，iOS 27）
- [ ] `scripts/03-build.sh device` 编译通过
- [ ] `scripts/05-package-ipa.sh` 生成 IPA
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

1. **补丁没编译过。** 写补丁时已经发现两处 API 漂移（`SysInfo::AmountOfPhysicalMemoryMB` 改成了 `AmountOfTotalPhysicalMemory()`，`--js-flags` 常量挪到了 Blink），还会有。编译报错先查 158 里接口叫什么。
2. **Chrome + Blink 在单进程下能否跑通。** `ios/web/content` 官方标注为原型（`SECURITY.md`："not currently shipped"）。2024 年 Igalia 列过缺失功能：打印预览、下载、文本选择、请求桌面版网站、文字缩放、翻译、页内查找、触摸事件。现在完成度未知。
3. **Chrome 这个 app 目标没有打包 BrowserEngineKit 扩展进程。** `ios/chrome/app/BUILD.gn` 在 `use_blink` 时只加了权限文件，没有像 `content/shell/BUILD.gn` 那样打包 `content_process`/`gpu_process`/`network_process` 扩展。推测官方的 Chrome+Blink 本来就跑不起多进程，单进程反而是唯一可行的路。需要在模拟器里确认。
4. **BrowserEngineKit 的文本输入类在没有权限时是否可用。** `RenderWidgetUIView` 采用 `BETextInput` 协议。Blinker Fluid 在 iOS 17.4 以上用的就是这套，说明大概率可用；如果输入法异常，Blinker 有一个 1240 行的 UITextInput 替代实现（`render_widget_host_view_ios_uiview.mm`，分类里归在 legacy）可以参考。
5. **地址空间。** 侧载 app 未必拿得到 extended-virtual-addressing。`args/device.gn` 已关掉 V8 沙箱和 Oilpan caged heap；如果仍有大块预留失败，需要 memory 类补丁（PartitionAlloc 小内存池等）。
6. **内存上限。** 所有东西挤在一个进程里，4 GB 设备的 jetsam 上限可能被重网页顶到。补丁 0001 已按内存大小限制 V8 堆和 GPU 内存估算。
7. **JIT。** 侧载拿不到 JIT 权限，先用免 JIT（JS 明显变慢）。iOS 26 起，A15 及更新机型（含 13 mini）用 StikDebug 开 JIT 需要 app 自己实现 JIT 脚本协议（LiveContainer 文档："If you are on iOS 26+ and your device uses A15+ or M2+ (included), you'll also need a JIT script for each app"）。iOS 27 上的情况未知。放到最后。
8. **侧载工具对 iOS 27 的支持。** Sideloadly / AltStore / SideStore 在 iOS 27 上的状态要以它们当时的说明为准。免费 Apple ID 每 7 天要重签一次。
9. **应用组权限。** 真机包不签名，就不带任何权限声明；侧载工具可能因此不开通 Chrome 用的两个应用组（`group.<前缀>.chrome`/`.common`）。如果启动崩在共享容器相关代码，用 `scripts/05-package-ipa.sh --with-app-groups` 重新打包（临时签名写入声明）。侧载工具会不会改写应用组名称还不确定。
10. **Google 账号。** Chromium 构建没有 Google API key 和内部组件，登录/同步、Discover、Lens 等大概率不可用。
11. **`DEVELOPER_DIR` 能不能传到构建的每一步。** `xcode-select -p`、`xcodebuild`、`xcrun` 都认它（验证过）；gn 生成时的 SDK 探测、siso 在本地执行的 actool/ibtool 等动作是否都继承这个环境变量，还没验证。如果编译时报找不到 Xcode 工具或 SDK，先在 Chromium 的 `src` 里 `git grep DEVELOPER_DIR build/` 看构建怎么处理它；临时改 `xcode-select` 是最后手段，要先问用户。
12. **本机 Xcode 27.1 比 CI 的 27.0 新。** SDK 小版本不同可能带来少量编译错误。推测概率不高：新版本 SDK 里新加的弃用标记，只有部署目标不低于弃用版本时才会报警告，而这里的部署目标是 26.0。

## 日志

- 2026-10-26：选定固定版本 `d586be9f`；对比 Blinker Fluid 全部改动并分类；写好补丁 0001–0003 和两个可选补丁，在固定版本的原始文件上验证 `git am --3way` 能干净打上；写好脚本（`bash -n` 和 shellcheck 通过，打补丁脚本在模拟的 checkout 上试跑过）和 `tools/blinker_rebase.py`（对固定版本跑过一遍，结果见 patch-triage.md）。未编译。
- 2026-10-26（Mac，第一次实际执行）：`00-check-env.sh` 不设 `DEVELOPER_DIR` 时报 FAIL，因为 `xcode-select` 指向 Command Line Tools（用户有意保持）；设成外置盘上的 Xcode 后全部通过，只剩"depot_tools 还没装"的提示（`01` 会自己装）。记录了本机环境；检查脚本的 FAIL 提示加上 `DEVELOPER_DIR` 的用法；新增待验证第 11、12 条。还没拉源码。
- 2026-10-26～27（Mac）：用户选外置盘放源码，并要求升到最新版本。按固定规则取官方 iOS Blink CI 最近一次通过的提交（不直接用 main 最新），从 `d586be9f` 升到 `4558926c`（158.0.8127.0），核对结果写在"固定版本"表下面；`config.sh`、`CLAUDE.md`、`README.md` 等处的版本号一起改了。新增 `scripts/config.local.sh`（不进 git）存本机路径，`config.sh` 会自动读取。开始在后台拉源码，下完自动编未打补丁的模拟器版 `content_shell` 作基线。
