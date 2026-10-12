import Foundation
import AppKit
import WebKit

/// ClipFlow 原生外壳：双击启动后，先在本进程内拉起本地 Node 服务，
/// 解析其输出的预览地址，再用 WKWebView 在原生窗口里加载编辑器。
/// 体验等同普通 macOS App（自带窗口、Dock 图标、⌘Q 退出即关服务）。
final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var serverTask: Process?
    var loaded = false
    var serverOutput = ""
    static let sourceRepoURL = "https://github.com/anson55sky/ClipFlow"

    let libDir: String = {
        NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? NSHomeDirectory()
    }()
    var logPath: String { (libDir as NSString).appendingPathComponent("Logs/ClipFlow.log") }
    var serverLogPath: String { (libDir as NSString).appendingPathComponent("Logs/ClipFlow-server.log") }

    func log(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = FileHandle(forWritingAtPath: logPath) {
            fh.seekToEndOfFile()
            fh.write(data)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("=== ClipFlow 原生窗口启动 ===")
        let rect = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "ClipFlow"
        window.setFrameAutosaveName("ClipFlowMainWindow")
        window.center()

        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: rect, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.navigationDelegate = self
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        webView.loadHTMLString("<h1 style='font-family:sans-serif;padding:24px'>ClipFlow 正在启动本地服务…</h1>", baseURL: nil)
        startServer()
    }

    /// 按架构选择内嵌的 node 二进制（Contents/MacOS/node-arm64 或 node-x64）
    func nodeURL() -> URL {
        let macos = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
        var u = utsname()
        uname(&u)
        let size = MemoryLayout.size(ofValue: u.machine)
        let machine = withUnsafePointer(to: &u.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: size) {
                String(cString: $0)
            }
        }
        let name = (machine == "arm64") ? "node-arm64" : "node-x64"
        return macos.appendingPathComponent(name)
    }

    func startServer() {
        let node = nodeURL()
        log("node 可执行文件: \(node.path) 存在=\(FileManager.default.fileExists(atPath: node.path))")
        let mjs = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/app/dist/bin/videocut.mjs")
        log("mjs 路径: \(mjs.path) 存在=\(FileManager.default.fileExists(atPath: mjs.path))")
        guard FileManager.default.fileExists(atPath: mjs.path) else {
            log("错误：找不到 videocut.mjs")
            webView.loadHTMLString("<h1>找不到 videocut.mjs</h1><p><code>\(mjs.path)</code></p>", baseURL: nil)
            return
        }
        let root = (NSHomeDirectory() as NSString).appendingPathComponent("ffclip-projects")

        let task = Process()
        task.executableURL = node
        // 注意：不带 --open，由本原生窗口自行加载预览；默认加载内置中文示例以便开箱即用
        task.arguments = [mjs.path, "--demo", "--demo-locale", "zh", "--port", "0", "--root", root]
        // 清理可能干扰内嵌 node 的环境变量（如某些外壳注入的 NODE_OPTIONS shim）
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "NODE_OPTIONS")
        task.environment = env

        // 将服务输出重定向到文件（比 Pipe 更可靠：Node 对文件同步落盘，headless 也能捕获）
        FileManager.default.createFile(atPath: serverLogPath, contents: nil)
        guard let outFH = FileHandle(forWritingAtPath: serverLogPath) else {
            webView.loadHTMLString("<h1>无法创建服务日志文件</h1>", baseURL: nil)
            return
        }
        task.standardOutput = outFH
        task.standardError = outFH

        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.log("本地服务进程已退出")
                if let self = self, !self.loaded {
                    self.renderFatal("本地服务已停止", "服务进程意外退出，请查看日志：\(self.logPath)\n服务输出：\(self.serverLogPath)")
                }
            }
        }
        do {
            try task.run()
            log("本地服务启动成功，PID=\(task.processIdentifier)")
        } catch {
            log("启动失败: \(error.localizedDescription)")
            webView.loadHTMLString("<h1>无法启动本地服务: \(error.localizedDescription)</h1>", baseURL: nil)
            return
        }
        serverTask = task

        // 超时兜底：若 20 秒内未解析到地址，展示已捕获的服务输出，避免白屏
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, !self.loaded else { return }
            self.log("超时：20 秒内未解析到预览地址")
            self.renderFatal("启动超时", "未能从服务输出中解析到预览地址。\n\n已捕获输出：\n\(self.serverOutput)\n\n服务日志：\(self.serverLogPath)")
        }

        // 后台线程轮询服务日志文件，捕获 "ClipFlow: http://..." 行
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var lastLen = 0
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline {
                usleep(200_000)
                guard let content = try? String(contentsOfFile: self?.serverLogPath ?? "", encoding: .utf8) else { continue }
                if content.count > lastLen {
                    let start = content.index(content.startIndex, offsetBy: min(lastLen, content.count), limitedBy: content.endIndex) ?? content.endIndex
                    let delta = String(content[start...])
                    lastLen = content.count
                    let trimmed = delta.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        DispatchQueue.main.async { self?.handleServerOutput(delta) }
                    }
                }
                if self?.loaded == true { break }
            }
            DispatchQueue.main.async { self?.log("服务日志轮询结束") }
        }
    }

    /// 处理服务输出的一块：记录日志并尝试解析预览地址并加载
    func handleServerOutput(_ str: String) {
        serverOutput += str
        log("服务输出: \(str.trimmingCharacters(in: .newlines))")
        guard !loaded else { return }
        if let url = AppDelegate.parseURL(from: str) {
            loaded = true
            log("解析到预览地址: \(url.absoluteString)")
            webView.load(URLRequest(url: url))
        }
    }

    /// 从输出文本中提取本地预览地址（优先 127.0.0.1，其次 localhost，含路径）
    /// 注意：路径可能含非 ASCII（如中文项目名），URL(string:) 会返回 nil，
    /// 必须对路径做百分号编码后才能成功构造 URL，否则窗口一直白屏。
    static func parseURL(from text: String) -> URL? {
        let patterns = [
            "https?://127\\.0\\.0\\.1:\\d+[^\\s]*",
            "https?://localhost:\\d+[^\\s]*"
        ]
        for pat in patterns {
            if let regex = try? NSRegularExpression(pattern: pat),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                let raw = String(text[range])
                if let u = AppDelegate.encodedURL(from: raw) { return u }
            }
        }
        return nil
    }

    /// 将可能含非 ASCII 的 URL 字符串编码为合法 URL（仅对路径部分做百分号编码）
    static func encodedURL(from raw: String) -> URL? {
        if let u = URL(string: raw) { return u }
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: ":/?=&#@+")
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed),
              let u = URL(string: encoded) else { return nil }
        return u
    }

    func renderFatal(_ title: String, _ detail: String) {
        let escaped = detail.replacingOccurrences(of: "<", with: "&lt;")
        let html = "<html><body style='font-family:sans-serif;padding:24px'><h1>\(title)</h1><pre style='white-space:pre-wrap'>\(escaped)</pre><p>日志：\(logPath)</p><p>服务日志：\(serverLogPath)</p><p>开源地址：\(AppDelegate.sourceRepoURL)</p></body></html>"
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log("加载失败(provisional): \(error.localizedDescription)")
        renderFatal("页面加载失败", "\(error.localizedDescription)\n\n日志：\(logPath)\n服务日志：\(serverLogPath)")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("加载失败: \(error.localizedDescription)")
        renderFatal("导航失败", "\(error.localizedDescription)\n\n日志：\(logPath)\n服务日志：\(serverLogPath)")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("页面加载完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverTask?.terminate()
        serverTask?.waitUntilExit()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
