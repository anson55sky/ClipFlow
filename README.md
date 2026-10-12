# ClipFlow

原生 macOS 视频剪辑工作台 —— 双击打开即是一个真正的 macOS 原生窗口（WKWebView 外壳），内部自动启动本地服务并加载编辑器，体验等同普通 Mac 应用（自带窗口、Dock 图标、⌘Q 退出即关服务）。

> 本仓库是 ClipFlow 的原生外壳 + 全量重品牌工具链。内置的 web 编辑器基于 MIT 许可的开源项目 [`@ffclip-com/videocut`](https://www.npmjs.com/package/@ffclip-com/videocut)，通过 `rebrand.sh` 完成品牌化（界面文案、关于页、二维码、演示项目名等），原项目的 LICENSE 与 THIRD_PARTY_NOTICES 随分发包完整保留。

## 功能

- 🖥️ **原生窗口**：Swift + WKWebView 实现，非浏览器标签页。
- 🔌 **自动拉起本地服务**：内嵌 node 二进制（arm64 + x86_64），启动后自动解析预览地址并加载。
- 🧭 **中文路径兼容**：对含中文/非 ASCII 的本地预览地址做百分号编码，规避白屏。
- 📄 **日志与诊断**：服务输出落盘 `~/Library/Logs/ClipFlow-server.log`，应用日志 `~/Library/Logs/ClipFlow.log`；启动超时/失败时窗口内直接展示已捕获输出与日志路径。
- 🎬 **开箱即用**：默认加载内置中文演示项目，无需手动打开文件。

## 构建

要求：macOS 13+，已安装 Xcode / Swift 工具链与 Node.js（npm）。

```bash
# 1. 安装编辑器核心（MIT）
npm install -g @ffclip-com/videocut

# 2. 构建通用二进制 .app（自动下载 node、自动应用重品牌补丁）
./build-videocut-native.sh

# 产物：./ClipFlow.app（arm64 + x86_64）
```

环境变量可覆盖默认值：`APP_VERSION`、`NODE_VERSION`、`MIN_MACOS`、`SWIFTC`、`INCLUDE_X64_NODE` 等，详见脚本头部。

## 重品牌（rebrand.sh）

`rebrand.sh <目录>` 对编辑器副本（含 `web/ server/ bin/`）做全量品牌替换：

- 界面文案：顶栏 logo、`<title>`、关于弹窗、窗口标题、更新提示显示名等；
- 演示项目名：`ClipFlow · 演示项目`；
- 二维码：关于弹窗两张二维码替换为 GitHub 指向；
- **机制字符串受保护**：npm 包名 `@ffclip-com/videocut`、更新临时目录 `.ffclip-update-` 不会被误改，更新机制保持可用。

构建脚本会在拷贝编辑器后自动调用它，因此每次构建产物都是品牌化后的。

## 目录结构

```
├── main.swift                 # 原生外壳（WKWebView + 本地服务管理）
├── build-videocut-native.sh   # 构建脚本（swiftc 直编，无 Xcode 工程）
├── rebrand.sh                 # 全量重品牌补丁
├── AppIcon.icns               # 应用图标
└── AppIcon.iconset/           # 图标源集
```

## 致谢与许可

- 编辑器核心：[@ffclip-com/videocut](https://www.npmjs.com/package/@ffclip-com/videocut)（MIT），其浏览器音视频实现引用并改编了 [WebAV](https://github.com/bilibili/WebAV)（MIT，感谢作者风痕及社区贡献者）；媒体引擎使用 [Mediabunny](https://mediabunny.dev)（MPL-2.0）；动画使用 GSAP。
- 完整声明及许可证随安装包提供（`Resources/app/licenses/`、`THIRD_PARTY_NOTICES.md`）。

## License

[MIT](LICENSE) © 2026 anson55sky
