import Foundation
import SwiftUI

/// 全局设置（UserDefaults 持久化）
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    enum Key {
        static let keepAlive = "keepAlive"           // 后台音频保活
        static let showTopBar = "showTopBar"         // 顶部原生工具条
        static let remoteMode = "remoteMode"         // 远程模式
        static let remoteURL = "remoteURL"           // 远程 dsh 地址
        static let autoRestart = "autoRestart"       // 崩溃自动重启
        static let preferredPort = "preferredPort"   // 固定端口（0=自动）
    }

    @AppStorage(Key.keepAlive) var keepAlive: Bool = true { didSet { KeepAlive.shared.setEnabled(keepAlive) } }
    @AppStorage(Key.showTopBar) var showTopBar: Bool = true { didSet { objectWillChange.send() } }
    @AppStorage(Key.remoteMode) var remoteMode: Bool = false { didSet { objectWillChange.send() } }
    @AppStorage(Key.remoteURL) var remoteURL: String = ""
    @AppStorage(Key.autoRestart) var autoRestart: Bool = true
    @AppStorage(Key.preferredPort) var preferredPort: Int = 3280

    private init() {}
}
