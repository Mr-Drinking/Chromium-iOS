# 补丁系列

写的时候基于 Chromium `d586be9f`（158.0.8125.0）。2026-10-26 固定版本升到 `4558926cce232609ce125114e633e0b3a67b793d`（158.0.8127.0）：全部补丁（含可选的）在新版本的对应文件上用 `git am --3way` 也能干净打上，没有用到 3-way 合并（验证过，在只放这些文件的临时仓库里模拟的）。`scripts/02-apply-patches.sh` 按 `series` 的顺序用 `git am --3way` 打到 `src` 的 `ios-blink-sideload` 分支上。

**状态：还没编译通过过。** 验证过的有：能在固定版本上干净打上（2026-10-27 在 Mac 上用 `scripts/02-apply-patches.sh` 实际打过 0001–0004）、用到的接口在 158 里存在（逐个核对过）、打上后 `gn gen` 能通过。

| 补丁 | 改动文件 | 作用 |
|---|---|---|
| `0001-ios-sideload-single-process-jitless-switches.patch` | `content/app/content_main.cc` | 在 tvOS 默认单进程的同一位置，给 iPhone 加 `--single-process`、V8 免 JIT 和内存相关参数 |
| `0002-ios-sideload-in-process-calayer-display.patch` | `ui/accelerated_widget_mac/ca_layer_frame_sink_provider.{h,mm}`、`ui/accelerated_widget_mac/BUILD.gn`、`gpu/ipc/service/image_transport_surface_overlay_mac.mm`、`content/browser/child_process_launcher_helper_ios.mm`、`content/browser/renderer_host/render_widget_host_view_ios.{h,mm}` | 不经 BrowserEngineKit，GPU 线程把根图层直接挂到网页视图；浏览器端用 DisplayCALayerTree 显示 CALayerParams |
| `0003-ios-sideload-wait-for-metal-device.patch` | `content/gpu/BUILD.gn`、`content/gpu/ios_sideload_metal_wait.{h,mm}`（新）、`content/gpu/in_process_gpu_thread.cc` | GPU 初始化前最多等 2 秒 Metal 设备 |
| `0004-ios-sideload-allow-building-without-app-extensions.patch` | `ios/chrome/app/BUILD.gn` | 纯构建修复：扩展全关时 `_extension_toolchain` 没被用到，GN 报错；标成 `not_needed`。2026-10-27 在 Mac 上写的，`gn gen` 验证过 |
| `optional/0101-gl-init-failure-without-abort.patch` | `ui/gl/init/gl_factory_ios.mm` | GL 不可用时记日志、返回空，而不是直接崩溃（排错用） |
| `optional/0102-disable-media-capture.patch` | `content/browser/renderer_host/media/media_devices_manager.cc`、`media/capture/video/apple/video_capture_device_avfoundation.mm` | 不枚举/不打开摄像头和麦克风（只在 iOS 27 上也因此崩溃时才用） |

详细说明见 [docs/architecture.md](../docs/architecture.md)。

## 约定

- 代码里的改动统一加 `[ios-blink-sideload]` 注释，`git grep '\[ios-blink-sideload\]'` 能找全。
- 改动尽量小，只放语义改动，不夹带格式化。
- 以后如果要改 V8 等子仓库，`series` 里写成 `src/v8:v8/0201-xxx.patch`，脚本会在 `src/v8` 里按 DEPS 的版本建分支再打。

## 来源与许可

- 补丁修改的是 Chromium（BSD 许可）；新文件沿用 Chromium 的 BSD 许可头。
- 0002/0003 的思路、`-attachContentLayer:` 这个名字，以及 0001 里按内存分档的数值，来自 [Blinker Fluid](https://github.com/Nodesclock/Blinker-Fluid)（GPL-3.0）。代码是对照 158 重写的最小改动，没有复制它的文件。

## 更新补丁

见 [docs/build-guide.md 第 7 节](../docs/build-guide.md#7-修改补丁)：在 `src` 的 `ios-blink-sideload` 分支上修改并提交，再用 `git format-patch 4558926c..HEAD` 导出覆盖这里的文件。
