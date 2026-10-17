import SwiftUI

@main
struct DashHarnessApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings.shared
    @ObservedObject private var server = DSHServer.shared

    init() {
        // 关闭 WebView 的自动内边距，布局由页面自己负责
        UserDefaults.standard.register(defaults: [
            "WebKitDeveloperExtras": false
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(nil)
                .onAppear {
                    KeepAlive.shared.setEnabled(settings.keepAlive)
                    if !settings.remoteMode { DSHServer.shared.boot() }
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                KeepAlive.shared.ensureRunning()
                if !settings.remoteMode { DSHServer.shared.resumeIfNeeded() }
            case .background:
                // 保活开启时保持后台运行；未开启则让系统挂起
                break
            default:
                break
            }
        }
    }
}
