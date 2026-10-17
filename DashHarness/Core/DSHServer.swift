import Foundation
import UIKit
import Combine
import Darwin

/// 本机 dsh 服务的生命周期管理：
/// posix_spawn 拉起内嵌 Node 运行 `@deepseek-ai/dsh web`，
/// 从 stdout 解析端口与访问 token，交给 WKWebView 首访换 cookie 完成鉴权。
/// 附带宽表盘：健康检查、崩溃自动重启、日志尾部、诊断信息。
final class DSHServer: ObservableObject {
    static let shared = DSHServer()

    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case failed
    }

    enum Stage: Equatable {
        case idle, nodeBoot, pluginBoot, serving, failed
        var text: String {
            switch self {
            case .idle: return "准备启动"
            case .nodeBoot: return "启动内核"
            case .pluginBoot: return "加载插件"
            case .serving: return "连接界面"
            case .failed: return "启动失败"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var stage: Stage = .idle
    @Published private(set) var logTail: String = ""
    @Published private(set) var restarts: Int = 0
    @Published private(set) var lastError: String = ""
    @Published private(set) var startedAt: Date?

    private(set) var launchURL: URL?
    private(set) var baseURL: URL?
    private(set) var port: Int = 0
    private(set) var token: String = ""
    private(set) var logPath: String = ""

    private var childPID: pid_t = -1
    private var pollTimer: Timer?
    private var startBegin: Date?
    private var pollTick = 0
    private var healthFails = 0
    private var autoRestartBudget = 5

    private let queue = DispatchQueue(label: "com.cuicsi.dsh.server", qos: .userInitiated)

    // MARK: - 路径

    var homeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let u = base.appendingPathComponent("dsh", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    var workspaceURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let u = docs.appendingPathComponent("工作区", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func bundledPath(_ name: String) -> String? {
        Bundle.main.path(forResource: name, ofType: nil)
    }

    private var dshEntry: String? {
        guard let root = bundledPath("dsh") else { return nil }
        let entry = root + "/node_modules/@deepseek-ai/dsh/lib/bin.js"
        return FileManager.default.fileExists(atPath: entry) ? entry : nil
    }

    // MARK: - 启停

    func boot() {
        guard phase != .starting else { return }
        phase = .starting
        stage = .nodeBoot
        lastError = ""
        startBegin = Date()
        pollTick = 0
        healthFails = 0
        startedAt = Date()

        // 清理上次可能的残留
        killStale()
        resetLog()

        queue.async { [weak self] in
            let result = self?.spawnChild() ?? (false, "内部错误")
            DispatchQueue.main.async {
                guard let self else { return }
                if !result.0 {
                    self.phase = .failed
                    self.stage = .failed
                    self.lastError = result.1
                    self.appendLog("[app] 启动失败: \(result.1)\n")
                    return
                }
                self.startPolling()
            }
        }
    }

    func restart(reason: String = "手动重启") {
        appendLog("\n[app] ---- \(reason) ----\n")
        stopChild()
        phase = .idle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.boot()
        }
    }

    func resumeIfNeeded() {
        guard AppSettings.shared.remoteMode == false else { return }
        switch phase {
        case .ready:
            checkHealth { [weak self] ok in
                guard let self, !ok else { return }
                self.appendLog("[app] 前台健康检查失败，重启服务\n")
                self.restart(reason: "前台恢复")
            }
        case .idle, .failed:
            boot()
        case .starting:
            break
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        stopChild()
        phase = .idle
        stage = .idle
    }

    // MARK: - 拉起进程

    private func spawnChild() -> (Bool, String) {
        guard let nodePath = bundledPath("node") else {
            return (false, "App 内缺少 node 运行时")
        }
        guard let entry = dshEntry else {
            return (false, "App 内缺少 dsh 主程序 lib/bin.js")
        }
        let home = homeURL.path
        let work = workspaceURL.path
        let tmp = NSTemporaryDirectory()
        logPath = home + "/server.log"

        var args = [nodePath, entry, "web", "--no-open", "--host", "127.0.0.1"]
        args.append("--port")
        args.append("\(AppSettings.shared.preferredPort)")

        var env: [String: String] = [
            "HOME": home,
            "TMPDIR": tmp,
            "TMP": tmp,
            "TEMP": tmp,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "NODE_ENV": "production",
            "NODE_NO_WARNINGS": "1",
            "USER": "mobile",
            "LOGNAME": "mobile",
            "LANG": "zh_CN.UTF-8",
            "LC_ALL": "zh_CN.UTF-8",
            "DSH_HOME": home,
            "DSH_WORKSPACE": work,
            "DSH_BASE": (bundledPath("dsh") ?? ""),
            "PWD": work,
            "CI": "1",
        ]
        if let old = ProcessInfo.processInfo.environment["TZ"] { env["TZ"] = old }

        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        var cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        cEnv.append(nil)
        defer {
            cArgs.forEach { if let p = $0 { free(p) } }
            cEnv.forEach { if let p = $0 { free(p) } }
        }

        var actions: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&actions)
        _ = logPath.withCString { p in
            posix_spawn_file_actions_addopen(&actions, 1, p, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        }
        _ = logPath.withCString { p in
            posix_spawn_file_actions_addopen(&actions, 2, p, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        }
        // 读 /dev/null 作为 stdin，避免继承无效 fd
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, nodePath, &actions, &attr, &cArgs, &cEnv)
        posix_spawn_file_actions_destroy(&actions)
        posix_spawnattr_destroy(&attr)

        if rc != 0 {
            let reason = String(cString: strerror(rc))
            var msg = "无法启动内嵌 node：errno=\(rc) (\(reason))"
            if rc == EPERM {
                msg += "\n\n这是 iOS 的代码签名限制：侧载工具重新签名时没有给 App 内的 node 可执行文件签名。\n请在安装器（全能签/ESign）里勾选「全部可执行文件/深度签名」后重装；若仍失败，请告诉我，我切到内嵌库（libnode）版本。"
            }
            return (false, msg)
        }
        childPID = pid
        try? "\(pid)".write(toFile: home + "/pid", atomically: true, encoding: .utf8)
        appendLog("[app] node 已启动 pid=\(pid) v=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?")\n")
        return (true, "")
    }

    private func stopChild() {
        guard childPID > 0 else { return }
        killpg(childPID, SIGTERM)
        usleep(300_000)
        killpg(childPID, SIGKILL)
        kill(childPID, SIGKILL)
        appendLog("[app] 已结束 node pid=\(childPID)\n")
        childPID = -1
    }

    private func killStale() {
        // 上次进程若仍存活（极少见），先清掉
        let path = homeURL.appendingPathComponent("pid").path
        if let s = try? String(contentsOfFile: path, encoding: .utf8), let p = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(p, SIGKILL)
            print("[app] kill stale pid \(p)")
        }
    }

    private func resetLog() {
        logPath = homeURL.appendingPathComponent("server.log").path
        FileManager.default.createFile(atPath: logPath, contents: nil)
    }

    // MARK: - 启动轮询

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func tick() {
        pollTick += 1
        refreshLogTail()

        let elapsed = Date().timeIntervalSince(startBegin ?? Date())
        if port == 0 || token.isEmpty {
            parseEndpoint()
        }

        switch stage {
        case .nodeBoot where !logTail.isEmpty:
            stage = .pluginBoot
        case .pluginBoot where port > 0 && !token.isEmpty:
            stage = .serving
        default:
            break
        }

        if port > 0 && !token.isEmpty {
            checkHealth { [weak self] ok in
                guard let self else { return }
                if ok {
                    self.markReady()
                } else if elapsed > 240 {
                    self.fail("服务在 240 秒内未就绪，详见运行日志")
                }
            }
        } else if elapsed > 240 {
            fail("未获取到服务地址（240s 超时），详见运行日志")
        }

        // 进程退出检测
        if childPID > 0 && elapsed > 3 {
            var status: Int32 = 0
            let r = waitpid(childPID, &status, WNOHANG)
            if r == childPID {
                appendLog("[app] node 进程已退出 status=\(status)\n")
                childPID = -1
                if AppSettings.shared.autoRestart && autoRestartBudget > 0 {
                    autoRestartBudget -= 1
                    restarts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.restart(reason: "进程退出自动重启 #\(self?.restarts ?? 0)")
                    }
                } else {
                    fail("node 进程异常退出（status=\(status)）")
                }
            }
        }
    }

    private func markReady() {
        guard phase != .ready else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        phase = .ready
        stage = .serving
        autoRestartBudget = 5
        appendLog("[app] 服务就绪 http://127.0.0.1:\(port)\n")
        startWatchdog()
        if let p = URL(string: "http://127.0.0.1:\(port)") { baseURL = p }
        launchURL = URL(string: "http://127.0.0.1:\(port)/?token=\(token)")
    }

    private func fail(_ msg: String) {
        pollTimer?.invalidate()
        pollTimer = nil
        phase = .failed
        stage = .failed
        lastError = msg
        appendLog("[app] \(msg)\n")
    }

    // MARK: - 解析地址与 token

    private func parseEndpoint() {
        guard !logPath.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
              let text = String(data: data.suffix(64 * 1024), encoding: .utf8) else { return }

        if token.isEmpty {
            if let t = firstMatch(text, #"token=([A-Za-z0-9_\-\.]{8,})"#) {
                token = t
            }
        }
        if port == 0 {
            // 优先取带端口的本地 URL
            if let p = firstMatch(text, #"https?://(?:127\.0\.0\.1|localhost|0\.0\.0\.0):(\d{2,5})"#), let n = Int(p) {
                port = n
            } else if let p = firstMatch(text, #"--port[= ](\d{2,5})"#), let n = Int(p), n > 0 {
                port = n
            }
        }
    }

    private func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: - 健康检查与看门狗

    func checkHealth(_ completion: @escaping (Bool) -> Void) {
        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/healthz") else {
            completion(false); return
        }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.setValue("dsh-ios-probe", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        URLSession(configuration: cfg).dataTask(with: req) { _, resp, err in
            if let http = resp as? HTTPURLResponse {
                completion(http.statusCode < 500)
            } else if err == nil {
                completion(true)
            } else {
                // /healthz 可能不存在，退化为根路径探测
                self.checkRoot(completion)
            }
        }.resume()
    }

    private func checkRoot(_ completion: @escaping (Bool) -> Void) {
        guard port > 0, let url = URL(string: "http://127.0.0.1:\(port)/") else {
            completion(false); return
        }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.setValue("dsh-ios-probe", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        URLSession(configuration: cfg).dataTask(with: req) { _, resp, err in
            if let http = resp as? HTTPURLResponse {
                completion(http.statusCode < 500)
            } else {
                completion(err == nil)
            }
        }.resume()
    }

    private func startWatchdog() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { [weak self] _ in
            guard let self, self.phase == .ready else { return }
            self.checkHealth { ok in
                if ok {
                    self.healthFails = 0
                } else {
                    self.healthFails += 1
                    if self.healthFails >= 3 {
                        self.healthFails = 0
                        if AppSettings.shared.autoRestart {
                            self.restarts += 1
                            self.restart(reason: "看门狗检测到服务无响应 #\(self.restarts)")
                        }
                    }
                }
            }
        }
        if let t = pollTimer { RunLoop.main.add(t, forMode: .common) }
    }

    // MARK: - 日志

    private func refreshLogTail() {
        guard !logPath.isEmpty,
              let attrs = try? FileManager.default.attributesOfItem(atPath: logPath),
              let size = attrs[.size] as? UInt64, size > 0 else { return }
        let readBytes: UInt64 = 12 * 1024
        let offset = size > readBytes ? size - readBytes : 0
        guard let fh = FileHandle(forReadingAtPath: logPath) else { return }
        defer { try? fh.close() }
        do {
            try fh.seek(toOffset: offset)
            if let data = try fh.readToEnd(), let s = String(data: data, encoding: .utf8) {
                let lines = s.split(separator: "\n").suffix(8).joined(separator: "\n")
                if lines != logTail { logTail = lines }
            }
        } catch {}
    }

    private func appendLog(_ s: String) {
        guard !logPath.isEmpty else { return }
        if let fh = FileHandle(forWritingAtPath: logPath) {
            _ = try? fh.seekToEnd()
            try? fh.write(contentsOf: s.data(using: .utf8) ?? Data())
            try? fh.close()
        }
    }

    /// 完整日志（供日志页 / 分享）
    func fullLog() -> String {
        guard !logPath.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)) else { return "（暂无日志）" }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? "（暂无日志）" : text
    }

    func clearLog() {
        if !logPath.isEmpty { try? "".write(toFile: logPath, atomically: true, encoding: .utf8) }
        logTail = ""
    }

    // MARK: - 诊断

    func diagnostics() -> String {
        var out: [String] = []
        out.append("阶段: \(stage.text) / 状态: \(phase == .ready ? "ready" : phase == .starting ? "starting" : phase == .failed ? "failed" : "idle")")
        out.append("node 资源: \(bundledPath("node") == nil ? "❌ 缺失" : "✅")")
        out.append("dsh 资源: \(dshEntry == nil ? "❌ 缺失" : "✅")")
        out.append("进程 pid: \(childPID)")
        out.append("端口: \(port)  token: \(token.isEmpty ? "（无）" : "已获取(\(token.count)位)")")
        out.append("重启次数: \(restarts)")
        out.append("工作区: \(workspaceURL.path)")
        out.append("日志: \(logPath)")
        if !lastError.isEmpty { out.append("错误: \(lastError)") }
        out.append("—— 日志尾部 ——")
        out.append(fullLog().split(separator: "\n").suffix(30).joined(separator: "\n"))
        return out.joined(separator: "\n")
    }
}
