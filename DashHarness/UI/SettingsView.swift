import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var server = DSHServer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var remoteDraft: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("后台保活（静音音频）", isOn: $settings.keepAlive)
                    Toggle("显示顶部工具条", isOn: $settings.showTopBar)
                    Toggle("服务异常自动重启", isOn: $settings.autoRestart)
                } header: {
                    Text("运行")
                } footer: {
                    Text("保活用于让本机服务在切到后台时继续响应；关闭后系统会挂起 App。")
                }

                Section {
                    Toggle("连接远程 dsh", isOn: $settings.remoteMode)
                    if settings.remoteMode {
                        TextField("https://example.com/?token=…", text: $remoteEdit)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                } header: {
                    Text("模式")
                } footer: {
                    Text("远程模式不启动本机服务，直接打开你在 NAS / 云主机上跑的 dsh Web 地址。")
                }

                Section("本机服务") {
                    LabeledContent("状态") {
                        Text(server.phase == .ready ? "运行中" : server.phase == .starting ? "启动中" : server.phase == .failed ? "失败" : "未启动")
                            .foregroundColor(server.phase == .ready ? .green : .secondary)
                    }
                    LabeledContent("端口", value: server.port > 0 ? "\(server.port)" : "自动")
                    LabeledContent("重试次数", value: "\(server.restarts)")
                    if let u = server.baseURL {
                        Button {
                            UIPasteboard.general.string = u.absoluteString
                        } label: {
                            LabeledContent("复制地址", value: u.absoluteString)
                        }
                    }
                    Button(role: .destructive) {
                        server.restart(reason: "设置页重启")
                    } label: {
                        Text("重启本机服务")
                    }
                    .disabled(settings.remoteMode)
                }

                Section("数据") {
                    Button {
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        UIPasteboard.general.string = docs.path
                    } label: {
                        Text("复制数据目录路径（文件 App → 我的 iPhone → dsh助手）")
                    }
                    Button(role: .destructive) {
                        server.clearLog()
                    } label: {
                        Text("清空运行日志")
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                    LabeledContent("引擎", value: "DeepSeek Harness (dsh)")
                    LabeledContent("运行时", value: "内嵌 Node.js 22")
                    LabeledContent("工作区", value: server.workspaceURL.lastPathComponent)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { remoteDraft = settings.remoteURL }
        }
    }

    private var remoteEdit: Binding<String> {
        Binding(
            get: { remoteDraft },
            set: { remoteDraft = $0; settings.remoteURL = $0 }
        )
    }
}
