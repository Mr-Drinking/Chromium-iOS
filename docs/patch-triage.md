# Blinker Fluid 补丁分类

Blinker Fluid（[Nodesclock/Blinker-Fluid](https://github.com/Nodesclock/Blinker-Fluid)，GPL-3.0）把 Chromium Blink 移植到不带 BrowserEngineKit 权限的 iOS 上。它以“整文件替换”的形式发布（基于 Chromium 149.0.7821.0，`31dce68b`）。本表是逐文件对比官方 M149 后的分类，以及用 `tools/blinker_rebase.py` 三方合并到本项目固定版本（Chromium 158.0.8125.0，`d586be9f`）的结果。

- 不含 `content/shell/*`：那是它的界面（28 个文件，约 +1.1 万行），我们用 Chrome 自己的界面，用不上。
- “合并到 158”只说明文本上有没有冲突，不代表能编译；Blinker 的文件里还夹带不少 clang-format 格式化改动，冲突很多来自这些噪音。
- 本仓库**不收录** Blinker 的代码；需要时用 `python3 tools/blinker_rebase.py --target-src ~/chromium/src --files <路径>` 现拉现合，然后只提取语义改动，写成 `patches/` 里的最小补丁。

## 类别说明

| 类别 | 文件数 | 含义 |
|---|---|---|
| core | 11 | 单进程、不靠 BrowserEngineKit 出画面所必需（已用本项目自己的最小补丁重写，见“本项目对应”列） |
| noop | 1 | Blinker 改了但没有功能变化 |
| memory | 9 | 地址空间/内存上限相关；先看真机上 extended-virtual-addressing 是否生效、是否 OOM，再决定是否移植 |
| wasm | 3 | 免 JIT 模式下 WebAssembly 走 DrumBrake 解释器的小修；构建参数里已开 v8_enable_drumbrake |
| jit | 9 | 调试器挂载后的 V8 JIT（RX 映射 + RW 镜像）；iOS 26+ 的 A15 机型还要额外适配 StikDebug 的脚本机制，放最后 |
| fix | 9 | 通用 bug 修复/功能增强（视频、触摸、横屏尺寸、文件选择等），出现对应问题时按需移植 |
| legacy | 53 | 只为 iOS 12–17 或 Xcode 15 SDK 做的兼容；我们只支持 iOS 26+、用 Xcode 26/27，不需要 |
| diag | 3 | 诊断日志、计数器，不需要 |
| test | 7 | 测试代码的编译修正，不需要 |

## core

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `content/browser/child_process_launcher_helper_ios.mm` | +8/-4 | 干净 | 0002 | 单进程下把 BrowserEngineKit 的图层交接置空（否则编不过） |
| `content/browser/renderer_host/media/media_devices_manager.cc` | +61/-15 | 冲突 1 处 | optional/0102 | 单进程下拦截摄像头/麦克风枚举，避免崩溃（Blinker 原版夹带大量 clang-format 格式化改动） |
| `content/browser/renderer_host/render_widget_host_view_ios.h` | +12/-0 | 干净 | 0002（DisplayCALayerTree 部分） | DisplayCALayerTree 成员；另有键盘/光标度量（依赖 shell，未移植） |
| `content/browser/renderer_host/render_widget_host_view_ios.mm` | +207/-23 | 冲突 4 处 | 0002（DisplayCALayerTree 部分） | DisplayCALayerTree 接收 CALayerParams；另有点击立即派发、键盘避让（依赖 shell，未移植） |
| `content/gpu/in_process_gpu_thread.cc` | +32/-0 | 冲突 1 处 | 0003（改为不依赖 shell 的写法） | 进程内 GPU 线程启动前确保 ANGLE 拿到 Metal 设备（原本由 shell 提供钩子） |
| `gpu/ipc/service/image_transport_surface_overlay_mac.mm` | +24/-13 | 干净 | 0002（进程内挂图层部分） | GPU 线程把根 CALayer 直接挂到网页视图上（替代 BELayerHierarchy 跨进程交接） |
| `media/capture/video/apple/video_capture_device_avfoundation.mm` | +21/-2 | 干净 | optional/0102 | 单进程下禁用媒体采集，直接返回拒绝 |
| `ui/accelerated_widget_mac/BUILD.gn` | +2/-2 | 干净 | 0002 | 把 tvOS 专用的进程内图层树（display_ca_layer_tree）也编进 iPhone 版 |
| `ui/accelerated_widget_mac/ca_layer_frame_sink_provider.h` | +11/-4 | 干净 | 0002 | 网页视图改为普通 UIView（tvOS 写法），不再继承 BrowserEngineKit 的跨进程图层宿主 |
| `ui/accelerated_widget_mac/ca_layer_frame_sink_provider.mm` | +24/-0 | 干净 | 0002 | 进程内直接挂上 GPU 渲染出的 CALayer，并随旋转/布局保持铺满 |
| `ui/gl/init/gl_factory_ios.mm` | +15/-3 | 干净 | optional/0101 | EGL 初始化失败时的兜底，避免 GL 实现为空导致不出画面 |

## noop

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `components/viz/service/display/overlay_processor_interface.cc` | +4/-0 | 冲突 1 处 | 无需移植（只加了注释） | 只加了一段注释，没有功能改动 |

## memory

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `base/allocator/partition_allocator/partition_alloc.gni` | +5/-0 | 干净 | — | 地址空间不够时用更小的内存池（新增 GN 开关） |
| `base/allocator/partition_allocator/src/partition_alloc/BUILD.gn` | +1/-0 | 冲突 1 处 | — | 把上面的开关传给 PartitionAlloc |
| `base/allocator/partition_allocator/src/partition_alloc/partition_address_space.cc` | +43/-7 | 冲突 1 处 | — | extended-virtual-addressing 不生效时强制小内存池 |
| `base/allocator/partition_allocator/src/partition_alloc/partition_address_space.h` | +17/-0 | 干净 | — | 小内存池的容量定义 |
| `gin/v8_platform_page_allocator.cc` | +11/-0 | 干净 | — | 不用 MAP_JIT 方式保留地址空间（TrollStore 环境会被拒） |
| `storage/browser/blob/blob_builder_from_stream.cc` | +24/-2 | 干净 | — | 大文件上传超过阈值就写盘，防止单进程内存爆掉 |
| `third_party/blink/renderer/platform/media/multi_buffer_data_source.cc` | +16/-0 | 冲突 1 处 | — | 限制媒体缓冲占用，防止被系统 jetsam 杀掉 |
| `v8/src/base/platform/platform-posix.cc` | +28/-7 | 干净 | — | 大块保留内存不带 MAP_NORESERVE（越狱设备上内核会拒绝） |
| `v8/src/heap/code-range.cc` | +90/-0 | 干净 | — | 代码区保留失败时逐级缩小重试 |

## wasm

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `v8/src/wasm/interpreter/wasm-interpreter-runtime-inl.h` | +1/-1 | 干净 | — | DrumBrake 小修 |
| `v8/src/wasm/interpreter/wasm-interpreter.cc` | +1/-1 | 冲突 1 处 | — | DrumBrake 小修 |
| `v8/src/wasm/wasm-js.cc` | +13/-2 | 干净 | — | 免 JIT 模式下让 Wasm 走 DrumBrake 解释器 |

## jit

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `v8/src/common/code-memory-access-inl.h` | +60/-19 | 干净 | — | JIT：代码区 RX 映射 + RW 镜像写入 |
| `v8/src/common/code-memory-access.cc` | +354/-0 | 干净 | — | JIT：RW 镜像的建立与 mprotect 兜底 |
| `v8/src/common/code-memory-access.h` | +25/-0 | 干净 | — | JIT：镜像接口 |
| `v8/src/common/globals.h` | +8/-0 | 干净 | — | JIT：iOS W^X 开关 |
| `v8/src/heap/memory-allocator.cc` | +25/-2 | 干净 | — | JIT：可执行内存块头部经镜像写入 |
| `v8/src/heap/mutable-page-inl.h` | +10/-0 | 干净 | — | JIT：GC 标记经镜像写入 |
| `v8/src/heap/mutable-page.h` | +8/-0 | 干净 | — | JIT：代码页按 RX 而不是 RWX 分配 |
| `v8/src/heap/sweeper.cc` | +18/-4 | 干净 | — | JIT：清扫时经镜像清零 |
| `v8/src/wasm/wasm-code-manager.cc` | +28/-2 | 干净 | — | JIT：Wasm 代码页按 RX 提交，经镜像写入 |

## fix

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `components/input/web_input_event_builders_ios.h` | +5/-1 | 干净 | — | 触摸表修正（声明） |
| `components/input/web_input_event_builders_ios.mm` | +34/-7 | 干净 | — | 触摸点"卡死"导致之后所有触摸失效的问题 |
| `media/audio/ios/audio_session_manager_ios.mm` | +15/-6 | 干净 | — | 音频输出路由（扬声器/耳机/蓝牙）修正 |
| `third_party/blink/renderer/platform/media/web_media_player_impl.cc` | +13/-2 | 干净 | — | 旋转后全屏视频不出帧的修正 |
| `ui/accelerated_widget_mac/ca_renderer_layer_tree.mm` | +154/-41 | 冲突 6 处 | 暂未移植；0001 用 --disable-features=avfoundation-overlays 绕开 | 进程内图层树的视频层 flush、画中画等修正 |
| `ui/display/ios/screen_ios.mm` | +63/-9 | 干净 | — | 横屏时 screen.width/height 方向错误的修正 |
| `ui/shell_dialogs/BUILD.gn` | +4/-0 | 干净 | — | 文件选择器增强（构建） |
| `ui/shell_dialogs/select_file_dialog.h` | +7/-0 | 干净 | — | 文件选择器保留 accept/capture 信息 |
| `ui/shell_dialogs/select_file_dialog_ios.mm` | +238/-31 | 干净 | — | 文件选择按类型打开相册/相机/文件 |

## legacy

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `base/BUILD.gn` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `base/allocator/partition_allocator/src/partition_alloc/spinning_mutex.cc` | +8/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `base/apple/owned_objc_types.h` | +4/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `base/message_loop/message_pump_kqueue.cc` | +3/-7 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `build/config/BUILDCONFIG.gn` | +6/-2 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `components/input/native_web_keyboard_event_ios.mm` | +4/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `components/metal_util/hdr_copier_layer.mm` | +11/-3 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/BUILD.gn` | +4/-3 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/date_time_chooser/ios/date_time_chooser_coordinator.mm` | +3/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/date_time_chooser/ios/date_time_chooser_view_controller.mm` | +15/-8 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/renderer_host/ios_extended_text_input_traits.h` | +2/-2 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/renderer_host/ios_extended_text_input_traits.mm` | +0/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/renderer_host/render_widget_host_view_ios_uiview.h` | +12/-1 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/renderer_host/render_widget_host_view_ios_uiview.mm` | +1240/-45 | 冲突 4 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `content/browser/renderer_host/web_menu_runner_ios.mm` | +62/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `crypto/BUILD.gn` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `crypto/apple/unexportable_key_apple.mm` | +6/-3 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `device/bluetooth/bluetooth_low_energy_adapter_apple.mm` | +14/-0 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `device/gamepad/game_controller_gamepad.mm` | +60/-43 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ios/build/chrome_build.gni` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `media/audio/BUILD.gn` | +8/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `media/base/mac/color_space_util_mac.mm` | +27/-8 | 冲突 2 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `media/base/mac/video_frame_mac.mm` | +18/-4 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `media/capture/video/apple/video_capture_device_factory_apple.mm` | +11/-6 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `media/gpu/mac/vt_video_encode_accelerator_mac.mm` | +11/-6 | 冲突 4 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `mojo/core/channel_mac.cc` | +6/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `mojo/core/ipcz_driver/wrapped_platform_handle.cc` | +7/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `net/base/network_change_notifier_apple.mm` | +21/-4 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `net/base/platform_mime_util_apple.mm` | +59/-24 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `net/cert/cert_verify_proc_ios.cc` | +25/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `services/device/public/cpp/geolocation/location_manager_delegate.mm` | +7/-3 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `services/webnn/BUILD.gn` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `services/webnn/webnn_context_provider_impl.cc` | +5/-5 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `skia/ext/skia_utils_ios.mm` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `skia/ext/skia_utils_mac.mm` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/angle/src/libANGLE/renderer/metal/DisplayMtl.mm` | +12/-2 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/angle/src/libANGLE/renderer/metal/mtl_utils.mm` | +36/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/blink/renderer/modules/nfc/BUILD.gn` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/blink/renderer/modules/nfc/nfc_parser_ios.mm` | +3/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/blink/renderer/platform/mac/graphics_context_canvas.mm` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/crashpad/crashpad/client/crash_handler_ios.cc` | +3/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `third_party/crashpad/crashpad/util/mach/exc_server_variants.cc` | +26/-1 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/accessibility/platform/BUILD.gn` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/base/clipboard/clipboard_format_type_ios.mm` | +69/-8 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/base/resource/resource_bundle_ios.mm` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/events/devices/input_device_observer_ios.mm` | +27/-19 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/events/keycodes/keyboard_code_conversion_ios.h` | +4/-2 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/events/keycodes/keyboard_code_conversion_ios.mm` | +2/-2 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/gfx/image/image_ios.mm` | +1/-1 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/gfx/mac/color_space_util.mm` | +6/-4 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/gfx/mac/io_surface.cc` | +12/-10 | 冲突 1 处 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/gfx/mac/mtl_shared_event_fence.mm` | +8/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |
| `ui/gl/gl_display_egl.mm` | +13/-0 | 干净 | — | 只为 iOS 12–17 / Xcode 15 SDK 做的兼容 |

## diag

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `content/browser/renderer_host/browser_compositor_ios.mm` | +22/-0 | 冲突 2 处 | — | 诊断日志/计数器 |
| `gin/isolate_holder.cc` | +19/-0 | 干净 | — | 诊断日志/计数器 |
| `ui/compositor/compositor.cc` | +50/-25 | 冲突 2 处 | — | 诊断日志/计数器 |

## test

| 文件 | 改动（相对 M149） | 合并到 158 | 本项目对应 | 用途 |
|---|---|---|---|---|
| `base/test/test_support_ios.mm` | +18/-11 | 冲突 1 处 | — | 测试代码的编译修正 |
| `content/test/BUILD.gn` | +2/-0 | 干净 | — | 测试代码的编译修正 |
| `ios/chrome/browser/snapshots/model/image_file_manager_unittest.mm` | +1/-1 | 干净 | — | 测试代码的编译修正 |
| `services/shape_detection/text_detection_impl_mac_unittest.mm` | +1/-1 | 干净 | — | 测试代码的编译修正 |
| `ui/gfx/image/image_ios_unittest.mm` | +1/-1 | 干净 | — | 测试代码的编译修正 |
| `ui/gfx/image/image_unittest_util_apple.mm` | +1/-1 | 干净 | — | 测试代码的编译修正 |
| `ui/webui/BUILD.gn` | +8/-0 | 干净 | — | 测试代码的编译修正 |
