import Foundation
import AVFoundation
import UIKit

/// 后台保活：用静音音频让 App 保持运行，保证本机 dsh 服务随时可用。
/// 采用 AVAudioEngine + 全零 PCM 源（比播放静音文件更稳），并做健康自检与媒体服务重置重建。
final class KeepAlive {
    static let shared = KeepAlive()

    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var timer: Timer?
    private(set) var enabled = false
    private(set) var recoverCount = 0

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(mediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBack), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        on ? start() : stop()
    }

    /// App 回到前台时纠偏（iOS 可能在后台中断音频）
    func ensureRunning() {
        guard enabled else { return }
        if engine?.isRunning != true { rebuild() }
    }

    @objc private func appBack() { ensureRunning() }

    @objc private func mediaServicesReset() {
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.rebuild()
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            NSLog("[KeepAlive] audio session 失败: %@", "\(error)")
        }
        build()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, self.enabled else { return }
            if self.engine?.isRunning != true {
                self.recoverCount += 1
                self.rebuild()
            }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    private func build() {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in abl {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.0
        do {
            try engine.start()
            self.engine = engine
            self.source = source
        } catch {
            NSLog("[KeepAlive] engine 启动失败: %@", "\(error)")
            self.engine = nil
            self.source = nil
        }
    }

    private func rebuild() {
        teardown()
        build()
    }

    private func teardown() {
        source.map { engine?.detach($0) }
        engine?.stop()
        source = nil
        engine = nil
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        teardown()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
