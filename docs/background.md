# 调研背景（2026-10）

起点：想在 iPhone 13 mini 上用 Chromium（Blink）内核的浏览器，并且界面要像 Chrome，而不是社区项目那种测试壳。

## iOS 上为什么没有真正的 Chromium

- App Store 规则要求浏览器都用系统 WebKit；iOS 上的 Chrome 也只是 WebKit 套壳。
- 2024 年起 Apple 在欧盟（后来还有日本）开放了 BrowserEngineKit，允许第三方引擎，但要向 Apple 申请专门的权限，只发给符合条件的浏览器厂商，侧载拿不到。
- TrollStore 能给侧载 app 加任意权限，但只支持到 iOS 17.0；而 BrowserEngineKit 要 iOS 17.4 起。两条路正好错开。

## 社区和官方现状

| 项目 | 情况 |
|---|---|
| [Blinker Fluid](https://github.com/Nodesclock/Blinker-Fluid)（Nodesclock，GPL-3.0） | 目前唯一能实际运行的 Blink IPA。基于 `content_shell`，界面是自己用 UIKit 手写的（单个 `shell_platform_delegate_ios.mm` 约 6600 行，图标沿用 content_shell 的位图）。主要面向 TrollStore/越狱；LiveContainer 非官方支持，有设备启动即崩的报告。v0.3.1（2026-09-09）基于 Chromium M149。 |
| [omnificate/blink-browser-ios](https://github.com/omnificate/blink-browser-ios) 及其 fork | AI 代理生成的仓库，默认构建用的是 WKWebView（即 WebKit），所谓 Blink 只是一段需要 BrowserEngineKit 的构建脚本，没有任何发布。 |
| [Neoncat-OG/Chromium-iOS](https://github.com/Neoncat-OG/Chromium-iOS) | README 只写了"之后会上传 IPA"，2025 年 7 月后无更新、无发布。 |
| Google / Igalia 的 Chrome-on-Blink | 官方原型，直接复用 Chrome iOS 的界面（`ios/web/content`）。依赖 BrowserEngineKit。参见 [Igalia 的介绍](https://blogs.igalia.com/gyuyoung/2024/08/08/chrome-ios-browser-on-blink/)。 |
| 微软 Edge 团队原型 | 2026 年 6 月在 iPhone 17 Pro Max（iOS 26.5.1）上跑过 Chromium 151，Speedometer 比 Safari 高 28.6%；研究原型，未公开，依赖 BrowserEngineKit。参见 [aldenblog](https://aldenblog.io/posts/2026-06-15/test-drive-blink-ios/)、[OWA](https://open-web-advocacy.org/blog/28-percent-faster--the-blink-prototype-that-shows-why-apples-ios-browser-engine-ban-must-end/)。 |
| [Reynard](https://github.com/minh-ton/reynard-browser)（Gecko，非 Chromium） | 完成度最高的非 WebKit 浏览器，README 有 iPhone 13 mini / iOS 26.1 截图；iOS 17.4+ 可用 AltStore/SideStore 安装，应用内用配对文件开 JIT。不是 Chromium，作为备选记录在此。 |

## 为什么选"官方 Chromium + Chrome iOS 界面"

- 用户想要的是 Chrome 原生界面。Chrome Android 的界面是 Java/Kotlin，在 iOS 上跑不了；Chrome iOS 的界面在 Chromium 开源代码里，`use_blink = true` 时官方就支持接到 Blink 上。
- 从官方最新版出发，Blinker Fluid 真正有用的只是"去掉 BrowserEngineKit、单进程出画面"的思路和少量补丁；它约一半的引擎改动是为了兼容 iOS 12–17 和 Xcode 15，我们用不上（逐文件分类见 [patch-triage.md](patch-triage.md)）。
- 官方 CI（`ios-blink-rel-fyi`）每半小时在 main 上编一次 iOS Blink，并在 iOS 27 模拟器上跑测试，说明这条路线一直有人维护。

## 设备相关的约束

- iPhone 13 mini：A15，4 GB 内存。按 [LiveContainer 文档](https://livecontainer.github.io/docs/guides/jit-support)，iOS 26 起 A15/M2 及更新机型用 StikDebug 开 JIT，需要每个 app 提供专门的 JIT 脚本（app 自己要适配）。
- 用户的手机是 iOS 27：没有 TrollStore；只能用开发证书侧载（免费 Apple ID 7 天重签）。

## 来源

- Chromium iOS 构建文档：`docs/ios/build_instructions.md`（固定版本里的 "Building Blink for iOS" 与 "Blink for tvOS" 两节）
- 官方 CI builder 配置：`infra/config/generated/builders/ci/ios-blink-rel-fyi/`（`gn-args.json`、`properties.json`、`targets/chromium.fyi.json`）
- [Blinker Fluid](https://github.com/Nodesclock/Blinker-Fluid) 及其 [Releases](https://github.com/Nodesclock/Blinker-Fluid/releases)、[LiveContainer 崩溃报告](https://github.com/Nodesclock/Blinker-Fluid/issues/26)
- [Igalia: Chrome iOS Browser on Blink](https://blogs.igalia.com/gyuyoung/2024/08/08/chrome-ios-browser-on-blink/)
- [9to5Google: First look at Google Chrome's Blink engine running on an iPhone](https://9to5google.com/2023/03/03/first-look-google-chrome-blink-engine-iphone-ios/)
- [Test Drive: Blink on iOS](https://aldenblog.io/posts/2026-06-15/test-drive-blink-ios/)、[OWA: 28% Faster](https://open-web-advocacy.org/blog/28-percent-faster--the-blink-prototype-that-shows-why-apples-ios-browser-engine-ban-must-end/)
- [Reynard](https://github.com/minh-ton/reynard-browser)、[Reynard FAQ](https://github.com/minh-ton/reynard-browser/issues/130)
- [LiveContainer JIT Support](https://livecontainer.github.io/docs/guides/jit-support)
