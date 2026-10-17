import SwiftUI

/// 启动过程页面：真实阶段 + 日志尾行，避免「白屏等半天」
struct BootView: View {
    let stageText: String
    let detail: String
    let failed: Bool
    var onRetry: () -> Void
    var onLogs: () -> Void

    @State private var pulse = false
    @State private var seconds = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.42, blue: 0.98),
                                                  Color(red: 0.13, green: 0.20, blue: 0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.blue.opacity(0.28), radius: 18, y: 8)
                Image(systemName: failed ? "exclamationmark.triangle.fill" : "sparkles")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(pulse ? 1.06 : 0.94)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            }
            .onAppear { pulse = true }

            Text("DeepSeek Harness")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .padding(.top, 20)
            Text(failed ? "启动遇到问题" : stageText)
                .font(.system(size: 14))
                .foregroundColor(failed ? .red : .secondary)
                .padding(.top, 6)

            if !failed {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("\(seconds)s")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 14)
            }

            if !detail.isEmpty {
                ScrollView {
                    Text(detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 120)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 28)
                .padding(.top, 18)
            }

            if failed {
                VStack(spacing: 10) {
                    Button(action: onRetry) {
                        Text("重新启动").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(.white)
                    }
                    Button("查看运行日志", action: onLogs)
                        .font(.footnote)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
            }

            Spacer()
            Text("首次启动需要加载插件，约 10-30 秒")
                .font(.system(size: 11))
                .foregroundColor(Color(uiColor: .tertiaryLabel))
                .padding(.bottom, 24)
        }
        .onReceive(timer) { _ in seconds += 1 }
    }
}
