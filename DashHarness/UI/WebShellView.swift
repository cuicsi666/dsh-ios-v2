import SwiftUI
import UIKit
import WebKit

/// 官方 dsh Web UI 的全屏容器。
/// 只做三件事：注入移动端适配样式、接管外链/下载、把加载状态回报给外壳。
struct WebShellView: UIViewRepresentable {
    let url: URL
    let reloadID: UUID
    var onFinish: () -> Void = {}
    var onFail: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.websiteDataStore = .default()
        cfg.applicationNameForUserAgent = "dsh-ios/2.0"
        cfg.userContentController.addUserScript(WKUserScript(
            source: Self.bootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true))
        cfg.userContentController.addUserScript(WKUserScript(
            source: Self.cssJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true))

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.showsVerticalScrollIndicator = false
        web.allowsLinkPreview = true
        web.customUserAgent = nil
        context.coordinator.webView = web
        context.coordinator.load(url: url)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.loadedID != reloadID {
            context.coordinator.load(url: url)
        }
    }

    // 移动端引导：viewpoort-fit=cover + 禁用双击缩放
    static let bootstrapJS = """
    (function () {
      try {
        var m = document.querySelector('meta[name="viewport"]');
        if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
        var c = m.getAttribute('content') || '';
        if (c.indexOf('viewport-fit') < 0) c += ', viewport-fit=cover';
        if (c.indexOf('maximum-scale') < 0) c += ', maximum-scale=5';
        m.setAttribute('content', c);
      } catch (e) {}
    })();
    """

    // 视觉适配：安全区、滚动回弹、输入框字号（防止 iOS 自动放大）
    static let cssJS = """
    (function () {
      try {
        var s = document.createElement('style');
        s.id = '__dsh_ios_fix';
        s.textContent = `
          html, body { overscroll-behavior: none; -webkit-text-size-adjust: 100%; }
          input, textarea, select { font-size: 16px !important; }
          ::-webkit-scrollbar { width: 0; height: 0; }
          @media (max-width: 820px) {
            :root { --dsh-ios-safe-top: env(safe-area-inset-top, 0px); }
          }
        `;
        if (!document.getElementById('__dsh_ios_fix')) document.head.appendChild(s);
      } catch (e) {}
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        var parent: WebShellView
        weak var webView: WKWebView?
        var loadedID: UUID?
        private var retries = 0

        init(_ p: WebShellView) { parent = p }

        func load(url: URL) {
            loadedID = parent.reloadID
            retries = 0
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            webView?.load(req)
        }

        private func allowed(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "about" || scheme == "data" || scheme == "blob" || scheme == "javascript" { return true }
            guard scheme == "http" || scheme == "https" else { return false }
            let host = url.host?.lowercased() ?? ""
            if host == "127.0.0.1" || host == "localhost" { return true }
            // 远程模式下允许同源跳转
            if AppSettings.shared.remoteMode,
               let base = parent.url.host?.lowercased(), host == base { return true }
            return false
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = navigationAction.request.url else { decisionHandler(.allow); return }
            if allowed(u) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                UIApplication.shared.open(u)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {}

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retries = 0
            parent.onFinish()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            retryIfNeeded(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryIfNeeded(error)
        }

        private func retryIfNeeded(_ error: Error) {
            parent.onFail()
            let ns = error as NSError
            // 服务未就绪时的连接失败 → 自动重试
            if ns.code == -1004 || ns.code == -1001 || ns.code == -1003 {
                guard retries < 20 else { return }
                retries += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, let w = self.webView else { return }
                    w.load(URLRequest(url: self.parent.url))
                }
            }
        }

        // target=_blank / window.open
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let u = navigationAction.request.url, allowed(u) {
                webView.load(navigationAction.request)
            } else if let u = navigationAction.request.url {
                UIApplication.shared.open(u)
            }
            return nil
        }

        // 下载（产物文件 / 导出）
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let fm = FileManager.default
            let base = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("下载", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            var dest = base.appendingPathComponent(suggestedFilename.isEmpty ? "download" : suggestedFilename)
            var i = 1
            while fm.fileExists(atPath: dest.path) {
                let name = (suggestedFilename as NSString).deletingPathExtension
                let ext = (suggestedFilename as NSString).pathExtension
                dest = base.appendingPathComponent("\(name)-\(i)" + (ext.isEmpty ? "" : ".\(ext)"))
                i += 1
            }
            completionHandler(dest)
        }

        func downloadDidFinish(_ download: WKDownload) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            NSLog("[WebShell] 下载失败 %@", "\(error)")
        }
    }
}
