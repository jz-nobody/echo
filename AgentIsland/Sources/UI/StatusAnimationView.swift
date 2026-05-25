import SwiftUI
import WebKit

struct StatusAnimationView: NSViewRepresentable {
    let status: SessionStatus
    let size: CGFloat

    var animationName: String {
        switch status {
        case .idle, .completed: "idle"
        case .thinking, .reading, .editing, .executing: "running"
        case .compacting: "compacting"
        case .waitingConfirmation, .error: "asking"
        }
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        let config = WKWebViewConfiguration()
        config.preferences.setValue(false, forKey: "javaScriptCanOpenWindowsAutomatically")

        let webView = WKWebView(frame: container.bounds, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.autoresizingMask = [.width, .height]
        context.coordinator.webView = webView
        context.coordinator.currentStatus = animationName

        container.addSubview(webView)

        let html = Self.buildHTML(initialStatus: animationName)
        webView.loadHTMLString(html, baseURL: nil)

        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let name = animationName
        guard context.coordinator.currentStatus != name else { return }
        context.coordinator.currentStatus = name

        guard let webView = context.coordinator.webView else { return }
        if context.coordinator.isPageLoaded {
            webView.evaluateJavaScript("setStatus('\(name)')", completionHandler: nil)
        } else {
            context.coordinator.pendingStatus = name
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var currentStatus: String?
        var pendingStatus: String?
        var isPageLoaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            if let status = pendingStatus {
                webView.evaluateJavaScript("setStatus('\(status)')", completionHandler: nil)
                pendingStatus = nil
            }
        }
    }

    // MARK: - HTML

    private static var htmlCache: [String: String] = [:]

    static func buildHTML(initialStatus: String) -> String {
        if let cached = htmlCache[initialStatus] { return cached }

        let svgNames = ["idle", "running", "compacting", "asking"]
        var divs = ""
        for name in svgNames {
            let activeClass = name == initialStatus ? " active" : ""
            let svg = StatusSVGContent.svgContent(for: name)
            divs += "<div id=\"\(name)\" class=\"status\(activeClass)\">\(svg)</div>\n"
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; overflow: hidden; background: transparent; }
        .status {
            position: absolute; inset: 0;
            opacity: 0;
            transition: opacity 0.3s ease;
            pointer-events: none;
        }
        .status.active { opacity: 1; }
        .status svg { width: 100%; height: 100%; display: block; }
        #idle svg { transform: scale(1.35); transform-origin: center; }
        </style>
        </head>
        <body>
        \(divs)
        <script>
        function setStatus(name) {
            document.querySelectorAll('.status').forEach(function(el) {
                el.classList.remove('active');
            });
            var target = document.getElementById(name);
            if (target) target.classList.add('active');
        }
        </script>
        </body>
        </html>
        """

        htmlCache[initialStatus] = html
        return html
    }
}
