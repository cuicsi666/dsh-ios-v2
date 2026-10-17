import SwiftUI
import UIKit

struct LogView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var server = DSHServer.shared
    @State private var text: String = ""
    @State private var autoRefresh = true
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            ScrollView {
                Text(text.isEmpty ? "（暂无日志）" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .navigationTitle("运行日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Toggle("自动刷新", isOn: $autoRefresh)
                        Button { UIPasteboard.general.string = text } label: { Label("复制全部", systemImage: "doc.on.doc") }
                        ShareLink(item: text) { Label("分享", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) {
                            server.clearLog(); text = ""
                        } label: { Label("清空日志", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear { text = server.fullLog() }
            .onReceive(timer) { _ in if autoRefresh { text = server.fullLog() } }
        }
    }
}
