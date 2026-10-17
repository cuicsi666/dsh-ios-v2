# dsh助手 iOS（V2 重构版）

把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`dsh`）装进 iPhone：
App 内嵌 Node.js 22（arm64）+ `@deepseek-ai/dsh` 全量运行时，本机 `127.0.0.1` 起服务，
SwiftUI 原生外壳 + WKWebView 渲染官方 Web UI。**不依赖任何服务器，点图标就能用。**

## V2 相对上一版的重做点

| 维度 | V1 | V2 |
|---|---|---|
| 启动 | 白屏等 30s，失败无线索 | 分阶段进度（内核/插件/界面）+ 实时日志尾行 |
| 稳定性 | 崩溃后需杀进程重开 | 看门狗 3 次探活失败自动重启 + 进程退出自愈 |
| 后台 | 一切后台即挂起 | 静音音频保活（2s 自检 / 媒体服务重置重建） |
| 移动适配 | 桌面 UI 硬塞 | viewport-fit=cover、输入框 16px 防缩放、滚动回弹抑制 |
| 文件 | 无法导出产物 | 下载接管 → 文件 App「下载」；Documents 可共享 |
| 排查 | 只能看一小段 | 运行日志页（自动刷新/复制/分享/清空）+ 诊断 |
| 远程 | 无 | 可切「远程模式」直连 NAS/云上的 dsh |

## 构建

GitHub Actions（macos-15）：复用已交叉编译的 node-for-ios → 安装并裁剪 dsh 依赖 →
冒烟测试（宿主 node 验证裁剪后仍能起服务）→ xcodegen + xcodebuild → ldid 伪签名全部 Mach-O → 无签名 IPA。

产物：`dsh助手_V2.ipa`（侧载：AltStore / 全能签 / TrollStore）。

## 结构

```
DashHarness/
  Core/DSHServer.swift     本机 Node 服务生命周期、日志、看门狗
  Core/KeepAlive.swift     后台静音音频保活
  Core/AppSettings.swift   设置
  UI/RootView.swift        启动/就绪/失败三态 + 顶部工具条
  UI/WebShellView.swift    WKWebView 容器（外链/下载/移动适配）
  UI/BootView.swift        启动页
  UI/SettingsView.swift    设置
  UI/LogView.swift         运行日志
scripts/                   图标、裁剪、装配、打包
```
