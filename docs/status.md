# 进度与待验证事项

最后更新：2026-10-28（Mac：补丁 0001–0026 和 V8 补丁 0201 在模拟器里验证过，WebAssembly、翻译、系统代理、滚动、滑到底、下载、文本选择（拖柄和 Safari 同款的编辑菜单，系统蓝的光标和选区，空输入框能粘贴）、深色模式、屏幕键盘、页内查找、请求桌面版网站、网站权限（定位、剪贴板、摄像头）都正常，无痕模式停用；最新的真机包是 Release `chromium-158.0.8127.0-sideload-6`（公开，预发布）：用户在真机上测过含 0001–0022 的第一版，反馈的页内查找起点和选区颜色问题（第 22、23 条）修好后，2026-10-28 换成含 0001–0023 的新包，标签移到 `82cb4da`，新包还没在真机上测。用户在真机上测过 Release 3、4、6，反馈见"真机反馈的问题"第 16–26 条；第 24–26 条的修正（0024–0026）还没发到真机。Release 2 是 0001–0007 的真机包）。

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

## 真机反馈的问题（2026-10-27，用户在 iPhone 13 mini 上测 Release 1）

| # | 问题 | 状态 |
|---|---|---|
| 1 | 发热严重 | 查了一部分：模拟器里静止页面 CPU 0.1%，不空转（bilibili 首页加载完也是 0.0–0.1%）；GPU 光栅化默认开着（`kDefaultEnableGpuRasterization` 在 Apple 平台默认开）。2026-10-27 粗测：同一个 bilibili 页面加载 25 秒，Chromium 用了约 5 CPU 秒，模拟器里的 Safari（所有进程合计）约 10 CPU 秒，免 JIT 的 JS 在模拟器里并不显得更费 CPU（数据粗糙；GPU 的工作不算在进程 CPU 里）。日志里每次加载网页都有 `PageContextWrapper execution timed out`，查过源码：是 Chrome 为 AI 功能抽取网页正文，只取文字、不截图，Blink 下相关 JS 调用被挡住，只是等到超时，不是发热原因。最终要在真机上用 Instruments 定位 |
| 2 | 有点卡 | **找到并修了一个主要原因**（补丁 0011，模拟器验证过）：Chrome 下拉刷新的手势一识别就取消网页收到的触摸，Blink 收到 touchcancel，页面滚几下就停，而且只是"有时候"这样（换渲染视图时这个手势会被移除）。修后页面跟手、带惯性。用 AXe 测：之前 500 pt 的滑动只滚约 30 pt，之后正常。真机上的效果待用户确认 |
| 3 | 网页不用系统字体（SF Pro / SF Mono） | **已修**（补丁 0005，模拟器验证过） |
| 4 | Passkey 不支持 | **不做**（用户 2026-10-27 决定放弃）。读源码确认：Chromium 的通行密钥实现（iCloud 钥匙串）只在 Mac 上编译（`device/fido/BUILD.gn` 里的 `is_mac`），还要求苹果授予的 `com.apple.developer.web-browser.public-key-credential` 权限（`device/fido/mac/icloud_keychain_sys.mm`）。iOS 的 Blink 版没有这部分实现，侧载 app 也拿不到这个权限 |
| 5 | 偶尔冒出一行 Times 小字 "This is an error page." | **已修**（补丁 0006，模拟器验证过）。顺带修了一个无障碍崩溃（补丁 0007） |
| 6 | 滚动条拖不动，样式和原版不一样 | **暂缓**（用户说优先级低）。读源码确认：网页外面那层 `UIScrollView` 只是个镜像，滚动被禁用、手势识别器全被移除（`render_widget_host_view_ios_uiview.mm` 的 `-updateView:`），滚动由 Blink 处理。滚动条是 Blink 画的移动版叠加滚动条，不响应触摸。要换成原生、可拖动的指示条，得隐藏 Blink 的滚动条、显示 UIKit 的，再把拖动转成 Blink 的滚动，不是小改动 |
| 7 | 没有 WebAssembly | **已修**（V8 补丁 0201 + 0001 的 `--wasm-jitless` + `args/` 开 DrumBrake 并做显式边界检查，模拟器验证过）：测试页 17 项全过，速度和免 JIT 的 JS 相当，比 JIT 慢 4–6 倍；新式异常处理（`try_table`）的模块会报 `CompileError` |
| 8 | 想要网页翻译（用户 2026-10-27 提出） | **已修**（补丁 0008，模拟器验证过）：德语网页会弹出翻译提示，翻译后是中文。需要连得上 Google |
| 9 | （测试时发现）Blink 版网页请求不走系统代理设置 | **已修**（补丁 0009，模拟器验证过），见风险 15 |
| 10 | （测试时发现）google.com 只给旧版基础页面 | **已修**（补丁 0010，模拟器验证过）：UA 里的 iOS 版本由 14_0 改成 18_7 |
| 11 | 网页滑不到底（用户 2026-10-27 提出） | **已修**（补丁 0012，模拟器验证过）：Blink 被告知工具栏能收起，多留了 108 pt 的滚动距离，可工具栏在 Blink 下从不收起。现在能滚到底；工具栏仍然一直显示（正版滚动时会收起，要接进 Chrome 的 fullscreen 逻辑，没做） |
| 12 | 下载（用户 2026-10-27 让查） | **已修**（补丁 0013，模拟器验证过）。原因是 Blink 版 `ContentBrowserContext::GetDownloadManagerDelegate()` 返回空，content 把每个下载的目标路径定成空，等于直接取消。补丁加了一个下载委托，把 content 的下载包装成 `web::DownloadTask` 交给 Chrome 的下载栏。zip 链接、`download` 属性、PDF、页面生成的 blob 都能下载，存到 app 的 Documents 里，和原文件逐字节一致；下载前关掉下载栏、下载中途点"停止"、下载中关掉标签页，传输都会断开，不留半截文件。PDF 不能在网页里直接看（Blink 在 iOS 上没有 PDF 查看器），会当成下载；下载完用"打开方式…"（原来的"打开"会新开标签页再下载一次，已改掉） |
| 13 | （测试时发现）接实体键盘时，在网页里按 Chrome 的快捷键或 Cmd+C 就闪退 | **已修**（补丁 0014，模拟器验证过）。上游的 `RenderWidgetUIView` 对所有动作都声称能处理，UIKit 就把它没实现的动作也发给它，报 "unrecognized selector"。现在 Cmd+C/X/V 能拷贝、剪切、粘贴，快捷键交还给 Chrome。剩一个小问题：没有功能的 Cmd 组合键（例如无痕停用后的 Cmd+Shift+N）会在网页输入框里打出那个字母（推测是 content 的按键处理没过滤 Cmd 组合键，没细查） |
| 14 | 编辑菜单（用户 2026-10-27 要求） | **已加**（补丁 0015，模拟器验证过）。原来长按文字只会选中一个词，没有任何菜单，触屏上没法拷贝。现在长按普通文字弹出系统的"拷贝 / 全选"，输入框里是"剪切 / 拷贝 / 粘贴 / 全选"，菜单显示在选中文字上方；"全选"后菜单还在，可以直接拷贝全文；长按链接还是 Chrome 原来的链接菜单。还没有选区拖柄，只能选一个词或全选。（2026-10-27 更新：用户觉得难用，0015 改成弹系统菜单，补丁 0019 加上了拖柄，见第 18 条） |
| 15 | （测试时发现）打开无痕标签页就闪退（模拟器） | **无痕模式停用**（补丁 0016，模拟器验证过）。单进程模式只支持一个浏览器上下文，见风险 16。现在各处"新建无痕标签页""在无痕模式下打开"都是灰的，标签页网格的无痕页显示"无痕模式不可用 / 您的组织关闭了私密浏览功能"（借用的是企业策略的提示文字，并没有什么组织）。新标签页上的"无痕模式"快捷按钮还显示着，点了没反应（上游的快捷按钮不看停用状态，策略停用时也一样），没改 |
| 16 | 用屏幕键盘在输入框里打字，每输一个字网页就往下移（用户 2026-10-27 在真机上发现） | **已修**（补丁 0017，模拟器验证过）。键盘高度被扣了两次：Chrome 已经把网页视图缩到键盘上方，content 计算可见区域时又减了一次键盘高度，可见区域变成 0，Blink 每次为了露出光标都要滚一屏。模拟器里用拼音屏幕键盘测：之前每按一个键滚约 420 px，之后只在聚焦时把输入框滚进视野一次，打字、选候选字、收起键盘页面都不动。真机上待用户确认。（2026-10-27 更新：补丁 0020 让键盘不再缩小网页视图，可见区域的算法跟着改了，见第 20 条） |
| 17 | 手机上关掉 Shadowrocket 后网页报错（用户 2026-10-27 提出） | **已改进，待真机确认**（补丁 0018）：网络配置一变（开关 VPN 会触发）就立刻重读代理设置，不再等最长 10 秒的轮询。用户还没提供报错代码，所以还不确定原来的报错就是这个原因。以下是改之前的分析：没有写死代理：补丁 0009 读 iOS 的系统代理设置，Chromium 在 iOS 上每 10 秒（有请求时）重读一次，所以关掉 VPN 后的头几个请求可能还走已关闭的代理（推测）。等用户提供报错代码。准备的改法：登记 iOS 的网络变化通知（`com.apple.system.config.network_change`），一变就立刻重读代理设置 |
| 18 | 长按后的选择菜单很难用，希望和 Safari 一致（用户 2026-10-27 提出） | **已改**（补丁 0019，0015 重写，模拟器验证过）。原来长按只选中一个词，没有拖柄，菜单只有"拷贝 / 全选"，还常压在地址栏上。content 其实接了 BrowserEngineKit 的系统文本交互（Safari 的拖柄和编辑菜单就是它），但它从 content 读到的选区一直是空的：起点写成了终点、所有位置比较都相等、`beginningOfDocument` 为空，系统换算时把选区丢了；只在选中文字变化时刷新（那时 Blink 还没报新的边界）；非输入框里的裁剪区域是空矩形，拖柄全被裁掉。拖柄出来后又修了拖动逻辑（拖结尾手柄动的是开头）。现在：长按选词，两端有拖柄，上方是系统菜单"拷贝 / 查询 / 翻译"（第二页"共享…"），同一台模拟器里 Safari 是"拷贝 / 查询 / 翻译 / 查找"，展开后还有"搜索网页"等 Safari 自己的功能；拖柄能拖、能跨行，松手后菜单回到新选区上方；滚动时菜单收起，停下后再出现；"查询"弹系统词典，"翻译"弹 Apple 翻译；输入框里是"剪切 / 拷贝 / 粘贴 / 全选"。细节见 architecture.md。真机待确认 |
| 19 | 深色模式不可用（用户 2026-10-27 提出） | **已修**（补丁 0021，模拟器验证过）。网页一直以为系统是浅色：iOS 上没有读取系统外观的实现，iOS 的嵌入层也不把配色偏好传给网页（默认浅色）。现在支持深色的网页（`prefers-color-scheme`、`color-scheme: light dark`）跟随系统，网页开着时切换系统外观也立刻生效。Chrome 自己的界面本来就跟随系统。google.com 在这台模拟器里 Safari 也是浅色（它自己的"深色主题"设置是"已停用"），不是这里的问题 |
| 20 | 屏幕键盘会缩短页面布局，和 Liquid Glass 的设计冲突，网页卡来卡去（用户 2026-10-27 提出） | **已修**（补丁 0020，模拟器验证过）。Chrome 把键盘高度并进网页视图的底部内边距（WKWebView 里只表示"被挡住"），Blink 版据此把网页视图缩短，每次键盘出现、收起、改变高度，页面都要整页重排，半透明键盘后面只有一块灰色。现在键盘不再缩小网页视图，只缩小可视区域，和 Safari、安卓 Chrome 一样：聚焦输入框时 `innerHeight` 保持 631，可视区域变成 314，平滑滚动把输入框居中在键盘上方，键盘后面看得到网页。顺带修了三处跳动：滚动时可视区域高度在 314/315 之间来回跳、每帧都触发一次 resize；点输入框时网页视图会被瞬间挪到页面顶部再回来；键盘上方的按钮栏没算进遮挡，输入框会停在按钮后面。真机待确认 |
| 21 | 网页查找（页内查找）是灰色的（用户 2026-10-27 问） | **已加**（补丁 0022，模拟器验证过）：菜单里的"在网页中查找…"能用了，弹出和 Safari 一样的系统查找栏，显示"第几个 / 共几个"，上一个、下一个、区分大小写、中文都正常，关闭后高亮清除。以下是之前读源码确认的原因：Chrome 先问网页能否搜索，Blink 版 `ContentWebState::IsFindInteractionSupported()` 是上游的空实现，固定返回 false（`GetFindInteraction()` 也返回 nil），菜单项就灰了。正版 Chrome iOS 用 WKWebView 自带的系统查找面板（`UIFindInteraction`），Blink 版没有对应实现（2024 年 Igalia 列的缺失功能里也有它，见风险 2）。做法是把 content 的 `WebContents::Find` 接到系统查找栏上，见 architecture.md 的 0022 一节 |
| 22 | 页内查找的起点和 Safari 不一样，不会从第 1 个开始（用户 2026-10-28 在真机上发现） | **已修**（补丁 0022 修正，模拟器验证过）。系统查找栏每次搜索后会自己调一次"下一个"，第一版新搜索时自己也选中一个，而且 Blink 从上一次的当前项接着找，所以每敲一个字母往后挪一格：页面停在第 3 处时打 apple，停在 5/6。现在新搜索从页面开头重来、只计数和高亮，由那次"下一个"选中第一个，和 Safari 一样是 1/6，拼音候选上屏也一样。之前说"Safari 用拼音上屏也是 2/5"是错的，已更正。见 architecture.md 的 0022 一节。2026-10-28 已换进测试版 6，待真机确认 |
| 23 | 选区拖柄和选区的颜色不对（用户 2026-10-28 提出） | **已修**（补丁 0023，模拟器验证过）。拖柄是写死的纯蓝，选区是安卓的青色（选中的字还变黑），光标是 1 pt 宽、和文字同色的竖线。现在拖柄、选区、光标都是系统蓝：选区 20% 不透明、字保持原色，光标 2 pt 宽，和 Safari 取色一致。见 architecture.md 的 0023 一节。2026-10-28 已换进测试版 6，待真机确认 |
| 24 | 切换到电脑模式（请求桌面版网站）不可用（用户 2026-10-28 在真机上发现） | **已修**（补丁 0024，模拟器验证过）。菜单项调用的 `ReloadWithUserAgentType()` 在 Blink 版是上游没实现的空函数。现在照安卓版 Chrome 的做法：换成 Mac 版 Chrome 的 UA（客户端提示也改），按原始网址重新加载，之后这个标签页里点链接、输网址都保持桌面版，菜单变成"请求切换到移动版网站"。见 architecture.md 的 0024 一节 |
| 25 | 空文本框里没法粘贴（用户 2026-10-28 提出） | **已修**（补丁 0025，模拟器验证过）。只有光标时系统不知道光标在哪，编辑菜单弹不出来。现在和 Safari 一样：已聚焦的输入框再点一下（光标没被移动时）或长按，弹出"粘贴"，有字时还有"选择 / 全选"。见 architecture.md 的 0025 一节 |
| 26 | 网页请求不了位置、剪贴板等权限（用户 2026-10-28 提出） | **已修**（补丁 0026，模拟器验证过，摄像头用的是虚拟设备）。Blink 版没有权限委托，content 对所有权限一律直接拒绝。现在写剪贴板直接允许；定位、读剪贴板弹提示问用户（记到 app 退出）；摄像头、麦克风用 Chrome 给 WKWebView 用的同一个提示；通知仍不支持。见 architecture.md 的 0026 一节 |

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
- [x] 能打开网页、滚动、输入文字（2026-10-27，验证过：在模拟器里用 AXe 操作。打开网页、地址栏输入一直正常；滚动原来常常被打断，补丁 0011 修好；网页输入框能输入，中文拼音输入法的候选和标记文字也正常。怎么在模拟器里自动操作见 build-guide.md 的 AXe 一节）
- [ ] 记录明显缺失或异常的功能（下载、查找、文本选择、视频等）

验收：模拟器里用 Chrome 界面正常浏览几个常见网站。

### 阶段 2：真机（iPhone 13 mini，iOS 27）
- [x] `scripts/03-build.sh device` 编译通过（2026-10-27，05:32–09:09，48153 步，没有错误）
- [x] `scripts/05-package-ipa.sh` 生成 IPA（2026-10-27：`dist/Chromium-158.0.8127.0-sideload.ipa`，148 MB，arm64，minos 26.0，SDK 27.1，未签名）
- [x] 用 Sideloadly / AltStore / SideStore 装上，开发者模式已开（2026-10-27，用户装了 Release 里的 IPA）
- [x] 启动不崩，网页能显示（2026-10-27，用户在 iPhone 13 mini / iOS 27 上验证过：**网页能看**。补丁 0002 的进程内显示在真机上有效）
- [ ] 记录内存表现：重网页、多标签是否被系统杀掉

验收：手机上用免 JIT 模式日常浏览可用。

### 阶段 3：补强（按实际问题挑）
- [ ] 内存/地址空间：如遇启动时地址空间预留失败或频繁被杀，参考 `docs/patch-triage.md` 的 memory 类
- [ ] 视频：目前用 `--disable-features=avfoundation-overlays` 绕开，如需原生视频层再移植 `ca_renderer_layer_tree.mm` 的修复
- [ ] 输入、触摸、横屏尺寸等问题：参考 fix 类
- [ ] JIT：见下方风险 7

## 待验证的假设与风险

1. **补丁没编译过。**（2026-10-27 更新：0001–0004 已在模拟器配置下编译通过，验证过；运行时行为还要验证。） 写补丁时已经发现两处 API 漂移（`SysInfo::AmountOfPhysicalMemoryMB` 改成了 `AmountOfTotalPhysicalMemory()`，`--js-flags` 常量挪到了 Blink），还会有。编译报错先查 158 里接口叫什么。
2. **Chrome + Blink 在单进程下能否跑通。** `ios/web/content` 官方标注为原型（`SECURITY.md`："not currently shipped"）。2024 年 Igalia 列过缺失功能：打印预览、下载、文本选择、请求桌面版网站、文字缩放、翻译、页内查找、触摸事件。（2026-10-27 更新：翻译、下载、文本选择的编辑菜单分别由补丁 0008、0013、0015 补上，触摸被打断的问题由 0011 修好；页内查找、打印预览、请求桌面版网站、文字缩放还没测。另见风险 16。又更新：选区拖柄和 Safari 同款的编辑菜单由 0019 补上，页内查找由 0022 补上，见"真机反馈的问题"第 21 条；打印预览、请求桌面版网站、文字缩放还没测。2026-10-28：请求桌面版网站由 0024 补上，见第 24 条。）
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
13. **免 JIT 时没有 WebAssembly。**（2026-10-27 已修，见 V8 补丁 0201 和日志。）V8 的 Wasm 解释器 DrumBrake 在固定版本的 V8（`f7be3c62`）上编不过，V8 2026-10-26 的 main（`3c21887f`）、2026-10-27 的 main 也一样（验证过）。原因是上游改了接口，DrumBrake 没跟上：`TrustedManaged<T>::raw()` 现在要求传 `DisallowGarbageCollection&`，`TrustedCast<T>` 只允许受信任类型，DrumBrake 却用来转 `Map`、`WasmArray` 等普通对象。上游 CI 显然没编它。V8 补丁 0201 修好了编译；两份 `args/` 开了 `v8_enable_drumbrake` 和 `v8_drumbrake_bounds_checks`，0001 传 `--wasm-jitless`。
14. **模拟器机型受限。**（2026-10-27 更新：本机另有一个 iOS 27.0 运行时，支持 iPhone 11 到 18 系列，包括 13 mini，`04-run-simulator.sh` 现在会自动挑支持所选机型的运行时；之后的测试都在 "iPhone 13 mini" 上做。）本机 Xcode 27.1 的 iOS 27.1 模拟器运行时只支持 "iPhone Duo" 一种 iPhone（验证过），CI 用的 iPhone 16 和用户手上的 13 mini 都建不出来（"Incompatible device"）。Xcode 27 不再带 Simulator.app，模拟器窗口换成了 `Xcode.app/Contents/Applications/DeviceHub.app`（`com.apple.dt.Devices`，验证过；`04-run-simulator.sh` 会按路径打开它）。要在 13 mini 的屏幕尺寸上测，得另装一个支持它的模拟器运行时（几 GB，要先问用户）。
15. **网页请求不走系统代理设置。**（2026-10-27 补充：补丁 0009 用的 `ProxyConfigServiceIOS` 在 iOS 上只能轮询，每 10 秒、而且要有请求时才重读；补丁 0018 加上了网络变化通知，开关 VPN 后立刻重读。）（2026-10-27，读源码确认，模拟器里也看到了现象。）Blink 版的网页请求走 content 的网络服务，ios/web 没给它传代理设置，于是它退回直连（`services/network/network_context.cc` 里的 `CreateDirect()`）。所以 iOS 里给 Wi-Fi 配的 HTTP 代理、PAC 对网页无效；Clash 等 VPN 型代理（虚拟网卡）对所有流量生效，不受影响。模拟器里同理：Mac 的系统代理不起作用，google.com 打不开，只能开代理软件的虚拟网卡（TUN）模式。**补丁 0009 已修**：iOS 上改读系统代理设置（`ProxyConfigServiceIOS`），之后模拟器里的 Chromium 直接走 Mac 的系统代理（验证过）。
16. **单进程只支持一个浏览器上下文，所以没有无痕模式。**（2026-10-27，读源码确认，模拟器里复现了。）content 的单进程模式只有一个进程内渲染器，`RenderProcessHostImpl::IsSuitableHost` 在单进程时只用 DCHECK 检查浏览器上下文是否一致。无痕模式要用第二个浏览器上下文：模拟器配置开着 DCHECK，一打开无痕标签页就崩；真机配置不开 DCHECK，推测无痕标签页会和普通标签页共用同一个渲染器进程和绑在它上面的存储（没在真机上试）。补丁 0016 把无痕模式当成被策略停用。要恢复无痕，得有多进程（BrowserEngineKit 权限，侧载拿不到）或者大改 content。

17. **编辑菜单依赖 UIKit 的内部行为。**（2026-10-27，补丁 0019，在 iOS 27 模拟器里观察到的。）系统编辑菜单里"查询""翻译"用的是 UIKit 的私有动作（`_define:`、`_translate:`），0019 按名字把它们换成 BrowserEngineKit 的公开动作；`refreshKeyboardUI` 会顺带关掉菜单，0019 刷新后再弹出来；UIKit 把选区换算成"文档里的偏移"再换回来，0019 让选区充当整篇文档。这些都不是文档写明的行为，以后的 iOS 版本可能变。推测最坏是菜单少几项、闪一下或者拖柄不显示，不会崩溃。
18. **页内查找和光标、选区颜色依赖 UIKit 的行为和取值。**（2026-10-28，补丁 0022、0023，在 iOS 27 模拟器里观察到的。）系统查找栏每次搜索后立刻调一次"下一个"，0022 靠这一下选中第一个匹配；以后不调的话，新搜索只会高亮，没有当前项。0023 把系统蓝写成了常量（iOS 26 的值），iOS 改了系统蓝的话，Blink 画的选区和光标会和系统画的拖柄差一点。这些都不是文档写明的，推测最坏是查找时没有当前项、颜色略有差别，不会崩溃。
19. **空输入框粘贴依赖 UIKit 的行为。**（2026-10-28，补丁 0025，在 iOS 27 模拟器里观察到的。）只有光标时让系统的选区显示保持激活、换上不画东西的光标视图（`cursorView` 是公开接口），菜单才弹得出来；点光标弹菜单是自己做的，Blink 处理完点按后等 150 毫秒看光标有没有动，真机很慢时，光标的更新晚于 150 毫秒到达，菜单可能先弹出、随即被刷新收起（推测）。

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
- 2026-10-27（真机，用户测试）：Release 1 的 IPA 装到 iPhone 13 mini（iOS 27）上：**网页能显示**，但①发热严重，②有点卡，③网页不用系统字体了（SF Pro / SF Mono）。接下来在模拟器里查这几个问题（用户同意自己下载测试工具），最后修 DrumBrake。
- 2026-10-27（Mac）：装了模拟器自动化工具 **AXe**（`brew trust --formula cameroncooke/axe/axe` 后 `brew install`，预编译二进制，配合 `DEVELOPER_DIR` 可用，不用改 `xcode-select`），能在无窗口模拟器上点击、输入、读界面结构、截图。用 iOS 27.0 运行时建了 iPhone 13 mini 模拟器。问题 3（字体）：测试页确认 `system-ui`、`-apple-system`、`BlinkMacSystemFont`、`ui-monospace` 都退回 Times；补丁 0005 修好后与 Safari 并排比较，字距相差 1% 以内。问题 5（错误页）：占位实现在 `ios_content_renderer_client.cc`；补丁 0006 后主页面出错显示正版"无法访问此网站"页，失败的 iframe 为空白。测试时还撞到一个上游崩溃：开着无障碍（AXe 用的就是无障碍接口）时打开出错页面，`-[RenderWidgetUIView accessibilityElements]` 的 WeakPtr CHECK 崩溃，补丁 0007 修好。问题 1、2：静止页面 CPU 0.1%，GPU 光栅化默认开着。0001–0007 从头打上后，开始编真机版。
- 2026-10-27（Mac）：0001–0007 的真机版编译通过，打包后发布为 Release `chromium-158.0.8127.0-sideload-2`（公开，预发布，标签指向提交 `aa05242`，IPA 的 SHA-256 是 `2a4f1c4c…336f86dfb`）。
- 2026-10-27（Mac）：按用户要求查滚动条、Passkey、DrumBrake。滚动条和 Passkey 的结论见"真机反馈的问题"第 4、6 条（用户决定 Passkey 不做，滚动条暂缓）。**DrumBrake**：上游 V8 main 当天的三个解释器文件和固定版本完全一样，也编不过（验证过），所以自己修：新增 V8 补丁 0201（`patches/v8/`，打在 `src/v8` 上），把 `TrustedManaged::raw()` 改成 `unsafe_raw()` / `raw(no_gc)`，把 25 处用在普通堆对象上的 `TrustedCast<>` 改成 `Cast<>`，做法和上游别处一致（细节见 architecture.md）。读源码还发现两件事：① `--jitless` 只在 tvOS 上自动带上 `--wasm-jitless`，iPhone 上要自己传，否则仍然没有 `WebAssembly` 对象，所以 0001 加回了 `--wasm-jitless`（放在最后）；② iOS arm64 上 DrumBrake 默认不做显式边界检查，要靠 V8 的陷阱处理器，而 content 在 iOS 上默认不开它，DrumBrake 会在第一次实例化模块时 `CHECK` 崩溃，所以 `args/` 加了 `v8_drumbrake_bounds_checks = true`（还省掉每块 Wasm 内存 8 GB 的地址空间预留）。对照了 Blinker Fluid 的 wasm 类改动，都不用移植（见 patch-triage.md）。
- 2026-10-27（Mac）：用户想要网页翻译。读源码发现 Chromium 版翻译被几处挡着：没有 API key 时 `TranslateManager` 直接不提供翻译（但 Google 翻译组件请求时用的是它脚本里自带的 key，下载当时的脚本确认过，所以可以放开）；Blink 版 ios/web 默认根本不注入 Chrome 的网页脚本（`kContentEnableInjectedFeatureScripts` 默认关），而且上游这条 JS 桥只写了一半（`JavaScriptFeature` 的调用在 Blink 下直接返回 false，`ContentWebFrame` 的调用格式也过时了）。新增补丁 0008：只为翻译放行语言检测和翻译两个功能的脚本，并把调用链接通（细节见 architecture.md）。另外发现 Blink 版网页请求不走系统代理设置（风险 15），模拟器里连不上 Google，翻译的最后一步（下载 Google 的翻译脚本）当时没法在模拟器里测；用户建议开代理软件的虚拟网卡模式，但用户不在电脑前，我没有改系统网络设置，后来用补丁 0009 解决（见下一条）。
- 2026-10-27（Mac）：模拟器里验证了新补丁（新编的 app，从头打补丁后编译，`02-apply-patches.sh` 的结果和开发分支逐字节一致）。**WebAssembly**：测试页 17 项全过（含两个用 clang 编成 wasm32 的 C 程序，结果和 Mac 原生编译的一致），`try_table` 模块报 `CompileError`。**翻译**：先是看不到翻译提示，在测试页里挂钩子查出 JS 桥是通的，提示其实出现了，只是几秒后自动收起；从提示或菜单翻译都正常。**系统代理**（新补丁 0009）：google.com、github.com 都能打开了。google.com 却是旧版基础页面，用 curl 比对出原因是 UA 里冻结的 `iPhone OS 14_0`，新补丁 0010 改成和 iOS 27 的 Safari 一样的 18_7 后显示完整页面。**滚动**：用记录触摸事件的测试页查出，Chrome 下拉刷新的手势会取消网页收到的触摸（touchstart 之后马上 touchcancel），新补丁 0011 修好，页面跟手、带惯性。另外应用户建议在 Chromium 里打开了用户的字体项目页面（GitHub，README 里的 SVG 样张正常），并用这个字体（更纱 Ui PD，可变字体）做了网页字体测试：字重轴、斜体、`pnum`/`tnum`/`zero`、按语言切换的标点都和预期一致；Blink 默认的 `text-spacing-trim` 已经会挤压标点，所以单独开 `chws` 看不出差别；竖排时超过一组的连续破折号（四个 `—`、`⸻⸻`、斜体的 `——⸺`）在接缝处断开，Safari 也一样，强开 `curs`/`calt` 无效，应是字体这边的问题，已告诉用户。
- 2026-10-27（Mac）：真机版带 DrumBrake 重编（13:25–14:04，V8 整个重编，没有错误），再增量编进 0010、0011（1 分钟，检查过二进制里已是 `iPhone OS 18_7`、带 `--wasm-jitless`）。`05-package-ipa.sh` 打包出 `dist/Chromium-158.0.8127.0-sideload-3.ipa`（后来又增量编进 0012 重新打包：148.5 MB，SHA-256 `8a367c9aa5b4d1f2265a7afda128fe6caee7f5000fade985beb6e1450146e18c`）。模拟器里 app 加载几个网页后的内存占用约 200 MB（`footprint`，峰值 215 MB）。
- 2026-10-27（Mac）：用户反映网页滑不到底。复现：测试页滚到头 `scrollY` 比最大值少 108 px，最后一个元素在底部工具栏下面。原因是 Blink 版把工具栏写死的可收起高度（顶部 30、底部 78 pt）当浏览器控件报给 Blink，而 Chrome 的工具栏收起逻辑只处理"正在拖动"的滚动，Blink 下永远不触发。补丁 0012 改成报 0，验证过能滚到底、顶部不受影响。接着按用户要求查下载：四种方式都没反应，原因是 Blink 版没有下载管理委托（见"真机反馈的问题"第 12 条）。
- 2026-10-27（Mac）：用户问补丁能否适配不同的工具栏位置。模拟器里把地址栏移到底部（长按地址栏）后重测：顶部不被挡，能滑到底（验证过）。"隐藏工具栏"时 Chrome 会缩小插入值、网页区域随之变大；滚到页面底部时 Chrome 会自动重新显示工具栏，最后一截照样露得出来。测试中一度以为底部地址栏点不动，临时编了记录命中视图的调试版才查明是 AXe 的坐标问题（见 build-guide.md 的 AXe 一节），调试代码已撤掉。测下载时看到的 `URL.createObjectURL is not a function` 也是测试页写法的问题（`onclick` 属性里 `URL` 指向 `document.URL`），不是 Blink 的问题。
- 2026-10-27（Mac）：做下载（用户要求先做下载再发布）。新增补丁 0013：Blink 版没有下载委托，content 把每个下载都取消了；补丁把 content 的下载包装成 Chrome 的 `web::DownloadTask`，交给 Chrome 的下载栏（细节见 architecture.md）。模拟器里测了 zip 链接、`download` 属性、PDF、页面生成的 blob：下载栏正常，下载后 Documents 里的文件和原文件 SHA-256 一致；用一个限速的本地服务器（约 100 KB/s）测了下载前关掉下载栏、中途停止、下载中关掉标签页，服务器那边都看到连接在同一秒断开，临时目录里不留文件。测试中发现并处理了三个问题：①PDF 下载完点"打开"会新开标签页、再下载一次（Blink 没有 PDF 查看器），0013 里改成只给"打开方式…"；②接着测快捷键时发现，焦点在网页上时按 Chrome 的快捷键或 Cmd+C 会闪退（上游 `RenderWidgetUIView` 对所有动作都说能处理），新增补丁 0014；③修好快捷键后，Cmd+Shift+N 打开无痕标签页又崩在单进程的 DCHECK 上（风险 16），新增补丁 0016 停用无痕模式。用户中途要求把编辑菜单加上，新增补丁 0015：长按文字时 Blink 会要上下文菜单，原来只有链接和图片才有菜单，现在对文字弹出系统编辑菜单。四个补丁的测试结果见"真机反馈的问题"第 12–15 条。另外按用户要求把模拟器里测试时攒下的四十多个标签页全关了，之后在同一个标签页里跳转。补丁核对：在临时索引里从 `4558926c` 按 `series` 依次打上 0001–0016，得到的树和开发分支完全一致（没有重跑 `02-apply-patches.sh`，免得刷新文件时间戳引起重编）；重新导出时 0001、0004–0012 逐字节不变，0002、0003 是早期手写的，格式不同、内容等价，没有替换。真机版增量编进 0013–0016（1 分钟，没有错误），重新打包 `dist/Chromium-158.0.8127.0-sideload-3.ipa`（148.5 MB，SHA-256 `4f3f8e90b03df9fb3076438f5a43cd6d60235ffffe46fdf647063a72a77649b4`），替换了之前那个只到 0012、还没发布的包。
- 2026-10-27（Mac）：用户确认发布。本仓库推送后，发布为 Release `chromium-158.0.8127.0-sideload-3`（公开，预发布，标签指向提交 `7f28b7d`，含补丁 0001–0016 和 V8 补丁 0201，IPA 的 SHA-256 是 `4f3f8e90…49b4`；从 GitHub 下载回来核对过，和本地一致）。
- 2026-10-27（Mac）：用户在真机上测 Release 3，报了两个问题。①用屏幕键盘在输入框里打字，每输一个字网页就往下移。模拟器一直认为接着实体键盘（AXe 打字发的是实体键盘事件），屏幕键盘不出来；把模拟器设备里的 `HardwareKeyboardLastSeen`、`AutomaticMinimizationEnabled` 设成 NO 并重启模拟器后，用拼音屏幕键盘复现了，原因和修法见补丁 0017（"真机反馈的问题"第 16 条）。②关掉 Shadowrocket 后网页报错，见第 17 条。内置的模拟器工具要求 `xcode-select` 指向完整 Xcode，按约定不改，所以继续用 AXe。用户还问到滚动时自动收起工具栏：Chrome 的收起逻辑只认真实的拖动，有简单做法（把 Blink 转发的拖动当真，收起时网页要改尺寸，可能闪白边、跳动）和 Android 式做法（Blink 管收起进度，Chrome 的工具栏跟随，工作量大），用户决定先不做；手动隐藏可用（长按地址栏 →"隐藏工具栏"，点顶部细条恢复，模拟器验证过）。真机版增量编进 0017（没有错误），打包 `dist/Chromium-158.0.8127.0-sideload-4.ipa`（148.5 MB，SHA-256 `ce0566d6002ff394fa7641fde6d23cddc59d3640b25a111d650b368fbd45c584`），还没发布（后来又编进 0018 重新打包，见下一条）。
- 2026-10-27（Mac）：用户问正版 Chrome 怎么跟随代理（iOS 版网页走 WKWebView，由系统处理；Android 版监听系统的 `PROXY_CHANGE` 广播；Chromium 在 iOS 上只能轮询），要求改成监听系统网络变化通知：补丁 0018。第一版在构造函数里登记，临时测试版里撞上了轮询服务的线程检查（有的实例在 UI 线程创建、在 IO 线程使用），改成第一次 `AddObserver` 时登记后验证通过（细节见 architecture.md）；真机上开关 Shadowrocket 的效果待用户确认。用户还问上游进展：用 GitHub 上的 Chromium 镜像查（googlesource 的历史页现在要登录），从固定版本到 10 月 27 日的主线，iOS Blink 相关代码和我们补丁碰过的文件都没有新提交，只有两处无关的重构；上游这半年大约每月有几个 "[ios blink]" 修复（最近的 10 月 23 日修 `document.hasFocus()`、10 月 26 日键盘和焦点解耦，都已在固定版本里），我们修的这些问题上游都还没修。所以建议暂不升级（用户问是否要拉到最新），等上游出了对我们有用的修复再升。真机版增量编进 0018，重新打包 `dist/Chromium-158.0.8127.0-sideload-4.ipa`（148.5 MB，SHA-256 `cc6e1df8e8d77af3068a00e0cb96302a0a589fbdacefab31da0d50539120b82f`，含 0001–0018 和 V8 0201），还没发布。
- 2026-10-27（Mac）：用户确认发布。本仓库推送后，发布为 Release `chromium-158.0.8127.0-sideload-4`（公开，预发布，标签指向提交 `9f27c02`，含补丁 0001–0018 和 V8 补丁 0201，IPA 的 SHA-256 是 `cc6e1df8…b82f`；从 GitHub 下载回来核对过，和本地一致）。
- 2026-10-27（Mac）：用户在真机上又提了三个问题：长按后的选择菜单难用（希望和 Safari 一致）、深色模式不可用、屏幕键盘会缩短页面布局（和 Liquid Glass 冲突，网页卡来卡去）。三个都在模拟器里复现并修好，见"真机反馈的问题"第 18–20 条：新补丁 0019（文本选择）、0020（键盘）、0021（深色模式），0015 改成弹系统菜单（按第 7 节的流程合进原提交并重新导出，0016–0018 导出后逐字节不变）。查选区问题时用 lldb 附加到模拟器里的 app，直接看视图层级、调 UIKit 内部方法，比反复加日志重编快得多（方法记在 build-guide.md）；只在 Release 版里打断点不好用，相同代码的函数被合并了，断点会命中一堆无关函数。键盘那条一度以为"输入框滚不到键盘上方"是时序问题没解决，其实是测试页只记了页面滚动、没记可视视口滚动，看截图才发现；随后在 Blink 和 cc 里加临时日志，确认了真正的时序问题（滚动请求比新的可视区域先到），改成等新帧激活后再请求。0001–0021 在临时索引里从头打上，和开发分支的代码树一致（验证过）。用户还问网页查找为什么是灰色的，见第 21 条。
- 2026-10-27（Mac）：0001–0021 的真机版增量编译通过（21:44–21:54，没有错误），打包出 `dist/Chromium-158.0.8127.0-sideload-5.ipa`（148.5 MB，SHA-256 `01266f44…0a56`），检查过二进制里有 0019–0021 的代码、没有调试日志。还没发布。
- 2026-10-27（Mac）：用户确认发布。本仓库推送后，发布为 Release `chromium-158.0.8127.0-sideload-5`（公开，预发布，标签指向提交 `ec89467`，含补丁 0001–0021 和 V8 补丁 0201，IPA 的 SHA-256 是 `01266f44…0a56`；从 GitHub 下载回来核对过，和本地一致）。
- 2026-10-27（Mac）：用户问页内查找难不难做，要求做出来并在模拟器里验证。新增补丁 0022：给 Blink 版网页视图装上 WKWebView 用的同一种系统查找栏（`UIFindInteraction`），用一个自定义的查找会话把搜索交给 content 的 `WebContents::Find`，Blink 的结果（第几个 / 共几个）再交回查找栏（细节见 architecture.md）。模拟器里验证过："apple" 在测试页上是 1/5，五处都高亮、第一个为当前；上一个、下一个逐个滚到对应位置，5/5 之后回到 1/5；区分大小写后是 1/4；搜不到时显示 0；拼音输入的"狐狸"能找到；用英文键盘和拼音键盘的结果都和 Safari 一致；关闭后高亮清除，再打开也正常。测试时一度看到 2/5（停在第二个），以为是查找栏搜索后会自动"下一个"，改成新搜索只计数，结果用英文键盘打字时计数和高亮对不上；用户指出自己手机上不会跳到第二个，和同一台模拟器里的 Safari 对照才查明：只有用拼音键盘打英文单词、再点候选栏里同样的词上屏时才会这样（上屏前后搜索词没变，查找栏当成"下一个"），Safari 也一样，于是改回第一版。查找栏选项里的"全字匹配"Blink 做不到，去掉了。0001–0022 在临时索引里从头打上，和开发分支的代码树一致（验证过）。
- 2026-10-27（Mac）：0001–0022 的真机版增量编译通过（改回第一版后又编了一次，23:03 完成），本地打包出 `dist/Chromium-158.0.8127.0-sideload-6.ipa`（148.5 MB，SHA-256 `56bfc0f2…bea3`），检查过二进制里有 0022 的代码、没有调试日志。还没发布。
- 2026-10-27（Mac）：用户确认发布。本仓库推送后，发布为 Release `chromium-158.0.8127.0-sideload-6`（公开，预发布，标签指向提交 `34cd696`，含补丁 0001–0022 和 V8 补丁 0201，IPA 的 SHA-256 是 `56bfc0f2…bea3`；从 GitHub 下载回来核对过，和本地一致）。
- 2026-10-28（Mac）：用户在真机上（Release 6）发现页内查找的起点和 Safari 不一样，选区拖柄和选区的颜色也不对。在模拟器里对照 Safari 查清：有 6 处匹配、停在第 3 处的长页面上打 apple，Safari 是 1/6 并跳回第 1 处，这里是 5/6。用 lldb 跟踪，系统查找栏每次搜索后会自己调一次"下一个"，而第一版新搜索时自己也选中一个，Blink 又从上一次的当前项接着找，每个字母往后挪一格。改成新搜索先 `StopFinding` 清掉当前项、只计数和高亮（`find_match = false`），由那次"下一个"选中第一个，并进补丁 0022。之前说"Safari 用拼音上屏也是 2/5"是错的，Safari 也是 1/6，文档和提交说明已更正。重测（验证过）：1/6 并跳回第 1 处，拼音上屏也是 1/6；上一个、下一个和两头回绕；区分大小写 1/5→1/4；搜不到显示 0；中文能找到。
- 2026-10-28（Mac）：新增补丁 0023：拖柄、选区、光标统一成系统蓝（拖柄原来是写死的纯蓝，选区是安卓的青色，选中的字被改成黑色，光标是 1 pt 宽、和文字同色的竖线）。选区 20% 不透明、字保持原色，光标 2 pt 宽，页面设了 `caret-color` 时听页面的。模拟器里和 Safari 取色一致（验证过）：选区 (197, 232, 255)、拖柄 (0, 139, 255)，深色模式也对。0001–0023 在临时索引里从头打上，和开发分支的代码树一致（验证过）。
- 2026-10-28（Mac）：0001–0023 的真机版增量编译通过（00:25 完成），本地打包出 `dist/Chromium-158.0.8127.0-sideload.ipa`（148.5 MB，SHA-256 `a4a598ee…5c88`）。还没发布：用户说这次不开新 tag（没有新功能），怎么更新测试版 6 待用户确认。
- 2026-10-28（Mac）：用户确认更新测试版 6（不开新 tag）。本仓库推送后，把标签 `chromium-158.0.8127.0-sideload-6` 从 `34cd696` 原地移到 `82cb4da`（含补丁 0001–0023 和 V8 补丁 0201，发布仍是公开的预发布版），用新包替换发布里的 IPA（文件名不变，SHA-256 `a4a598ee…5c88`），说明里加上这次的两项修正；从 GitHub 下载回来核对过，和本地一致。本地的旧包改名为 `dist/Chromium-158.0.8127.0-sideload-6-34cd696.ipa`。
- 2026-10-28（Mac）：用户在真机上报了三个问题：切换到电脑模式不可用、空文本框粘贴不可用、网页请求不了位置和剪贴板等权限。模拟器里都复现了（菜单项点了不重新加载；空输入框长按、再点都不弹菜单；`permissions.query` 全是 denied，定位直接报"User denied Geolocation"，连写剪贴板也被拒）。读源码查清原因后加了三个补丁：0024 请求桌面版网站（照安卓版 Chrome 换成 Mac 版 Chrome 的 UA 并按原始网址重新加载），0025 只有光标时也能弹编辑菜单（激活系统的选区显示、换上不画东西的光标、自己处理"点光标"），0026 网站权限（新的权限委托：写剪贴板允许，定位、读剪贴板弹提示；摄像头、麦克风用 Chrome 现成的提示；补上 Core Location 需要的系统定位权限管理器）。模拟器里逐项验证过，细节见 architecture.md。0001–0026 在临时索引里从头打上，和开发分支的代码树一致（验证过）。
- 2026-10-28（Mac）：0001–0026 的真机版增量编译通过（23:31 完成），还没打包发布。
