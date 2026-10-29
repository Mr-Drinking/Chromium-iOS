# 结构与补丁说明

以下路径都相对于 Chromium 的 `src/`。分析是在 `d586be9f`（158.0.8125.0）上做的；固定版本后来升到 `4558926c`（158.0.8127.0）。两者之间，补丁涉及的文件只有 `content/browser/renderer_host/render_widget_host_view_ios.{h,mm}` 有变化：上游新加了一个和补丁无关的 `ClearFocusedElement()`（验证过）。2026-10-29 再升到 `3313f827`（159.0.8129.0）：补丁内容都没变，只有 0023 要重新对上几行上下文：上游 2026-10-27 让竖线光标的宽度不受元素变换影响（`623986716f`），在 `caret_display_item_client.cc` 开头加了几个 include；V8 补丁 0201 上游已经修好，删掉了（见第 3 节；验证过）。

## 1. Chrome iOS 怎么换成 Blink 内核

```
ios/chrome/…            Chrome 的界面：标签页网格、地址栏、菜单、设置……（不改）
   │  只通过 ios/web 的公开接口（WebState 等）访问网页
ios/web/public/…        接口
   ├─ 默认：ios/web/web_state/…  用 WKWebView（WebKit）实现
   └─ use_blink=true：ios/web/content/…  ContentWebState 等，用 content API 实现
content/…               Chromium 的 content 层（多进程架构、导航、渲染宿主）
third_party/blink, v8   Blink 渲染引擎、V8
```

- `use_blink` 在 `ios/web/web_state/BUILD.gn` 里加上 `//ios/web/content` 依赖，在 `ios/web/init/BUILD.gn` 里加上 `//ios/web/content/init`。
- `ios/web/content/SECURITY.md` 写明这是原型、没有发布给用户（"This code is *not* currently shipped to users"）。
- 官方文档：`use_blink = true` 时支持的目标里，`content_shell` 和 `chrome` 最有用；tvOS 只支持 `content_shell`。

### 启动路径

```
IOSChromeMain()                       ios/chrome/app/startup/ios_chrome_main.mm
  └ web::WebMain / WebMainRunnerImpl   ios/web/init/web_main_runner_impl.mm
     └ IOSContentMainRunner::Startup   ios/web/content/init/ios_content_main_runner.cc
        └ content::RunContentProcess   content/app/content_main.cc   ← 补丁 0001 在这里
           └ ContentMainRunnerImpl     content/app/content_main_runner_impl.cc
```

`content_main.cc` 的 iOS 段落本来就会给 tvOS 加 `--single-process`（"Set tvOS to single-process mode by default"）。补丁 0001 在同一位置给 iPhone 加上我们的参数，所以 `content_shell` 和 Chrome 两个目标都生效，不用碰 Chrome 的启动代码。

`ContentMainRunnerImpl` 总会注册进程内的 renderer / GPU / utility 线程工厂（`RegisterMainThreadFactories()`），所以 `--single-process` 在 iOS 上本身就能工作，tvOS 就是这么跑的。

## 2. 官方多进程方案为什么用不了

- 官方 iOS（非 tvOS）用 BrowserEngineKit：`content/browser/child_process_launcher_helper_ios.mm` 通过 `BEWebContentProcess`、`BENetworkingProcess`、`BERenderingProcess` 拉起扩展进程。
- Blink 版 Chrome 的权限模板 `content/app/ios/appex/app.entitlements` 里有 `com.apple.developer.web-browser-engine.host` 和 `com.apple.developer.web-browser`。这些需要 Apple 审批，只发给欧盟/日本的浏览器厂商，侧载签名不可能带上。
- GPU 画面的跨进程交接：GPU 进程把根 `CALayer` 包进 `BELayerHierarchy`，通过 XPC 把句柄传给浏览器进程，后者用 `BELayerHierarchyHostingView`（即 `CALayerFrameSinkProvider` 的父类）显示。
- 另外，`ios/chrome/app/BUILD.gn` 在 `use_blink` 时只加了权限文件，没有像 `content/shell/BUILD.gn` 那样打包三个扩展进程。所以官方 Chrome+Blink 很可能本来就跑不起多进程（待验证，见 status.md 第 3 条）。

## 3. 补丁做了什么

### 0001 单进程 + 免 JIT 启动参数（`content/app/content_main.cc`）

在 iOS（非 tvOS）上追加：

| 参数 | 作用 |
|---|---|
| `--single-process` | 渲染、GPU、网络都在本进程的线程里跑，不需要扩展进程 |
| `--js-flags=--jitless --max-old-space-size=… --max-semi-space-size=… --wasm-jitless` | V8 不生成机器码；堆上限按内存分档，4 GB 机型是 384/16 MB（沿用 Blinker Fluid 的实测值）。`--wasm-jitless` 让 WebAssembly 在 DrumBrake 解释器里跑：免 JIT 时，V8 只有带上它才提供 `WebAssembly` 对象（`v8/src/wasm/wasm-js.cc`）。tvOS 上 `--jitless` 会自动带上它，iPhone 上不会（`flag-definitions.h` 里这条蕴含只在 `V8_OS_TVOS` 下成立）。它放在最后：没编 DrumBrake 的构建不接受它，而 V8 遇到出错的参数会忽略后面的全部参数，堆上限就没了 |
| `--disable-gpu-watchdog` | 单进程里 GPU 看门狗杀掉慢线程等于杀掉整个 app |
| `--force-gpu-mem-available-mb=384`（4 GB 机型） | 限制图块缓存，避免重网页把进程推过 jetsam 上限 |
| `--enable-features=WebContentsDiscard` | 允许丢弃后台标签页 |
| `--disable-features=avfoundation-overlays,BackForwardCache,NetTaskScheduler` | 原生视频层要额外修复才能在进程内图层树里正常显示；前进后退缓存会把整页留在内存里。NetTaskScheduler 见下 |

**为什么关 NetTaskScheduler**（2026-10-27 在模拟器里踩到，验证过）：单进程时，content 的网络服务跑在进程内的专用线程上，它的 `NetTaskScheduler` 会把这个线程的调度队列装成全进程共用的 `net::GetTaskRunner()`（`net/base/scheduler/net_task_scheduler.cc`）。但 Chrome iOS 自己的 ios/web 层还有一个 `NetworkContext` 跑在 IO 线程上（`ios/web/network_context_owner.cc`，地址栏建议、新标签页都走它），它创建的 `URLLoader` 会拿到专用线程的 runner。开着 DCHECK 时，启动后约 1 秒就崩在 `mojo::SimpleWatcher` 的断言上；关着 DCHECK 也是真实的线程错配。官方是多进程，网络服务在单独的进程里，所以碰不到。关掉这个 feature 后，每个 `URLLoader` 都用自己所在线程的 runner，这是上游支持的回退路径（`net/base/task/task_runner.cc`）。

已有的同名参数不会被覆盖（`--js-flags`、`--force-gpu-mem-available-mb` 已存在则跳过，feature 列表是追加）。

### 0002 进程内显示 GPU 画面

- `ui/accelerated_widget_mac/ca_layer_frame_sink_provider.{h,mm}`：iOS 上 `CALayerFrameSinkProvider` 改为继承普通 `UIView`（tvOS 本来就是这样），新增 `-attachContentLayer:`，把 GPU 的根图层加为子图层，并在 `layoutSubviews` 里保持铺满。
- `gpu/ipc/service/image_transport_surface_overlay_mac.mm`：不再创建 `BELayerHierarchy`，而是在主线程按 surface handle 找到对应的 provider，直接 `attachContentLayer:`。
- `content/browser/renderer_host/render_widget_host_view_ios.{h,mm}` + `ui/accelerated_widget_mac/BUILD.gn`：iPhone 也编译 `DisplayCALayerTree`，`UpdateCALayerTree()` 收到的 `CALayerParams` 交给它显示（tvOS 的做法；官方 iOS 版这里是空函数）。
- `content/browser/child_process_launcher_helper_ios.mm`：多进程交接代码里对 `handle` 属性的赋值去掉（父类换了，这个属性不存在了；单进程下这段代码本来也不会执行）。

### 0003 GPU 初始化前等 Metal（`content/gpu/…`）

ANGLE 只在 GL 初始化时要一次 Metal 设备，拿到 nil 就整个进程都没有 GL、网页画不出来。进程内 GPU 线程可能在 app 第一个 scene 连接前就启动，所以先最多等 2 秒（新文件 `ios_sideload_metal_wait.{h,mm}`）。

### 0004 允许不带任何 app 扩展（`ios/chrome/app/BUILD.gn`）

纯构建修复，不改运行时代码。`_extension_toolchain` 总会被赋值，但只在各个 `ios_enable_*_extension` 分支里用到。`args/` 把这些扩展全关了（见第 4 节），GN 就报 "Assignment had no effect"，连 `gn gen` 都过不去。补丁加了一行 `not_needed([ "_extension_toolchain" ])`。验证过：没有它 `gn gen` 失败，有了它模拟器和真机两套参数都能生成。

### 0005 网页用系统字体（Blink 字体代码）

Blink 的 iOS 版字体代码只有一个很薄的 `fonts/ios/font_cache_ios.mm`：`system-ui` 在 `FontCache::GetFontPlatformData()` 里被转去 `SystemFontPlatformData()`，而 iOS 上那里没有字体名可用，直接返回空，于是回退成 Times；`BlinkMacSystemFont` 的映射只写在 Mac 专用的代码里；`-apple-system`、`ui-monospace` 这些 Safari 认的写法 Blink 本来就不认。结果网页全都不是系统字体（用户在真机上发现，模拟器里验证过）。

补丁让 iOS 像 Mac 一样把 `system-ui` 当普通字体名创建和缓存，并在 Skia 的 `CreateTypeface()` 里加了 iOS 分支（`MakeIOSSystemFontTypeface()`）：`system-ui`、`ui-sans-serif` → SF Pro，`ui-serif` → New York，`ui-monospace` → SF Mono，`ui-rounded` → SF Rounded，带字重和斜体。用的是 UIKit 的 `UIFontDescriptor` 设计变体，因为 CoreText 的等宽 UI 字体是 Menlo 而不是 SF Mono（在模拟器里实测过）。还要把 SF 的 `opsz` 轴设成字号：Blink 用 HarfBuzz 排字，不设的话会用默认值 28，正文比 Safari 紧约 7%。设了以后与 Safari 的差距在 1% 以内（验证过）。CSS 解析那边把 `-apple-system` 和 `BlinkMacSystemFont` 都当成 `system-ui`，跟 Safari 一样。

### 0006 网络错误页（`ios/web/content/init/ios_content_renderer_client.cc`）

Blink 版 ios/web 的 `PrepareErrorPage()` 是占位实现，任何加载失败都只返回一行 "This is an error page"。网页里被拦掉的广告、统计 iframe 很多，所以用户会"莫名其妙"看到这行 Times 小字。补丁对主页面按 `ios/chrome/browser/web/model/error_page_util.mm`（WebKit 版 Chrome 的做法）生成正版错误页：`error_page::LocalizedError::GetPageState()` 加 `IDR_NET_ERROR_HTML` 模板；子框架则返回空文档，跟 Safari 一样。

### 0007 无障碍查询已销毁的视图时崩溃（上游 bug）

`-[RenderWidgetUIView accessibilityElements]` 没检查弱指针就解引用。导航换掉 `RenderWidgetHostViewIOS` 之后，UIAccessibility 还可能在主队列上回头查询旧的 UIView，于是 WeakPtr 的 `CHECK` 让整个 app 崩溃。只要无障碍功能处于激活状态（VoiceOver、语音控制、UI 自动化）就会碰到。2026-10-27 用 AXe 测试时复现并修好了。

### 0008 让翻译可用（`components/translate/…`、`ios/web/content/js_messaging/…`）

Chromium 版的翻译被三道关卡挡着：

1. **API key。** `TranslateManager` 在构建没有 Google API key 时不提供翻译（`google_apis::HasAPIKeyConfigured()`，三处检查），所以连翻译按钮都没有。但翻译本身用不着这个 key：Chrome 注入网页的 Google 翻译组件（`translate.googleapis.com/translate_a/element.js` 和它再加载的主脚本）请求 `translate-pa.googleapis.com/v1/translateHtml` 时，带的是脚本里写死的 key，不是 Chrome 传进去的那个（2026-10-27 下载当时的脚本确认过）。三处检查都看同一个静态开关 `ignore_missing_key_for_testing_`，补丁把它的默认值改成 `true`。
2. **网页脚本。** Blink 版 ios/web 只有打开 `kContentEnableInjectedFeatureScripts` 才注入 Chrome 的网页脚本（JavaScriptFeature），这个开关默认关着，所以既不检测网页语言，也没有翻译脚本。整个打开会注入 30 多个功能的脚本（自动填充、密码等），在 ios/web/content 里它们都跑在网页自己的 JS 环境里，免 JIT 时每次加载网页都要多花时间，安全上也不理想。补丁只放行翻译要用的：语言检测、翻译，加上它们依赖的 gCrWeb 基础脚本和 `window.webkit.messageHandlers` 转发脚本（`content_web_frames_manager.mm` 里的 `IsInjectedWithoutFlag()`）；`ContentWebFrame` 允许调用这两个功能的 JS 函数；`__gCrWeb.frameId` 总是设置，因为它们发回的消息靠它找到发送的框架。
3. **调用链没接通。** 上游 Blink 版的 JS 桥只写了一半：`JavaScriptFeature::CallJavaScriptFunction()` 和 `ExecuteJavaScript()` 在 Blink 下直接返回 false（`ios/web/js_messaging/java_script_feature.mm` 里的 TODO，crbug.com/40254930）；`ContentWebFrame` 还按 `__gCrWeb.<api>.<函数>()` 调用网页里的函数，但 gCrWeb 现在把注册的 API 放在私有表里，这种写法已经调不到了（`ios/web/public/js_messaging/resources/gcrweb.ts`）。补丁让前两者转给网页框架，调用格式改成和 WebKit 版（`ios/web/js_messaging/web_frame_impl.mm`）一样走 `__gCrWeb.callFunctionInGcrWeb()`。也就是说，即使打开上面那个开关，上游 Blink 版的网页脚本调用其实也都不通。

语言检测不需要联网：TFLite 模型下载不到时，iOS 会退回内置的检测方法（`ios_language_detection_tab_helper.mm`）。

模拟器里验证过（配合 0009 让模拟器连上 Google）：打开德语网页会弹出"翻译网页吗？从德语到简体中文"，从提示或菜单里翻译后正文变成中文。在测试页里挂钩子看到的调用顺序：原生调用 `languageDetection.detectLanguage()` → 网页发回 `LanguageDetectionTextCaptured` → 原生调用 `retrieveBufferedTextContent()` 取回正文。副作用：转发脚本让任何名字的 `window.webkit.messageHandlers.xxx` 都"存在"，有的网页会据此发消息，日志里会出现 `No message handler for youtubewebview` 之类，没有害处。

### 0009 网页请求走系统代理设置（`services/network/network_context.cc`）

Blink 版的网页请求走 content 的网络服务，而 ios/web 从不给它传代理设置，`NetworkContext` 就退回直连。结果 iOS 里给 Wi-Fi 配的 HTTP 代理、PAC 对网页都无效，Safari 和 WebKit 版 Chrome 却都认；模拟器里也一样，Mac 的系统代理不起作用（2026-10-27 实测：模拟器里 Safari 能经 Mac 的代理打开 google.com，Chromium 打不开 google.com 和 github.com）。补丁在 iOS 上、嵌入方没给代理设置时，改用 `net::ProxyConfigService::CreateSystemProxyConfigService()`（即 `ProxyConfigServiceIOS`）读系统设置，`URLRequestContextBuilder` 随后用系统的解析器处理 PAC。Clash 等 VPN 型代理本来就不受影响。模拟器里验证过：Mac 设了系统代理后，google.com、github.com 都能打开（之前都卡住）。

### 0010 UA 里的 iOS 版本（`components/embedder_support/user_agent_utils.cc`）

上游的精简 UA 把 iOS 版本冻结在 `iPhone OS 14_0`，网站会当成过时的浏览器：google.com 对这个 UA 只给 32 KB 的基础版 HTML，同一个 UA 只把版本改成 18_7 就给 203 KB 的完整页面，Safari、Chrome iOS、Android Chrome 的 UA 也都是完整页面（2026-10-27 用 curl 对比过）。iOS 27 上 Safari 自己的 UA 冻结在 `iPhone OS 18_7`（模拟器里实测），补丁改成同样的值，iPad 同理。模拟器里验证过：改后 google.com 显示完整页面。

### 0011 下拉刷新的手势不再打断网页滚动（`ios/chrome/browser/overscroll_actions/ui_bundled/overscroll_actions_controller.mm`）

Chrome 的下拉动作（刷新、关闭标签页、新标签页）往网页的滚动视图上加了一个 `UIPanGestureRecognizer`。WebKit 下没问题，滚动视图用自己的手势滚动；Blink 下网页是靠收到的原始触摸自己滚动的，那个滚动视图只是镜像 Blink 的偏移。手势一识别（拖动几个点之后），UIKit 就按默认的 `cancelsTouchesInView` 取消这些触摸，Blink 收到 touchcancel，页面就不滚了。`RenderWidgetUIView` 换渲染视图时会把这个滚动视图上的手势全部移除，所以只是"有时候"滚不动，对应用户说的"有点卡"。补丁让 Blink 构建里这个手势不取消、不延迟触摸。下拉动作在 Blink 下本来就触发不了（镜像的偏移不会小于 0），没有损失。模拟器里验证过（记录触摸事件和 `scrollY` 的测试页）：之前拖 400 pt 只收到 touchstart 和 touchcancel，页面不动；之后页面跟手（手指移动 416 px，滚动 421 px），快速一划带惯性滚 955 px；在顶部往下拉也没有异常。

### 0012 不再告诉 Blink 工具栏能收起（`ios/web/content/web_state/content_web_state.mm`）

Blink 版照 Android 的做法，把 Chrome 顶部、底部工具栏能收起的高度当成"浏览器控件"报给 Blink（`GetTopControlsHeight()`、`GetBottomControlsHeight()`，取自 `CRCWebViewportContainerView` 里写死的插入值：顶部 109 - 79 = 30 pt，底部 78 pt）。Blink 于是让网页多滚这么一段，等着工具栏收起后露出来。但工具栏从来不收起：Chrome 的 `FullscreenMediator` 只处理滚动视图"正在被拖动或减速"时的滚动，而 Blink 下那个滚动视图只是程序设置偏移的镜像，`isDragging` 永远是 NO。结果每个网页最后 108 pt 都被底部工具栏挡着，滑不到底（用户在真机上发现）。补丁报 0，Blink 的最大滚动距离就和可见区域一致。工具栏还是一直显示；要让它们像正版那样滚动时收起，得把 Blink 的滚动接进 Chrome 的 fullscreen 逻辑，没做。模拟器里验证过：之前滚到头还差 108 px，最后一个元素在工具栏下面；之后能滚到底、完整露出，顶部也没被挡。

### 0013 下载（`ios/web/content/download/…`、`ios/web/download/download_controller_impl.mm` 等）

Blink 版的 `ContentBrowserContext::GetDownloadManagerDelegate()` 返回空。没有委托时，content 把下载的目标路径定为空（调用方强制指定了路径的除外），空路径就等于取消（`DownloadManagerImpl::DetermineDownloadTarget`），所以点下载链接什么都不发生。Chrome 的下载界面（下载栏、"打开方式…"、存到"文件"）是围着 `web::DownloadTask` 写的，WebKit 版的任务由 `DownloadTaskImpl` 和 `DownloadControllerImpl` 提供。补丁把 content 的下载桥接成 `web::DownloadTask`：

- `ContentDownloadManagerDelegate`（新）：content 来要下载目标时（`DetermineDownloadTarget`），先不回答，把 content 的 `DownloadItem` 和回调包进一个 `ContentDownloadTask`，通过 `DownloadControllerImpl` 新加的 `OnContentDownloadCreated()` 交给 Chrome，Chrome 再按 MIME 类型分给下载栏、PassKit、AR 预览等。找不到所属网页、或 Chrome 没有下载委托时，直接取消。下载 ID 自己编号（content shell 也是这么做的）。
- `ContentDownloadTask`（新，继承 `DownloadTaskImpl`）：用户点"下载"后，Chrome 在临时目录里给一个路径（`StartInternal(path)`），任务这时才把它作为目标交给 content（中间文件是同目录的 `.crdownload`），之后把 content 的进度、完成、取消、中断转成 Chrome 的状态。content 在用户点"下载"之前就开始收数据了，所以小文件往往一点就完成。用户关掉下载栏、点"停止"或关掉标签页时，任务被取消或销毁：还没定目标的，回一个空路径让 content 取消；已经在下的，调 `Cancel()`。content 中断的下载不能"重试"（重试要换个路径重新下，任务没实现）。
- 委托销毁时先从 content 的下载管理器上摘掉自己：`content::BrowserContext` 要等 `ContentBrowserContext` 的成员析构完才关闭下载管理器，那时还会调用委托的 `Shutdown()`。写法照 content shell。
- PDF：Chrome 对下载完的 PDF 提供"打开"，做法是在新标签页里加载这个 `file://` 文件，靠 WKWebView 显示。Blink 在 iOS 上没有 PDF 查看器，结果只是又下载一次（验证过），所以 Blink 构建里 PDF 也只给"打开方式…"（`download_manager_mediator.mm`）。

模拟器里验证过：zip 链接、带 `download` 属性的链接（显示属性给的文件名）、PDF 链接、页面用 Blob 生成的文件，都会弹出下载栏，下载后的文件在 app 的 Documents 里，SHA-256 和原文件一致；"打开方式…"弹出系统分享面板（能存到"文件"）。用限速的本地服务器测了下载前关掉下载栏、下载中途停止（Chrome 会先问"停止下载？"）、下载中关掉标签页，三种情况服务器都在同一秒看到连接断开，临时目录里不留文件。无痕模式下的下载没测（无痕被 0016 停用了）。

### 0014 网页视图只认领自己实现了的动作（`content/browser/renderer_host/render_widget_host_view_ios_uiview.mm`）

`RenderWidgetUIView` 的 `canPerformAction:withSender:` 对任何动作都返回 YES。UIKit 沿响应者链找动作的目标时，第一个说"能"的就是目标，于是焦点在网页上时，Chrome 的键盘快捷键（`keyCommand_openNewIncognitoTab` 等）和系统的拷贝（`copy:`）都发到了这个视图上。它没有这些方法，app 以 "unrecognized selector" 崩溃（接实体键盘时，验证过；三指捏合拷贝之类的编辑手势推测也会走到这里）。补丁改成只认领自己实现了的方法（`respondsToSelector:`），宿主 `RenderWidgetHostViewIOS` 已经销毁时一个都不认领（编辑命令会 CHECK 它）；再照上游已有的 `selectAll:`，把 `copy:`、`cut:`、`paste:` 实现成 Blink 的编辑命令。模拟器里验证过（接实体键盘）：输入框里 Cmd+A、Cmd+C 后，系统剪贴板里是输入框的文字，Cmd+V 能粘贴；Cmd+Shift+N 进到了 Chrome 的处理函数（接着撞上无痕的问题，见 0016）。

### 0015 文字的编辑菜单（`ios/web/content/ui/content_context_menu_controller.mm`）

长按网页文字时，Blink 选中一个词并请求上下文菜单（`ShowContextMenu`）。ios/web/content 只会把请求转给 Chrome，而 Chrome 只为链接和图片做菜单，所以文字什么菜单都没有，触屏上没法拷贝。补丁在请求里没有链接和图片、但有选中文字或来自输入框时，改为通过网页视图上 BrowserEngineKit 的文本交互（`BETextInteraction`）弹出系统的编辑菜单（`presentEditMenuForSelection`），也就是 Safari 用的那个；菜单里有哪些项、点了做什么，由网页视图决定（补丁 0019）。这个菜单不是 Blink 的上下文菜单，所以弹出后马上告诉 content 这次上下文菜单已经关闭。

（2026-10-27 重写。第一版自己建了一个 `UIEditMenuInteraction`，只有"拷贝 / 全选"，没有选区拖柄，菜单经常压在地址栏上。用户在真机上觉得难用，要和 Safari 一致，于是改成用系统文本交互的菜单，配合 0019。）

模拟器里验证过（和 0019 一起）：长按普通文字，选区上方弹出"拷贝 / 查询 / 翻译"，第二页是"共享…"；输入框里是"剪切 / 拷贝 / 粘贴 / 全选"；长按链接仍然是 Chrome 的链接菜单。

### 0016 停用无痕模式（`ios/chrome/browser/policy/model/policy_util.mm`）

content 的单进程模式只有一个进程内渲染器，也只支持一个浏览器上下文：`RenderProcessHostImpl::IsSuitableHost` 在单进程时直接返回"合适"，只用 DCHECK 检查浏览器上下文是否一致。无痕标签页用的是另一个浏览器上下文：模拟器配置开着 DCHECK，一打开就崩（"Single-process mode does not support multiple browser contexts"，验证过）；真机配置不开 DCHECK，推测它会和普通标签页共用同一个渲染器进程和绑在它上面的存储，等于假无痕（没在真机上试）。补丁让 `IsIncognitoModeDisabled()` 在 Blink 构建里总是返回 true，效果和企业策略 `IncognitoModeAvailability` 停用无痕一样：新建无痕标签页、快捷键、从别的 app 用无痕打开等入口都按停用处理（读源码：它们都查这个函数）。链接菜单里的"在无痕模式下打开"原来不看策略（点了没反应），补丁让它和其他无痕动作一样变灰。标签页网格的无痕页显示的是策略停用时的文字"您的组织关闭了私密浏览功能"。模拟器里验证过：Cmd+Shift+N 不再崩溃；溢出菜单的"打开新的无痕式标签页"和链接菜单的"在无痕模式下打开"是灰的；无痕页显示"无痕模式不可用"。

### 0017 键盘弹出时的可见区域（`content/browser/renderer_host/render_widget_host_view_ios{,_uiview}.mm`）

屏幕键盘弹出时，Chrome 的工具栏收起逻辑（`FullscreenMediator`）把键盘高度当成网页底部被挡住的部分（`SetKeyboardObscuredInset`），加进网页视图的底部内边距。Blink 版里这个内边距直接决定网页视图的大小，视图被缩到了键盘上方（WebKit 版里同样的内边距只是告诉 WKWebView 哪块被挡住，视图大小不变）。content 的 `RenderWidgetHostViewIOS::GetVisibleViewportSize()` 又按 `RenderWidgetUIView` 自己记下的键盘高度，从可见区域里再减一次，可见区域（`visualViewport.height`）就成了 0。Blink 每次编辑后都要把光标滚进可见区域，区域为 0 时光标永远"看不见"，于是每输一个字页面就滚一屏（用户在真机上发现）。补丁给 `RenderWidgetUIView` 加了 `keyboardOverlap`：只算键盘实际挡住这个视图的那一段（键盘顶边到视图底边），可见区域只减这么多；要不要把焦点输入框滚进视野，仍按键盘是否弹出来判断。这样不管嵌入方有没有先把视图缩小，结果都对。

模拟器里验证过（拼音屏幕键盘，测试页记录 `scrollY` 和可视视口）：之前聚焦后可视视口高度为 0，每按一个键页面滚约 420 px；之后可视视口为 314 px（键盘上方的网页视图），聚焦时把输入框滚进视野一次，之后打字、选候选字、收起键盘，页面都不动。键盘弹出时网页的布局视口也会跟着变矮（`innerHeight` 631→314，因为视图被缩小了），和 Safari 只缩可视视口的做法不同，当时没改；后来补丁 0020 改了：键盘不再缩小网页视图，`keyboardOverlap` 也改成从外层滚动视图算。

### 0018 网络变化时立刻重读代理设置（`net/proxy_resolution/proxy_config_service_ios.cc`）

补丁 0009 让网页请求用 Chromium 的 `ProxyConfigServiceIOS` 读系统代理设置。iOS 没有 Mac 上那种代理变化通知（`SCDynamicStore` 在 iOS 上不可用），所以这个服务只能轮询：有请求、而且距上次检查超过 10 秒时才去重读，触发重读的那个请求还用旧设置。关掉 Shadowrocket 这类会设置代理的 VPN 后，接下来一段时间的请求仍会发往已经不存在的代理（推测这就是用户在真机上看到的报错，还没确认）。正版 Chrome 的网页走 WKWebView，由系统处理代理和 VPN，不受影响；Android 版监听系统的 `PROXY_CHANGE` 广播，Mac 版用 `SCDynamicStore` 通知，都是即时的。

补丁让服务在第一次被观察（`AddObserver`）时登记 iOS 的网络配置变化通知（`notify_keys.h` 里的 `kNotifySCNetworkChange`，即 `com.apple.system.config.network_change`，公开接口），一收到就在使用它的线程上调用 `CheckForChangesNow()` 重读；轮询保留作兜底。没有通知时不做任何事，读一次设置也只是在后台线程调一次 `CFNetworkCopySystemProxySettings()`，开销可以忽略。登记放在 `AddObserver` 而不放在构造函数里，是因为有的实例在 UI 线程上创建、却在 IO 线程上使用（`PollingProxyConfigService` 里的 TODO 也提到了），第一版在构造函数里登记，回调发回了 UI 线程，撞上了轮询服务的线程检查（模拟器版开着 DCHECK 直接崩溃，验证过）。

模拟器里验证过（临时测试版）：5 个实例（Chrome 自己的和网页的网络上下文）都登记成功；用同一条回调路径发一个测试通知，每个实例都在自己的线程上重读了设置，没有线程检查报错。模拟器里没法开关 VPN（`simctl spawn` 起的 `notifyutil` 连不上模拟器的通知服务，`com.apple.system.*` 的通知也只有 root 能发），真机上的效果要用户开关 Shadowrocket 来确认。

### 0019 像 Safari 那样选择文字（`content/browser/renderer_host/render_widget_host_view_ios{,_uiview}.mm`）

`RenderWidgetUIView` 早就接了 BrowserEngineKit 的系统文本交互（`BETextInteraction`，Safari 的选区拖柄、放大镜、编辑菜单都由它来画），但实际不起作用：长按只选中一个词，没有拖柄。原因是系统文本交互自己保存一份选区（由 UIKit 的 `UITextSelectionDisplayInteraction` 和 `UIAsyncTextInteraction` 维护），而它从 `RenderWidgetUIView` 读到的选区一直是空的。用 lldb 附加到模拟器里的 app 逐个查出来的（方法见 build-guide.md）：

- `BETextRange` 的起点返回的是终点，`comparePosition:toPosition:` 对任何两个位置都说相等，`offsetFromPosition:toPosition:` 总是 0，所以每个选区都被当成光标。现在位置带一个"离选区起点的偏移"（起点 0，终点为选中文字的长度），按它比较。
- `beginningOfDocument` 返回 nil。UIKit 会把选区换算成"从文档开头算起的偏移"再换算回来（私有方法 `_nsrangeForTextRange:` / `_textRangeFromNSRange:`），换回来时丢了选区。content 只知道选区，不知道整篇文档，所以让选区本身充当文档：开头就是选区起点。
- 系统那份选区要调 `refreshKeyboardUI` 才刷新，上游只在选中文字变化时调；Blink 先报文字、后报选区边界，所以刷新时拿到的是旧边界或者没有边界。现在边界变化时也刷新。`refreshKeyboardUI` 会顺带关掉编辑菜单，所以刷新前菜单开着的话，刷新后再弹出来（这是在模拟器里观察到的行为，不是文档写的）。
- 非输入框里 `selectionClipRect` 返回 `CGRectNull`，系统把拖柄裁剪到空矩形里，全被裁掉，编辑菜单也找不到选区，只好放在视图顶上。现在返回视图的范围。
- 拖柄画反了：`selectionRectsForRange:` 把终点标成了起点。

拖柄能显示以后，拖动的逻辑也是错的：`adjustSelectionBoundaryToPoint:touchPhase:baseIsStart:flags:` 的 `baseIsStart` 意思是"起点不动、拖的是结尾手柄"，上游读反了，拖结尾手柄时动的是开头；而且"不动的那一端"每次都从正在变化的选区里重新取，两个手柄交叉后就漂走了。现在拖动开始时记下不动端（取边界线段的中点，顶端可能取整到上一行），之后一直用它；手柄越过不动端时告诉系统选区翻转了（按从左到右的文字判断）。松手时系统会自己弹出编辑菜单，但随后 Blink 报来的最终选区又会触发一次刷新、把菜单关掉，所以松手时记下"下次选区更新后再弹一次"。

编辑菜单（`automaticallyPresentEditMenu` 改成 YES）照 Safari 的样子：

- `canPerformAction:withSender:` 按当前选区回答（拷贝要有选中文字；剪切、粘贴、选择、学习…只在输入框里；粘贴还要剪贴板里有文字），而且只认这个类自己实现的动作：UIKit 用分类让所有视图都"能响应"一些私有动作（比如菜单里"翻译"用的 `_translate:`），对这个视图却什么也不做。"全选"只在输入框里出现（和 Safari 一样），但 Command-A（发送者是 `UIKeyCommand`）仍然能全选整页。
- 系统菜单还会收进响应者链上其他对象能处理的命令，比如网页文字也出现"全选""自动填充"，"书写工具"也在（这个视图没有它要的文本访问能力）。所以在 `buildMenuWithBuilder:` 里过滤：命令要本视图能执行，非输入框去掉"自动填充"子菜单。
- 菜单里的"查询""翻译"用的是 UIKit 的私有动作 `_define:`、`_translate:`，过滤时按名字换成 BrowserEngineKit 公开的 `lookup:`、`translate:`（保留系统的标题），分别调 `BETextInteraction` 的 `showDictionaryForTextInContext:…`（系统词典）和 `translateText:fromRect:`（Apple 翻译）；另外实现了 `share:`（共享）、`addShortcut:`（学习…）、`select:`（选择）。
- "查询"只在系统拿得到选中文字时出现：`requestDocumentContext:completionHandler:` 原来返回 nil，现在返回选中文字和 Blink 报来的前后文。
- 滚动时收起菜单，停下后再弹出；拖柄跟着文字走。选区清空时关掉菜单。

模拟器里验证过（2026-10-27）：长按词语，两端出现拖柄，上方是"拷贝 / 查询 / 翻译"，第二页"共享…"；同一台模拟器里 Safari 是"拷贝 / 查询 / 翻译 / 查找"，展开后还有"搜索网页""拷贝高亮标记的链接"，这三项是 Safari 自己的功能，这里没有。拖结尾手柄向右、开头手柄向左、结尾手柄跨到下一行，选区都对，每次松手菜单回到新选区上方；拷贝后剪贴板里是选中的文字；"查询"弹出系统词典面板（模拟器里没装词典，和 Safari 一样显示"未找到内容"）；"翻译"弹出 Apple 翻译（第一次使用先要同意隐私说明）；滚动后菜单回到选区上方；点空白处选区、拖柄、菜单都消失；输入框里"粘贴"替换选中的词。没做的：Safari 的"查找""搜索网页"；放大镜（系统的手势都还关着，长按选词由 Blink 自己处理）。

### 0020 键盘只缩小可视区域，不缩短页面（`ios/chrome/browser/fullscreen/model/fullscreen_browser_agent.mm`、`content/browser/renderer_host/render_widget_host_view_ios{,_uiview}.mm`）

用户在真机上发现，屏幕键盘一出来页面布局就变短，和 iOS 26 起 Liquid Glass 的设计冲突（键盘是半透明的，后面应该看得到网页），而且网页卡来卡去。原因见 0017 一节：Chrome 把键盘高度加进网页视图的底部内边距，Blink 版据此把网页视图缩短，于是布局视口（`innerHeight`）变矮，每次键盘出现、收起、改变高度（比如候选栏变化）都要整页重新排版，键盘后面只剩空白。WKWebView 里同样的内边距只是标出"被挡住的部分"，视图不变。

补丁在 Blink 版里不再把键盘加进内边距（`FullscreenBrowserAgent` 里的 `kKeyboardInsetsWebView`），由 content 自己处理键盘：可见区域扣掉键盘挡住的部分，再把焦点输入框滚进视野。这和 Safari、安卓 Chrome（`interactive-widget=resizes-visual`，默认值）的做法一样：布局视口不变，只有可视视口变小。要做对，还改了几处：

- 键盘上方的"上一项 / 下一项 / 完成"按钮栏算作键盘的一部分。上游特意把它减掉了，以前视图被缩短时看不出问题，现在会把输入框滚到按钮后面。
- 等新的可视区域生效后再请求滚动。上游在同步新尺寸后立刻请求 `ScrollFocusedEditableNodeIntoView`，两条消息走不同的通道，Blink 先收到滚动请求，按旧的可视区域判断输入框"看得见"，就不滚了（在 Blink 和 cc 里加日志确认过：判断时可视区域还是 1893 px 高）。现在照 `RenderWidgetHostViewAura::SetInsets()` 的做法：键盘出现或变高时分配一个新的 surface id（`ForceNewSurfaceId()`），等带这个 id 的帧激活（`OnRenderFrameMetadataChangedAfterActivation`）后再请求滚动。
- 0017 的 `keyboardOverlap` 原来用网页视图自己的位置算它的底边，可网页视图的 frame 跟着页面的滚动偏移走（`UpdateFrameBounds()`），滚动时在屏幕上会偏零点几个点，可视区域高度就在 314 和 315 之间来回跳，每一帧都让 Blink 重新调一次可视视口、触发 resize 事件。现在从外层不动的滚动视图算，并取整。
- `-[RenderWidgetUIView showKeyboard:withBounds:]` 把视图的 frame 设成自己的 bounds，也就是挪到滚动视图的原点；视图本该在滚动偏移处，所以每次点输入框，页面都会跳到顶上一帧再回来。删掉了这一句。

模拟器里验证过（2026-10-27，拼音屏幕键盘，测试页记录布局视口和可视视口）：聚焦页面下方的输入框，`innerHeight` 保持 631，可视视口变成 314（键盘和按钮栏上方），并平滑滚动 276 把输入框居中，连试三次结果一样；打"ni hao"、选候选字上屏，页面不动；点"完成"后可视视口回到 631。半透明键盘后面看得到网页。改之前：`innerHeight` 631→314，键盘和按钮栏后面是一块灰色。真机待确认。

### 0021 网页跟随系统的深色模式（`ui/native_theme/os_settings_provider_ios.mm`、`ios/web/content/init/ios_content_browser_client.cc`）

网页一直以为系统是浅色：`prefers-color-scheme: dark` 从不匹配，支持深色的网页也是浅色。两处缺口：iOS 没有 `ui::OsSettingsProvider` 的实现（Mac、Windows、安卓都有），`NativeTheme` 不知道系统外观；iOS 的嵌入层（`IOSContentBrowserClient`）也不设网页偏好里的配色，而默认值是浅色。

补丁新增 `OsSettingsProviderIOS`：读 app 窗口场景（`UIWindowScene`）的浅色/深色外观（有前台场景时以它为准），在每个场景上登记外观变化（iOS 17 起的 `registerForTraitChanges:`），后来连上的场景在激活时补登记；外观一变就通知 `NativeTheme`。结果存在原子变量里，单进程模式下渲染线程也会读。`IOSContentBrowserClient` 实现 `OverrideWebPreferences`，按 `NativeTheme` 设置网页的 `preferred_color_scheme`，并在外观变化时（`WebPreferencesNeedUpdateForColorRelatedStateChanges`）要求重算网页偏好。Chrome 自己的界面本来就跟随系统，不受影响。

模拟器里验证过（2026-10-27）：测试页（`prefers-color-scheme`、`color-scheme: light dark`、`matchMedia` 监听）开着时用 `xcrun simctl ui <udid> appearance dark/light` 切换，页面、媒体查询、监听回调、表单控件都立刻跟着变；深色模式下新打开的网页直接是深色。google.com 在同一台模拟器里 Safari 和这里都是浅色（它自己的"深色主题"设置是"已停用"），不是这里的问题。

### 0022 页内查找（`ios/web/content/web_state/crc_find_in_page_controller.mm`、`content_web_state.mm`）

Chrome 菜单里的"在网页中查找…"一直是灰的：Chrome 先问网页状态能否搜索（`FindInPageManagerImpl::CanSearchContent()` → `WebState::IsFindInteractionSupported()`），Blink 版的 `ContentWebState` 在这几个接口上都是空实现，固定说不能。WKWebView 版里，Chrome 用的是网页视图自带的系统查找栏（`UIFindInteraction`，Safari 也是它），`FindInPageManagerImpl` 通过 `CRWFindInteraction`/`CRWFindSession` 包装来驱动它、轮询结果。

补丁给 Blink 版的网页视图（`CRCWebViewportContainerView`）装上同样的 `UIFindInteraction`，由新类 `CRCFindInPageController` 提供查找会话：一个 `UIFindSession` 子类，把查找栏里的文字交给 content 的查找（`WebContents::Find`，关闭时 `StopFinding`）。Blink 自己高亮所有匹配（黄色，当前项橙色）并滚到当前项；它的回复（`WebContentsObserver::DidReceiveFindReply`，由 `ContentWebState` 转过来）给出匹配数和当前是第几个，会话据此更新 `resultCount`、`highlightedResultIndex`，再调 `updateResultCount` 让查找栏刷新"1/5"。`ContentWebState` 的 `IsFindInteractionSupported()` 改为支持，`SetFindInteractionEnabled()` 创建或移除控制器，`GetFindInteraction()` 返回包装。几处细节：

- 新搜索从页面开头重来，只计数和高亮。系统查找栏每次搜索后会立刻自己调一次"下一个"：`_UIFindNavigatorViewController` 在同一个调用里先 `performSearchWithQuery:` 再 `highlightNextResultInDirection:`（lldb 看到的，文档没写），Safari 就是由这一下选中第一个匹配。所以新搜索先 `StopFinding` 清掉上一次的当前项（不清的话 Blink 会从它接着往后找，搜索词没变时还会跳过它），再用 `find_match = false` 只计数和高亮，接着那次"下一个"从页面开头选中第一个并滚过去。第一版新搜索时自己也选中一个，每敲一个字母就往后多挪一格：有 6 处匹配的页面停在第 3 处时打 apple，结果停在 5/6，Safari 是 1/6。用户 2026-10-28 在真机上发现。
- 回复按请求 ID 过滤：每次新搜索记下它的请求 ID，更早的回复不再采用（content 可能在 `Find()` 返回前就回复，所以 ID 在回调里记下）；`-1` 表示数值没变。
- Blink 只能按子串查找，不支持全字匹配，所以从查找栏的选项菜单里去掉"全字匹配"（按动作的标识 `wholeWords`，这是在模拟器里看到的，不是文档写的）；"区分大小写"映射到 `match_case`。

模拟器里验证过（2026-10-27；2026-10-28 修正后重测）：菜单项可用，点了弹出系统查找栏（在屏幕键盘上方，Chrome 进入全屏）；有 6 处 apple 的长页面停在第 3 处时，用英文键盘打"apple"是 1/6，页面滚回第 1 处，和同一台模拟器里的 Safari 一样；用拼音键盘打 apple、再点候选栏里的"apple"上屏，两边也都是 1/6；下一个、上一个逐个滚到对应位置，6/6 之后回到 1/6，1/6 往前是 6/6；在也有"Apple"的页面上开"区分大小写"，1/5 变成 1/4；搜页面里没有的词显示 0、按钮变灰；拼音输入的"狐狸"能找到；关闭后高亮清除、工具栏恢复，再打开也正常。再打开时查找框是空的（Chrome 从菜单打开查找时传的就是空字符串，`browser_coordinator.mm` 里的 `StartFinding(@"")`；Safari 会预填上次的词），右边显示"0"：这时查找会话的方法一个都没被调用（lldb 看到的），是查找栏复用上一次的界面自己显示的。

更正：这里原来写"用拼音上屏时两边都是 2/5：上屏前后搜索词没变，查找栏当成了'下一个'"，是错的。Safari 拼音上屏也是 1/6；2/5 是第一版的问题（见上面第一条），那个测试页上用英文键盘时恰好绕回到 1/5，所以当时没看出来。

### 0023 光标和选区用系统蓝（`third_party/blink/renderer/core/layout/layout_theme_ios.mm`、`caret_display_item_client.cc`、`local_frame_view.cc`、`content/browser/renderer_host/ios_extended_text_input_traits.mm`）

用户 2026-10-28 在真机上发现选区拖柄和选区的颜色不对。在模拟器里和 Safari 取色对比：拖柄是纯蓝 (0, 0, 255)，因为 content 里写死了 `[UIColor blueColor]`；选区是安卓的青色，因为 Blink 的 iOS 主题（`LayoutThemeIOS`）沿用了安卓的 `LayoutThemeMobile`，40% 不透明的 Holo 蓝 `#33B5E5`，选中的字还被改成黑色，深色模式下是浅蓝底配深灰字；输入框里的光标是 Blink 画的竖线，1 pt 宽，和文字同色。Safari 里三样都是系统蓝（`systemBlue`）：拖柄和光标是纯色，光标 2 pt 宽；选区是 20% 不透明的系统蓝（WebKit 给选区高亮的透明度就是 0.2），字保持原色。

补丁照 Safari 改：

- 拖柄用 `UIColor.systemBlueColor`（动态颜色，深色模式自动换）。
- `LayoutThemeIOS::PlatformActiveSelectionBackgroundColor()` 返回 20% 不透明的系统蓝；`SupportsSelectionForegroundColors()` 返回 false，选中的字保持原色（Blink 的 Mac 主题也是这样）。
- 光标：页面没设 `caret-color` 时用系统蓝（`CaretDisplayItemClient`），页面设了就听页面的；宽度 2 pt（`LocalFrameView::BarCaretWidth()`）。
- 系统蓝的值写在 `LayoutThemeIOS::SystemBlueColor()`：浅色 `#0088FF`，深色 `#0091FF`，是 iOS 26 起的值，用 lldb 在 iOS 27 模拟器里让 UIKit 解析 `systemBlueColor` 读出来的（验证过）。Blink 在渲染线程上，不调 UIKit，所以写成常量；以后 iOS 改了系统蓝，拖柄会跟着变，选区和光标不会。

正版 Chrome iOS（WKWebView）里这几样可能是 Google 蓝：WebKit 在网页视图的 tintColor 不是系统蓝时改用 tintColor，而 Chrome 窗口的 tintColor 是 `#1A73E8`（深色 `#8AB4F8`，lldb 读出来的）。这是读 WebKit 的做法推出来的，没有对照正版（推测）。这里按用户一直对照的 Safari 用系统蓝。

模拟器里验证过（2026-10-28，和同一台模拟器里的 Safari 在同一测试页上取色对比）：长按选中一个词，选区在白底上是 (197, 232, 255)，拖柄是 (0, 139, 255)，和 Safari 的像素值一样；选中的红字保持红色；深色模式下白字保持白色，选区是叠在页面上的 20% 深色系统蓝（Blink 的深色底 #121212 上是 (0, 44, 67)，Safari 的黑底上是 (9, 29, 53)）；textarea 里的光标是系统蓝，6 像素（2 pt）宽，和 Safari 一样；设了 `caret-color: red` 的输入框光标仍然是红色。没改的：输入框聚焦时的焦点框还是 Blink 的橙色（Safari 是蓝色），textarea 的默认字体是等宽字体（Safari 是系统字体）。

### 0024 请求桌面版网站（`ios/web/content/navigation/content_navigation_{manager,item}.mm`、`web_state/content_web_state_builder.mm`、Blink 的 `navigator_base.cc`）

用户 2026-10-28 在真机上发现"请求切换到桌面版网站"不起作用。Chrome 的菜单项调用 `NavigationManager::ReloadWithUserAgentType()`，Blink 版的实现是上游留下的 `NOTIMPLEMENTED()`，点了什么都不发生；条目的 `GetUserAgentType()` 也只是一个默认"移动版"的成员变量。

补丁照安卓版 Chrome 的做法（`NavigationControllerAndroid::SetUseDesktopUserAgent()`）：

- 第一次请求桌面版时，给 WebContents 设上桌面版的 UA 覆盖：Mac 版 Chrome 的 UA（`Macintosh; Intel Mac OS X 10_15_7`，安卓用的是 Linux 的），客户端提示也改成 `macOS`、非移动设备（照搬安卓的 `JNI_ContentUtils_SetUserAgentOverride`）。
- 在最近一次提交的条目上 `SetIsOverridingUserAgent()`，让 content 重新计算网页设置（`NotifyPreferencesChanged()`；安卓在同一处调的 `UpdateOverridingUserAgent()` 做的就是这个），再 `LoadOriginalRequestURL()` 按原始请求网址重新加载（手机版跳到 m. 站点的网站会回到原网址）。
- 重新计算网页设置是为了排版：条目覆盖了 UA 时，content 不理会网页的 viewport 标签（`WebContentsImpl::ComputeWebPreferences()`），网页按 980 像素宽排版、缩小到整页可见，和没有 viewport 标签的老式电脑网页一样。标志是在重新加载前设在条目上的，提交时 content 看不出变化，不会自己重算。第一版漏了这一步：UA 换成了 Mac 的，响应式网站（同一份网页按屏幕宽度排版）却还是手机排版，要等别的原因触发重算（比如切换深色模式）才突然变成电脑排版（用户 2026-10-29 在真机上发现："会闪一下，但是还是手机界面"，模拟器里复现了）。
- 之后在这个标签页里点链接、输网址，content 都沿用当前条目的覆盖设置，直到切回移动版；新标签页从移动版开始。
- 条目的 `GetUserAgentType()`/`SetUserAgentType()` 改成读写条目上的覆盖标志，菜单据此在"桌面版 / 移动版"两项之间切换。保存会话时本来就存了这个类型，恢复时却没读；现在恢复会话时把标志放回条目、给 WebContents 设上桌面版 UA 并重算设置，app 被系统关掉再打开后，标签页仍是桌面版。
- 桌面版里 `navigator.platform` 报 `MacIntel`（Blink 的 `NavigatorBase::platform()`，在客户端提示的平台是 macOS 时），和 Safari 一样；原来一直是 `iPhone`，按它判断设备的网页脚本还会当成手机。

和 Safari 的差别：iPhone 上的 Safari 请求桌面版时只换 UA 和 `navigator.platform`，仍按 viewport 标签排版（同一台模拟器里验证过，测试页在 Safari 的桌面版里布局宽度仍是 375），所以响应式网站在 Safari 里也还是手机排版。这里照安卓版 Chrome，真按电脑宽度排版。

模拟器里验证过（第一版 2026-10-28；修正后 2026-10-29 在 159 上重测，测试页带 `width=device-width` 的 viewport 标签，显示请求头里的 UA、`navigator.userAgent`、`navigator.platform`、`navigator.userAgentData` 和布局宽度）：请求桌面版后页面重新加载，UA 是 Mac 版 Chrome 的，客户端提示 `mobile` 为 false、平台 `macOS`，`navigator.platform` 是 `MacIntel`，布局宽 980、缩放 0.38；重新加载、点链接、重启 app 都保持桌面版；菜单变成"请求切换到移动版网站"，点了恢复 iPhone 的 UA 和 375 的布局。真实网站：github.com 变成电脑版排版；bilibili 从 m.bilibili.com 换到电脑版的 www.bilibili.com。缩小后的页面能不能双指放大，模拟器里没测（这里的模拟器工具发不了双指手势），推测可以：网页视图开着多点触控，Blink 的手势识别默认支持双指缩放；要真机确认。

### 0025 空输入框也能粘贴（`content/browser/renderer_host/render_widget_host_view_ios{,_uiview}.mm`）

用户 2026-10-28 在真机上发现空的文本框没法粘贴。系统的编辑菜单（0019）只在有选中文字时弹得出来：上游在选区为空时把系统文本交互的选区显示（`UITextSelectionDisplayInteraction`）关掉，0019 也只在有选中文字时刷新系统那份选区副本（`refreshKeyboardUI`）。输入框里只有光标时，长按后 Blink 照样发出编辑菜单请求，0015 也调了 `presentEditMenuForSelection`，但系统不知道光标在哪，菜单不出来。用 lldb 在运行中的 app 里验证过：光标状态下手动激活选区显示、刷新、再弹菜单，"粘贴"就出来了；但激活后系统会再画一个自己的光标，和 Blink 画的并排。

补丁：

- 可编辑区域里只有光标时，保持选区显示激活（WebKit 也是这样），光标移动时刷新系统的选区副本；输入法正在组字（有标记文字）时不刷新，免得打断。
- 系统自己的光标换成一个什么都不画的视图（`BEHiddenTextCursorView`），光标仍由 Blink 画。
- 点按：Safari 里，已有光标的输入框再点一下，只要光标没被移动（空框里点哪都一样，有字时点在光标上），就弹出编辑菜单。系统的交互不替 Blink 处理这种点按（用 lldb 看过，点按时它不会来问菜单），所以自己做：点按发给 Blink 前记下当时聚焦的输入框（`TextInputState::node_id`），Blink 处理完（收到这次点按的回执）后等 150 毫秒，期间光标没动、还是同一个输入框，就弹出菜单。
- "全选"只在输入框里有文字时出现（Safari 也是这样）。

模拟器里验证过（2026-10-28，和同一台模拟器里的 Safari 对照）：空输入框第一次点只聚焦，再点一次弹出"粘贴"，长按也是；点"粘贴"后内容贴进去，页面收到 paste 和 input 事件。有字的输入框里，移动光标的点按不弹菜单，点在光标上弹出"粘贴 / 选择 / 全选"。只有一个光标；拼音组字、选候选字上屏照常；长按普通文字照样选中一个词、出现拖柄和菜单。

### 0026 网站权限：定位、剪贴板、摄像头和麦克风（`ios/web/content/content_permission_manager.mm`、`content_browser_context.mm`、`web_state/content_web_state.mm`、`init/ios_browser_main_parts.mm`）

用户 2026-10-28 在真机上发现网页请求不了位置、剪贴板等权限。原因：Blink 版的浏览器上下文没有权限委托（`GetPermissionControllerDelegate()` 返回空），content 于是对所有权限一律直接拒绝、不提示：定位报"User denied Geolocation"，读写剪贴板都是 `NotAllowedError`，`permissions.query` 全是 denied。摄像头、麦克风走另一条路（`WebContentsDelegate::RequestMediaAccessPermission()`），`ContentWebState` 没实现，也直接拒绝。另外 iOS 上定位固定用 Core Location（`kPlatformOnly`），需要浏览器客户端提供"系统定位权限管理器"，content 的默认实现返回空，一旦允许了网页定位就会撞上 `CHECK`（读源码确认）。

补丁：

- 新的 `ContentPermissionManager`（`content::PermissionControllerDelegate`）：写剪贴板直接允许（和 Chrome 一样）；定位、读剪贴板弹提示框问用户，答案按顶层网页的源记住，直到 app 退出；页面不可见时不弹，按拒绝处理；其余权限照旧拒绝（通知等 iOS 版本来就不支持）。
- 提示框的文字用 components 里移动端已有的翻译（`IDS_GEOLOCATION_INFOBAR_TEXT`"…想使用您设备的位置信息"、`IDS_CLIPBOARD_INFOBAR_TEXT`"…想查看复制到剪贴板的文字和图片"、`IDS_PERMISSION_ALLOW`/`IDS_PERMISSION_DONT_ALLOW`），没有新加字符串。
- 摄像头、麦克风：`ContentWebState::RequestMediaAccessPermission()` 用 Chrome 给 WKWebView 用的同一个提示（`WebStateDelegate::HandlePermissionsDecisionRequest()`，"允许一次 / 在访问期间允许 / 一律不允许"）。提示只回"允许 / 拒绝"，所以答案按 WebKit 的做法记到换页为止；"在访问期间允许""一律不允许"由 Chrome 自己按网站保存（本地构建里是这样，见下）。允许后按页面要求的设备（没指定就用第一个）回给 content，选设备的写法参考了 Chromecast 的实现。
- 浏览器客户端返回系统定位权限管理器（`SystemGeolocationSourceApple`，和 content_shell 的 iOS 版一样），在 Objective-C++ 的 `IOSBrowserMainParts` 里创建（头文件里有 Objective-C 类型，不能从 `.cc` 引用）。页面一用定位，content 先请求 app 的定位权限（iOS 的系统提示，文字是 Chrome 自带的"Chromium 会将您的位置信息分享给您允许的网站"），再问网站权限（本补丁的提示）。

模拟器里验证过（2026-10-28，测试页逐个请求，结果通过本地服务器的日志读出来）：`permissions.query` 对定位、读剪贴板、摄像头、麦克风是 prompt，写剪贴板 granted，通知 denied；请求定位先弹 iOS 的系统提示，再弹"localhost:8765 想使用您设备的位置信息"，允许后拿到模拟的位置（`simctl location` 设的上海），再请求不再问；读剪贴板先弹本补丁的提示，允许后 iOS 还会问"Chromium 想从 CoreSimulatorBridge 粘贴"（内容来自别的 App 时的系统行为），之后读到文字，再读不再问；选"不允许"后报 `NotAllowedError`，再请求不再问；写剪贴板不提示、写入成功；模拟器没有摄像头，用 `--use-fake-device-for-media-stream` 启动给它一个虚拟摄像头：请求时弹 Chrome 的摄像头提示，"允许一次"后拿到视频轨道，同一页面再请求不问，重新加载后再问。上一轮选过"在访问期间允许"的 localhost 之后直接允许、不再提示，说明 Chrome 把它按网站存下了；`kDomainLevelSitePermissions` 默认是关的，本地构建里大概是测试用的功能开关配置打开了它（推测，没查）。没验证的：真机上的真摄像头和麦克风。Blink 的定位超时从请求一开始就计时，等提示的时间也算在内（上游行为，和 Chrome 一样），所以页面设的超时较短时，第一次请求可能在答完提示前就超时。

### 0027 选区的形状、放大镜和振动像 Safari（`third_party/blink/renderer/core/layout/inline/inline_cursor.cc`、`content/browser/renderer_host/render_widget_host_view_ios{,_uiview}.mm`、`ios/web/content/ui/content_context_menu_controller.mm`）

用户 2026-10-28 指出选区"形状与动画"还是有点怪，而且不会振动。在模拟器里和 Safari 逐项对比（截图取色量尺寸；录屏后用 AVFoundation 逐帧导出）：

- 形状：多行选区里，我们每行在文字末尾（加一个空格宽）就断开，右边参差不齐；Safari 除最后一行外，每行都延伸到内容区右边缘，拼成一整块。
- 拖柄：我们的圆点只有 31 像素（约 10pt），Safari 是 47 像素（约 16pt）。上游有一段代码把 BrowserEngineKit 的 16.5pt 圆点当成 bug，按拖柄高度缩小，最小到 0.65 倍；可这正是 Safari 的大小。拖动拖柄时系统又会把圆点恢复原大，于是两个圆点一大一小。
- 动画：Safari 长按选中词的那一帧，高亮和拖柄直接以原大小出现（没有缩放动画），同时出现放大镜，手指不松开时放大镜跟着选区末端，移动手指会扩展选区；松手后放大镜消失，编辑菜单才出来。我们没有放大镜，菜单在手指还按着时就弹出。拖拖柄时系统本来就会显示放大镜（录屏看到的），这部分两边一样。
- 振动：长按选字由 Blink 处理，系统的文本交互不知道选区变了，所以不振。用 lldb 看过：我们的 app 里长按时只有链接预览那类点按交互在准备触感；Chrome 地址栏（原生输入框）里长按、拖拖柄也没有调用选区触感，所以 Safari 的振动大概是 WebKit 自己加的（推测，系统不允许附加到 Safari 验证）。上游还把系统的文本手势全关了（`textInteractionGesture:shouldBeginAtPoint:` 一律返回 NO），系统自己的放大镜手势不会启动。

补丁：

- Blink：选区跨到下一行时，行尾那段高亮补到所在块内容区的末端（`ExpandedSelectionRectForSoftLineBreakIfNeeded()`，只在 iOS 上），各行拼成一整块。
- 去掉上游缩小圆点的代码，圆点保持 BrowserEngineKit 的 16.5pt。
- 长按：Blink 收到长按时记下位置；Chrome 的编辑菜单请求（0015）改为交给网页视图（`presentEditMenuWhenTouchesEnd`）。手指还按着时不弹菜单，而是振一下、用系统的放大镜接口（`UITextLoupeSession`）显示放大镜；移动手指时扩展选区（`MoveRangeSelectionExtent`，输入框里只有光标时移动光标 `MoveCaret`），放大镜跟着走，这期间触摸不再交给页面滚动；松手后收起放大镜、弹出菜单。
- 振动：长按选中文字或在输入框里放下光标时，以及拖拖柄、长按后拖动使选中文字变化时，用 `UISelectionFeedbackGenerator` 振一下。

模拟器里验证过（2026-10-28，和同一台模拟器里的 Safari 在同样的页面上对比截图、逐帧看录屏）：脚本选中的三行文字，前两行都延伸到右边缘，和 Safari 一样；拖柄圆点 47 像素，和 Safari 一样（之前 31 像素）；长按选中词后，手指按着时显示放大镜，松手后才弹出编辑菜单；按着不松再移动，选区扩展到下一行；挂上调试器看到：长按选中时振一次，按着拖动或拖拖柄时选区每变一次振一次，在空输入框里长按时也振一次（松手后菜单里有"粘贴"）；长按链接照常弹出 Chrome 的链接菜单，不显示放大镜、不振。模拟器里感觉不到振动，真机待确认。

### 0028 不在屏幕上的网页标成隐藏（`content/browser/web_contents/web_contents_view_ios.mm`、`ios/web/content/web_state/content_web_state.mm`）

用户 2026-10-29 说"恢复已暂停的网页时似乎会崩溃"。模拟器里没复现（切回很久没看的标签页、退到后台再回来都正常），但查的时候发现：iOS 上从来没有东西告诉 WebContents 网页在不在屏幕上。WebContents 一创建就算可见，之后一直可见。切走的标签页、后台打开的标签页、退到后台的 app 里的网页，`document.visibilityState` 都是 `visible`，不触发 `visibilitychange`，`requestAnimationFrame` 照跑。模拟器里，一个有动画的测试页切到别的标签页后仍每秒画 35–40 帧，只显示标签页网格时 Chromium 占 38% CPU；app 退到后台后每秒还画 4–5 帧（都验证过）。WKWebView 在这些情况下会把网页标成隐藏、停止绘制。

真机上 app 退到后台后，iOS 不允许再用 GPU（后台提交的 Metal 命令会被拒绝），单进程版的 GPU 线程却还在画。这和回到前台时的崩溃有没有关系不知道（推测有可能）；后台标签页一直在画，对发热（"真机反馈的问题"第 1 条）肯定没好处。

补丁：

- content：WebContents 的原生视图（`WebContentsViewIOS` 的 UIScrollView）换成一个子类，进出窗口（`didMoveToWindow`）、所在场景进入后台或回到前台时告诉 `WebContentsViewIOS`，后者调 `UpdateWebContentsVisibility()`：在窗口里、app 在前台才算可见。Mac 和 Aura 也是由原生视图驱动这个接口。
- ios/web/content：`ContentWebState` 创建 WebContents 时设 `initially_hidden`，后台打开的标签页在显示之前不绘制。content 的可见性变化不再转给 `WasShown()`/`WasHidden()`：Chrome 自己会在显示、隐藏标签页时调它们（和 WebKit 版一样），再转一次会让观察者重复收到通知，而且每次 app 退到后台都会收到。`IsVisible()` 也改成跟随 Chrome 的这两个调用（WebKit 版就是这样），不跟随 WebContents，因为 Chrome 有些代码在 `IsVisible()` 为假时直接跳过，甚至 DCHECK。

隐藏时 content 会拆掉这个视图的合成器，显示时再建一个新的（`BrowserCompositorIOS`），0002 按同一个句柄把新的根图层挂回网页视图；模拟器里切换标签页、退到后台再回来，画面都正常。

模拟器里验证过（2026-10-29，测试页每秒报告 `document.visibilityState` 和绘制的帧数）：回到主屏幕时触发 `visibilitychange`（hidden），帧数降到 0；回到 app 时触发 visible，帧数恢复，画面正常。切到别的标签页后它隐藏，Chromium 的 CPU 从 38% 降到 1.6%（标签页网格里 0%），切回来恢复。"在新标签页中打开"的链接在后台加载时就是隐藏的，切过去后开始绘制。重启 app 后恢复的标签页正常显示。输入框打字（键盘上方的表单工具条照常出现）、长按选词和编辑菜单、请求桌面版网站、定位权限提示都照常，退到后台再回来后也一样。真机待确认，尤其是回到前台时还崩不崩、发热有没有减轻。

### 0029 真机版的诊断检查只记录、不崩溃（`base/check.cc`）

用户 2026-10-29 从 iPhone 13 mini（iOS 27.2）传来两份崩溃日志（`Chromium-2026-10-29-131202.ips`、`-133137.ips`），是同一个崩溃：app 已经在后台（`procRole` 是 Non UI），被关闭时（上划关掉或系统回收，`-applicationWillTerminate:`）销毁用户配置，`~BrowserContextImpl()` 发现还有 RenderProcessHost 引用这个浏览器上下文（单进程模式下进程内渲染器的宿主一直活到最后），走到 `DUMP_WILL_BE_NOTREACHED()`，abort。用 sideload-2 的编译产物还原了地址：反汇编里传给它的 Location 是 `browser_context_impl.cc` 第 148 行（验证过）。

`DUMP_WILL_BE_*` 和还没到期的 `CHECK(..., base::NotFatalUntil::M…)` 在正式版 Chrome 里只上报、不崩溃，但 `base/check.cc` 的 `GetDumpSeverity()` 在非官方构建里返回 FATAL（为了在测试中尽早发现）。侧载版是面向用户的构建，却不是官方构建，真机上每一处这类检查都会让 app 闪退。

补丁：iOS 上用官方构建的严重级别：开着 DCHECK 时是 DCHECK（模拟器版，照旧崩溃，测试时能发现问题），否则是 ERROR（真机版：记日志、生成一份不上传的转储，然后继续）。只改了一个 .cc 文件，重编只需重新链接。

没在真机上验证；模拟器版开着 DCHECK，行为不变。chatgpt.com 那次崩溃的日志没留下来（见 status.md 第 31 条），是不是这类检查不知道（推测有可能）。

### 0030 横竖屏切换（`content/browser/renderer_host/render_widget_host_view_ios{,_uiview}.mm`、`browser_compositor_ios.{h,mm}`、`ui/display/ios/screen_ios.mm`）

用户 2026-10-29 说横竖屏切换后渲染错误。模拟器里用 UIKit 自己的调用转屏（调试器里先设 `UIDevice` 的方向，再调场景的 `requestGeometryUpdateWithPreferences:`），复现出三个问题：

1. **帧的尺寸和合成表面不同步。** 网页每一帧按屏幕大小画（`GetCompositorViewportPixelSize()` 用的是屏幕尺寸），浏览器端的合成器却只在网页视图的尺寸变化时才分配新的合成表面（`LocalSurfaceId`）。转屏改变了屏幕尺寸，没有新表面：模拟器版触发 `AsyncLayerTreeFrameSink` 的 DCHECK（同一个表面里帧高从 2436 变成 1125 像素）直接崩溃；关了 DCHECK 的真机版显示被裁掉的网页，旁边是网页没画到的区域（模拟器里是红色，用户的手机上是灰色）。改成和 Mac 一样按浏览器合成器显示网页的尺寸（视图大小）画，这个尺寸一变就会分配新表面。顺带省了工具栏后面那部分的绘制。
2. **屏幕信息慢一拍。** `display::Screen` 的 iOS 实现在设备方向变化时投一个任务去读 `UIScreen` 的尺寸，这时界面还没转、场景还是旧尺寸，于是网页拿到的是上一次的屏幕尺寸，横屏时还报 "portrait-secondary"；转回竖屏后新开的标签页（chatgpt.com）按横屏的高度绘制，下半截空着。改成跟随窗口场景的界面方向，尺寸按方向从竖屏尺寸转过来，并且用 KVO 观察场景的 `effectiveGeometry`（Apple 推荐的跟随转屏的办法）；网页视图也观察显示器变化，不只在布局时更新屏幕信息。
3. **网页视图的位置。** 网页视图在 Chrome 的滚动视图里按"网页的滚动偏移 + 内边距"放置，默认滚动视图的 `contentOffset` 总等于网页的滚动偏移；转屏时 UIKit 或 Chrome 把 `contentOffset` 改成了 -42，网页就画到工具栏下方 42 点的地方，露出滚动视图的灰色底。改成按滚动视图实际的 `contentOffset` 放置，并在它变化时跟着动。

另外，网页还没画到的地方原来显示上游调试用的红色，改成和 Mac 一样显示网页的背景色（默认白色）。

模拟器里验证过（2026-10-29）：测试页左转报 744×313、屏幕 812×375 landscape-primary，右转 landscape-secondary，转回竖屏 375×631、portrait-primary，每次都有 change 事件；横屏和转回竖屏后网页都完整、紧贴工具栏；转屏后新开 chatgpt.com 再来回转，都完整显示；来回转多次 app 不崩。没在真机上验证。

### 0031 菜单里的"GitHub 项目主页"（`ios/chrome/browser/popup_menu/overflow_menu/coordinator/overflow_menu_mediator.mm`）

菜单底部的"共享 Chromium"分享的是谷歌 Chrome 的 App Store 链接，和这个侧载 app 无关。按用户的要求（2026-10-29）换成"GitHub 项目主页"（繁体中文"GitHub 專案首頁"，其他语言 "Project on GitHub"），在新标签页打开 https://github.com/Mr-Drinking/Chromium-iOS ，图标换成链接。

标题写在代码里，按 app 实际使用的本地化（`zh_CN`、`zh_TW`）选：往 `ios_strings.grd` 加新词条会重新生成一个 ios/chrome 几乎每个文件都引用的头文件，模拟器版和真机版都得重编大半。菜单项的类型和无障碍 ID 沿用 ShareChrome，用户自定义过的菜单顺序不受影响。模拟器里验证过。

### 0032 去掉 Google 智能镜头（`ios/chrome/browser/lens_overlay/public/lens_overlay_availability_utils.mm`）

Chromium 没有 Google 镜头：它的提供方（`ios/chrome/browser/providers/lens/chromium_lens.mm`）创建不出镜头叠层、取景器和控制器，`IsLensSupported()` 返回 false。大部分入口（地址栏、键盘上方、图片的长按菜单）都检查这个函数，镜头叠层的入口却只看策略和默认搜索引擎：底栏的助手按钮显示"Google 智能镜头"，点了只会变灰；菜单里的"使用 Google 智能镜头搜索屏幕内容"点了没反应。`IsLensOverlayEntrypointAvailable()` 也检查 `IsLensSupported()` 后，助手按钮退到下一项"问问 Google"（打开 Google 的 AI 模式网页，能用），菜单项不再出现。模拟器里验证过；新标签页和地址栏本来就没有镜头按钮。

### 0033 选文件像 Safari（`ios/web/content/web_state/content_web_state.mm`、`ios/web/public/web_client.h`、`ios/chrome/browser/web/model/chrome_web_client.mm`、`choose_file/choose_file_tab_helper.mm`）

用户 2026-10-29 说上传文件和 Safari 不一样。Blink 版选文件时，content 调 `ContentWebState::RunFileChooser()`，上游直接交给 `FileSelectHelperIOS`，弹出系统的"文件"选择器（`UIDocumentPickerViewController`；上游在这里留了 TODO crbug.com/40255112）。Safari 和 WebKit 版 Chrome 都是在点的位置弹一个菜单：照片库、拍摄照片或视频、选择文件，并按 `accept` 调整。WebKit 版 Chrome 用的是自己的文件上传面板（`ios/chrome/browser/file_upload_panel`），由 WKWebView 的 `runOpenPanel` 经 `ChromeWebClient::RunOpenPanel()` 和 `ChooseFileTabHelper` 弹出。

补丁把 Blink 版的文件输入框也接到这个面板上：
- `web::WebClient` 加了 `RunFileChooser()`，带上 content 知道的输入框属性：能否多选、接受的 MIME 类型和扩展名、是否已有文件、有没有 `capture`。
- `ChromeWebClient` 据此构造面板用的 `ChooseFileEvent`。`ChooseFileTabHelper::RunFileChooser()` 像 `RunOpenPanel()` 一样，把面板放在最近一次点击的位置。
- 选中的文件按路径交回给网页（`FileSelectListener::FileSelected()`）。文件放在按标签页分开的临时目录里，关掉标签页才删，网页提交表单时读得到。
- 选文件夹和"另存为"仍用系统的文档选择器。
- Blink 只告诉我们有没有 `capture`，不说要前置还是后置摄像头，这里用后置。

模拟器里验证过（2026-10-29）：
- 没写 `accept` 的输入框在点的位置弹出"照片库 / 拍摄照片或视频 / 选择文件"；`image/*` 的第二项变成"拍摄照片"；只收 `.pdf` 的直接打开"文件"。
- 从照片库选的照片交到了网页，网页读出了全部 1,484,524 字节，开头是 JPEG 文件头；`multiple` 能一次选两张。
- 点菜单外面或取消"文件"时，网页收到 `cancel` 事件。

模拟器没有摄像头，带 `capture` 的输入框弹的仍是菜单（推测真机上会直接打开相机）。没在真机上验证。

### 0034 chrome:// 页面（`ios/web/content/init/ios_content_browser_client.cc`、`web_state/content_web_state.mm`、`js_messaging/content_web_frames_manager.mm`，以及 content 的 `navigation_url_loader_impl.cc`、`render_frame_host_impl.cc`）

用户 2026-10-29 说 chrome://credits 等打不开。Chrome iOS 的 chrome:// 页面是 iOS 自己的 WebUI，建在 ios/web 上，WebKit 版的流程是：
- `CRWWebUISchemeHandler` 通过浏览器状态（`ProfileIOS`）的网络栈取页面内容；
- 那个网络栈用 `URLDataManagerIOSBackend` 处理 chrome 协议，数据源由打开页面时创建的 WebUI 控制器注册；
- 页面里的 `chrome.send()`（`ui/webui/resources/js/ios/web_ui.js`）发到 "WebUIMessage" 处理器，交给 WebUI 的消息处理函数。

Blink 版这些都没接，一共补了四处：

1. **加载。** `IOSContentBrowserClient` 为 chrome 协议提供加载器，把请求转给浏览器状态的网络栈：导航用 `CreateNonNetworkNavigationURLLoaderFactory()`，chrome:// 页面的子资源用 `RegisterNonNetworkSubresourceURLLoaderFactories()`。
   - content 对自己的 WebUI 协议（包括 chrome）有专门的捷径，直接用它自己的 WebUI 加载器、不问嵌入方，结果是 ERR_INVALID_URL。所以在 iOS 上改了 content：导航先问嵌入方（`NavigationURLLoaderImpl::Start()`）；子资源让嵌入方的加载器顶替 content 的（`RenderFrameHostImpl` 里的 `emplace` 改成 `insert_or_assign`，循环之前表里只有那一项）。
   - 转发时去掉请求里的 DevTools 限速标识（`throttling_profile_id`）。浏览器状态的网络栈跑在 IO 线程上，而限速状态是进程级的，只能在 content 网络服务的线程上用。不去掉的话，打开过 chrome:// 页面后，下一个普通网页就会触发 `ThrottlingController` 的线程检查 DCHECK（模拟器里遇到过）。真机上没有 DCHECK，会变成两个线程同时读写（推测会出问题）。
2. **WebUI 控制器。** `ContentWebState` 在导航到 chrome:// 开始时创建 WebUI 控制器（和 `WebStateImpl` 一样），导航失败或去了别的网址时清掉。控制器里的 `MojoFacade` 要用主框架的接口绑定器，`ContentWebState` 原来返回空指针，第一个页面一加载完就崩；现在有了一个。
3. **提交权限。** content 只允许有 content WebUI 绑定的渲染进程提交 chrome:// 页面，否则当成恶意消息结束那个进程，单进程下就是结束整个 app。Chrome iOS 的 WebUI 不用这些绑定，所以在提交前（`ReadyToCommitNavigation`）给渲染进程授权 chrome 协议的提交和请求。content 在提交之后才检查（`ValidateDidCommitParams`），这时授权来得及（读源码确认）。
4. **`chrome.send()`。** `WebUIMessagingJavaScriptFeature` 处理这类消息时，会把 WebState 强转成 WebKit 版的 `WebStateImpl`，Blink 版不能用；而且 0008 只保留了翻译要的脚本功能，它本来也不在列表里。现在在 content 版的脚本消息分发处（`ContentWebFramesManager`）拦下 "WebUIMessage"，按同样的规则检查（只收主框架、chrome:// 页面、来源一致），再交给 `ContentWebState` 的 WebUI。

模拟器里验证过（2026-10-29）：
- chrome://version 显示版本、系统、用户代理和命令行，带 Chromium 标志；
- chrome://flags 列出实验功能（用 `chrome.send()` 请求，处理函数再调用页面里的 JS 返回）；
- chrome://credits 是完整的许可证列表（见第 4 节的 `generate_about_credits`）；
- 打开 chrome:// 页面后再开维基百科、GitHub、bilibili 都正常。

用 Mojo 的 WebUI（通过 `MojoFacade`）还不行：chrome://chrome-urls 只有标题、没有列表。`MojoFacade` 要在主框架里执行异步 JS（`ExecuteAsyncJavaScript`）来取页面发出的 Mojo 消息，而 Blink 版的 `ContentWebFrame` 还没实现（上游 TODO crbug.com/507056709）。没在真机上验证。

### V8 补丁 0201：让 DrumBrake 编得过（`v8/src/wasm/interpreter/…`，159 上已删）

**升到 159 后不再需要，已经删掉。** 上游 2026-10-27 自己修了下面这两处（V8 `c8b70908`「Fix build break after TrustedCast and raw() hardening」、`d1204af1`「Fix build break after SharedFunctionInfo flags move」），159 的 V8（`0388bc74`）不打补丁，DrumBrake 在模拟器和真机两种配置下都编得过，模拟器里的测试页结果正常（2026-10-29 验证过）。下面是 158 时的记录。

上游 CI 不编 DrumBrake，它就没跟上 V8 的两次接口改动（V8 2026-10-27 的 main 上这三个文件和固定版本一模一样，验证过）：

- `TrustedManaged<T>::raw()` 现在要传一个 `DisallowGarbageCollection&`。句柄（`DirectHandle`）保活、中间可能触发 GC 的地方（`Execute()` 等）改用 `unsafe_raw()`，上游别处（`wasm-objects-inl.h`）也是这么用的；只拿 `Tagged` 指针、不会 GC 的两处（`GetInterpretedStack()`、`GetFunctionIndex()`）开一个 `DisallowGarbageCollection` 再调 `raw(no_gc)`。
- `TrustedCast<T>` 现在只接受受信任类型。DrumBrake 拿它转 `WasmTableObject`、`WasmArray`、`Map`、`HeapObject` 等普通堆对象，一共 25 处，都改成 `Cast<T>`。两者都只在 DCHECK 里检查类型，行为不变；上游别处转同样的对象也用 `Cast<T>`（如 `runtime-wasm.cc`、`constant-expression-interface.cc`）。

补丁当时放在 `patches/v8/`，`series` 里写成 `src/v8:v8/0201-….patch`，打在 `src/v8` 的同名分支上，基准是 `src/DEPS` 里的 `v8_revision`（以后再有 V8 补丁也这样放）。DrumBrake 不支持新版异常处理（`try_table`/`throw_ref`）：免 JIT 时 V8 直接拒绝这种模块，网页拿到的是 `CompileError`，不会崩溃（`function-body-decoder-impl.h`）；旧版 `try`/`catch` 可以用。

模拟器里验证过（`v8_drumbrake_bounds_checks = true` 加 `--wasm-jitless`）：自己写的测试页覆盖算术、内存、表、尾调用、异常（含 `WebAssembly.JSTag`）、GC 结构和数组、SIMD，以及两个用 clang 编成 wasm32 的 C 程序，17 项全部通过；`try_table` 模块报 `CompileError`。速度：C 写的 SHA-256 和 Mandelbrot 比 JIT（Mac 上的 Chromium）慢 4–6 倍，`fib(25)` 和免 JIT 的 JS 差不多（9 ms 对 10 ms）。

### 可选补丁

- `optional/0101`：GL 实现为空时记录错误并返回空指针，而不是 `NOTREACHED()`/`CHECK` 直接崩溃。方便看日志。
- `optional/0102`：不枚举摄像头/麦克风、拒绝打开摄像头。Blinker Fluid 在 iOS 15 上遇到过重网页枚举设备导致崩溃；只有 iOS 27 上也出现时才用。

## 4. 构建参数里的取舍（`args/`）

| 参数 | 原因 |
|---|---|
| `use_blink = true`，`target_environment = simulator/device` | 主开关 |
| `ios_enable_code_signing = false`（真机） | 产出未签名的 .app，由侧载工具用你的 Apple ID 签 |
| `ios_enable_*_extension = false` 等 8 项 | 关掉 Chrome 自带的分享、小组件、密码填充等扩展；侧载时每个扩展都要占一个 App ID |
| `v8_enable_sandbox = false`，`cppgc_enable_caged_heap = false` | 两者都要预留很大的虚拟地址空间，侧载 app 未必有 extended-virtual-addressing（Blinker Fluid 在真机上用的就是这组） |
| `v8_enable_drumbrake = true` | 免 JIT 时 WebAssembly 靠 DrumBrake 解释器跑，tvOS 也是这么配的。上游 CI 不编 DrumBrake：158 的 V8 上要靠 V8 补丁 0201 才编得过，159 的 V8 上游已经修好（见第 3 节） |
| `v8_drumbrake_bounds_checks = true` | Wasm 内存访问做显式边界检查。iOS arm64 默认不做，改用 Wasm 内存四周 8 GB 的保护区加 V8 的陷阱处理器来发现越界。但 content 在 iOS 上默认不开陷阱处理器（`features::kWebAssemblyTrapHandler`），这时 DrumBrake 在第一次实例化模块时就 `CHECK` 崩溃（`wasm-interpreter.cc`），而每块 Wasm 内存预留 8 GB 地址空间，侧载 app 也未必给得起。显式检查两样都不需要，代价是访存稍慢 |
| `generate_about_credits = true` | chrome://credits 列出 Chromium 和所有第三方代码的许可证。默认只有官方构建才用 `tools/licenses/licenses.py` 生成（`components/resources/BUILD.gn`），其他构建只有一张占位页（"This is sample credits page"）。公开发布的二进制应当带上许可证，打开后 chrome://credits 是完整的列表（2026-10-29，模拟器里验证过；生成的页面 5.5 MB） |

`v8/gni/v8.gni` 里 tvOS（"runs in single process mode and is not allowed to use JIT"）的配置还有 `v8_enable_lite_mode = true`、`v8_enable_turbofan = false`。我们没开：它们能让包更小，但以后想加 JIT 就得重新编。如果内存吃紧可以试。

## 5. 和 Blinker Fluid 的关系

Blinker Fluid 编的是 `content_shell`，界面是它自己在 `content/shell/browser/shell_platform_delegate_ios.mm` 里写的（约 6600 行 UIKit）。它对 Chromium 改了 135 个文件，其中界面相关 28 个，引擎层 107 个；引擎层里约一半只是为了兼容 iOS 12–17 和 Xcode 15。我们只取"单进程出画面"这一核心思路，在 158 上重写成最小补丁；其余改动的分类和移植方法见 [patch-triage.md](patch-triage.md)。
