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
| `--js-flags=--jitless --wasm-jitless --max-old-space-size=… --max-semi-space-size=…` | V8 不生成机器码；堆上限按内存分档，4 GB 机型是 384/16 MB（沿用 Blinker Fluid 的实测值） |
| `--disable-gpu-watchdog` | 单进程里 GPU 看门狗杀掉慢线程等于杀掉整个 app |
| `--force-gpu-mem-available-mb=384`（4 GB 机型） | 限制图块缓存，避免重网页把进程推过 jetsam 上限 |
| `--enable-features=WebContentsDiscard` | 允许丢弃后台标签页 |
| `--disable-features=avfoundation-overlays,BackForwardCache` | 原生视频层要额外修复才能在进程内图层树里正常显示；前进后退缓存会把整页留在内存里 |

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
| `v8_enable_drumbrake = true` | 免 JIT 时 WebAssembly 用 DrumBrake 解释器跑；`v8/gni/v8.gni` 里 tvOS 也是这么配的 |

`v8/gni/v8.gni` 里 tvOS（"runs in single process mode and is not allowed to use JIT"）的配置还有 `v8_enable_lite_mode = true`、`v8_enable_turbofan = false`。我们没开：它们能让包更小，但以后想加 JIT 就得重新编。如果内存吃紧可以试。

## 5. 和 Blinker Fluid 的关系

Blinker Fluid 编的是 `content_shell`，界面是它自己在 `content/shell/browser/shell_platform_delegate_ios.mm` 里写的（约 6600 行 UIKit）。它对 Chromium 改了 135 个文件，其中界面相关 28 个，引擎层 107 个；引擎层里约一半只是为了兼容 iOS 12–17 和 Xcode 15。我们只取"单进程出画面"这一核心思路，在 158 上重写成最小补丁；其余改动的分类和移植方法见 [patch-triage.md](patch-triage.md)。
