# 结构与补丁说明

以下路径都相对于 Chromium 的 `src/`。分析是在 `d586be9f`（158.0.8125.0）上做的；固定版本后来升到 `4558926c`（158.0.8127.0）。两者之间，补丁涉及的文件只有 `content/browser/renderer_host/render_widget_host_view_ios.{h,mm}` 有变化：上游新加了一个和补丁无关的 `ClearFocusedElement()`（验证过）。

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

### V8 补丁 0201：让 DrumBrake 编得过（`v8/src/wasm/interpreter/…`）

上游 CI 不编 DrumBrake，它就没跟上 V8 的两次接口改动（V8 2026-10-27 的 main 上这三个文件和固定版本一模一样，验证过）：

- `TrustedManaged<T>::raw()` 现在要传一个 `DisallowGarbageCollection&`。句柄（`DirectHandle`）保活、中间可能触发 GC 的地方（`Execute()` 等）改用 `unsafe_raw()`，上游别处（`wasm-objects-inl.h`）也是这么用的；只拿 `Tagged` 指针、不会 GC 的两处（`GetInterpretedStack()`、`GetFunctionIndex()`）开一个 `DisallowGarbageCollection` 再调 `raw(no_gc)`。
- `TrustedCast<T>` 现在只接受受信任类型。DrumBrake 拿它转 `WasmTableObject`、`WasmArray`、`Map`、`HeapObject` 等普通堆对象，一共 25 处，都改成 `Cast<T>`。两者都只在 DCHECK 里检查类型，行为不变；上游别处转同样的对象也用 `Cast<T>`（如 `runtime-wasm.cc`、`constant-expression-interface.cc`）。

补丁放在 `patches/v8/`，`series` 里写成 `src/v8:v8/0201-….patch`，打在 `src/v8` 的同名分支上，基准是 `src/DEPS` 里的 `v8_revision`。DrumBrake 不支持新版异常处理（`try_table`/`throw_ref`）：免 JIT 时 V8 直接拒绝这种模块，网页拿到的是 `CompileError`，不会崩溃（`function-body-decoder-impl.h`）；旧版 `try`/`catch` 可以用。

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
| `v8_enable_drumbrake = true` | 免 JIT 时 WebAssembly 靠 DrumBrake 解释器跑，tvOS 也是这么配的。DrumBrake 在固定版本的 V8 上编不过，V8 补丁 0201 修好了（见第 3 节） |
| `v8_drumbrake_bounds_checks = true` | Wasm 内存访问做显式边界检查。iOS arm64 默认不做，改用 Wasm 内存四周 8 GB 的保护区加 V8 的陷阱处理器来发现越界。但 content 在 iOS 上默认不开陷阱处理器（`features::kWebAssemblyTrapHandler`），这时 DrumBrake 在第一次实例化模块时就 `CHECK` 崩溃（`wasm-interpreter.cc`），而每块 Wasm 内存预留 8 GB 地址空间，侧载 app 也未必给得起。显式检查两样都不需要，代价是访存稍慢 |

`v8/gni/v8.gni` 里 tvOS（"runs in single process mode and is not allowed to use JIT"）的配置还有 `v8_enable_lite_mode = true`、`v8_enable_turbofan = false`。我们没开：它们能让包更小，但以后想加 JIT 就得重新编。如果内存吃紧可以试。

## 5. 和 Blinker Fluid 的关系

Blinker Fluid 编的是 `content_shell`，界面是它自己在 `content/shell/browser/shell_platform_delegate_ios.mm` 里写的（约 6600 行 UIKit）。它对 Chromium 改了 135 个文件，其中界面相关 28 个，引擎层 107 个；引擎层里约一半只是为了兼容 iOS 12–17 和 Xcode 15。我们只取"单进程出画面"这一核心思路，在 158 上重写成最小补丁；其余改动的分类和移植方法见 [patch-triage.md](patch-triage.md)。
