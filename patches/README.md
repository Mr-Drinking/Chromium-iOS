# 补丁系列

写的时候基于 Chromium `d586be9f`（158.0.8125.0）。2026-10-26 固定版本升到 `4558926cce232609ce125114e633e0b3a67b793d`（158.0.8127.0）：全部补丁（含可选的）在新版本的对应文件上用 `git am --3way` 也能干净打上，没有用到 3-way 合并（验证过，在只放这些文件的临时仓库里模拟的）。`scripts/02-apply-patches.sh` 按 `series` 的顺序用 `git am --3way` 打到 `src` 的 `ios-blink-sideload` 分支上。

**状态：** 0001–0011 和 V8 补丁 0201 在模拟器和真机两种配置下都编译通过，模拟器里运行、测试过（2026-10-27，验证过；各补丁的验证方法写在提交说明的 Status 里）。真机上验证过 0001–0004（用户测试：网页能显示）；0005 以后还没在真机上测过。

| 补丁 | 改动文件 | 作用 |
|---|---|---|
| `0001-ios-sideload-single-process-jitless-switches.patch` | `content/app/content_main.cc` | 在 tvOS 默认单进程的同一位置，给 iPhone 加 `--single-process`、V8 免 JIT 和内存相关参数 |
| `0002-ios-sideload-in-process-calayer-display.patch` | `ui/accelerated_widget_mac/ca_layer_frame_sink_provider.{h,mm}`、`ui/accelerated_widget_mac/BUILD.gn`、`gpu/ipc/service/image_transport_surface_overlay_mac.mm`、`content/browser/child_process_launcher_helper_ios.mm`、`content/browser/renderer_host/render_widget_host_view_ios.{h,mm}` | 不经 BrowserEngineKit，GPU 线程把根图层直接挂到网页视图；浏览器端用 DisplayCALayerTree 显示 CALayerParams |
| `0003-ios-sideload-wait-for-metal-device.patch` | `content/gpu/BUILD.gn`、`content/gpu/ios_sideload_metal_wait.{h,mm}`（新）、`content/gpu/in_process_gpu_thread.cc` | GPU 初始化前最多等 2 秒 Metal 设备 |
| `0004-ios-sideload-allow-building-without-app-extensions.patch` | `ios/chrome/app/BUILD.gn` | 纯构建修复：扩展全关时 `_extension_toolchain` 没被用到，GN 报错；标成 `not_needed`。2026-10-27 在 Mac 上写的，`gn gen` 验证过 |
| `0005-ios-sideload-system-fonts.patch` | `third_party/blink/renderer/platform/fonts/{font_cache.cc,skia/font_cache_skia.cc,ios/font_cache_ios.mm,ios/system_font_ios.h}`（新头文件）、`third_party/blink/renderer/platform/BUILD.gn`、`third_party/blink/renderer/core/css/resolver/style_builder_converter.cc` | `system-ui`、`-apple-system`、`BlinkMacSystemFont` 用 SF Pro，`ui-monospace` 用 SF Mono（还有 `ui-serif`、`ui-rounded`），并按字号设置 `opsz` 轴，字距与 Safari 一致 |
| `0006-ios-sideload-net-error-page.patch` | `ios/web/content/init/{ios_content_renderer_client.cc,BUILD.gn,DEPS}` | 主页面加载失败显示 Chrome 正版网络错误页（原来是一行 "This is an error page" 占位文字）；子框架失败显示空白，与 Safari 一致 |
| `0007-ios-sideload-accessibility-dead-view.patch` | `content/browser/renderer_host/render_widget_host_view_ios_uiview.mm` | 修上游崩溃：导航换掉视图后，无障碍系统再来查询旧视图时，WeakPtr 的 CHECK 让 app 崩溃（开着 VoiceOver 等功能时会遇到） |
| `0008-ios-sideload-enable-translate.patch` | `components/translate/core/browser/translate_manager.cc`、`ios/web/content/js_messaging/{content_web_frames_manager,content_java_script_feature_manager,content_web_frame}.mm` | 让翻译可用：没有 Google API key 也提供翻译（Google 翻译组件请求时用的是它脚本里自带的 key），并且只为翻译注入需要的网页脚本（语言检测、翻译和它们的基础脚本） |
| `0009-ios-sideload-system-proxy.patch` | `services/network/network_context.cc` | 网页请求走系统代理设置（Wi-Fi 的 HTTP 代理、PAC；模拟器里是 Mac 的代理）。原来 ios/web 不给网络服务传代理设置，网页一律直连 |
| `0010-ios-sideload-user-agent-ios-version.patch` | `components/embedder_support/user_agent_utils{,_unittest}.cc` | UA 里的 iOS 版本从上游冻结的 14_0 改成 18_7（和 iOS 27 的 Safari 一样）；14_0 会让 google.com 等网站给出简陋的旧版页面 |
| `0011-ios-sideload-overscroll-touch-cancel.patch` | `ios/chrome/browser/overscroll_actions/ui_bundled/overscroll_actions_controller.mm` | 下拉刷新的手势不再取消网页收到的触摸。原来它一识别，Blink 就收到 touchcancel，页面滚几下就停（"有点卡"） |
| `v8/0201-ios-sideload-fix-drumbrake-build.patch`（打在 `src/v8` 上） | `v8/src/wasm/interpreter/wasm-interpreter{,-runtime,-objects}.cc` | 让 V8 的 Wasm 解释器 DrumBrake 编得过：上游 CI 不编它，它没跟上 `TrustedManaged::raw()` 和 `TrustedCast<>` 的接口改动 |
| `optional/0101-gl-init-failure-without-abort.patch` | `ui/gl/init/gl_factory_ios.mm` | GL 不可用时记日志、返回空，而不是直接崩溃（排错用） |
| `optional/0102-disable-media-capture.patch` | `content/browser/renderer_host/media/media_devices_manager.cc`、`media/capture/video/apple/video_capture_device_avfoundation.mm` | 不枚举/不打开摄像头和麦克风（只在 iOS 27 上也因此崩溃时才用） |

详细说明见 [docs/architecture.md](../docs/architecture.md)。

## 约定

- 代码里的改动统一加 `[ios-blink-sideload]` 注释，`git grep '\[ios-blink-sideload\]'` 能找全。
- 改动尽量小，只放语义改动，不夹带格式化。
- V8 等子仓库的补丁放在对应子目录，`series` 里写成 `src/v8:v8/0201-xxx.patch`，脚本会在 `src/v8` 里按 DEPS 的版本建分支再打。导出时的基准也是 DEPS 里的版本（V8 现在是 `f7be3c62`）。

## 来源与许可

- 补丁修改的是 Chromium（BSD 许可）；新文件沿用 Chromium 的 BSD 许可头。
- 0002/0003 的思路、`-attachContentLayer:` 这个名字，以及 0001 里按内存分档的数值，来自 [Blinker Fluid](https://github.com/Nodesclock/Blinker-Fluid)（GPL-3.0）。代码是对照 158 重写的最小改动，没有复制它的文件。

## 更新补丁

见 [docs/build-guide.md 第 7 节](../docs/build-guide.md#7-修改补丁)：在 `src` 的 `ios-blink-sideload` 分支上修改并提交，再用 `git format-patch 4558926c..HEAD` 导出覆盖这里的文件。
