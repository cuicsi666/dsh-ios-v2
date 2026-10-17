import SwiftUI
import UIKit

/// 启动页 / 首页：负责在「启动中 / 就绪 / 失败」之间切换
struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var server = DSHServer.shared
    @State private var showSettings = false
    @State private var showLog = false
    @State private var showDiagnostics = false
    @State private var reloadID = UUID()
    @State private var webFinished = false

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if settings.remoteMode, let u = remoteURL {
                webLayer(url: u)
            } else {
                switch server.phase {
                case .ready:
                    if let u = server.launchURL {
                        webLayer(url: u)
                    } else {
                        BootView(stageText: "未获取到界面地址", detail: server.logTail, failed: true,
                                 onRetry: { server.restart(reason: "重新获取地址") },
                                 onLogs: { showLog = true })
                    }
                case .failed:
                    BootView(stageText: server.lastError.isEmpty ? "启动失败" : server.lastError,
                             detail: server.logTail, failed: true,
                             onRetry: { server.restart(reason: "用户点重试") },
                             onLogs: { showLog = true })
                default:
                    BootView(stageText: server.stage.text, detail: server.logTail, failed: false,
                             onRetry: {}, onLogs: { showLog = true })
                }
            }

            if settings.showTopBar, showBar {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLog) { LogView() }
        .onAppear {
            if settings.remoteMode == false && server.phase == .idle { server.boot() }
        }
        .onChange(of: settings.remoteMode) { _ in
            if settings.remoteMode { server.stop() } else { server.boot() }
        }
    }

    private var showBar: Bool {
        if settings.remoteMode { return true }
        return server.phase == .ready
    }

    private var remoteURL: URL? {
        let s = settings.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let u = URL(string: s), u.scheme != nil { return u }
        return URL(string: "https://\(s)")
    }

    // MARK: - Web 层

    @ViewBuilder
    private func webLayer(url: URL) -> some View {
        ZStack {
            WebShellView(url: url, reloadID: reloadID, onFinish: { webFinished = true }, onFail: { webFinished = false })
            if !webFinished {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在打开工作台…").font(.footnote).foregroundColor(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    // MARK: - 顶部工具条

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(server.phase == .ready ? Color.green : (server.phase == .failed ? Color.red : Color.orange))
                .frame(width: 8, height: 8)
            Text("dsh")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if settings.remoteMode {
                Text("远程").font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: Capsule())
                    .foregroundColor(.blue)
            }
            Spacer()
            Button {
                reloadID = UUID()
                webFinished = false
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            Menu {
                Button { reloadID = UUID(); webFinished = false } label: { Label("刷新界面", systemImage: "arrow.clockwise") }
                if !settings.remoteMode {
                    Button { server.restart(reason: "菜单重启") } label: { Label("重启服务", systemImage: "power") }
                }
                Button { showLog = true } label: { Label("运行日志", systemImage: "text.alignleft") }
                Button { copyAddress() } label: { Label("复制地址", systemImage: "doc.on.doc") }
                if let u = currentURL { Button { UIApplication.shared.open(u) } label: { Label("在 Safari 打开", systemImage: "safari") } }
                Divider()
                Button { showSettings = true } label: { Label("设置", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 17, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var currentURL: URL? {
        settings.remoteMode ? remoteURL : server.launchURL
    }

    private func copyAddress() {
        guard let u = currentURL else { return }
        UIPasteboard.general.string = u.absoluteString
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }
}
