import AppKit
import WebKit

// usage: swift snap.swift file.html out.png width dark|light
let args = CommandLine.arguments
let url = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let width = CGFloat(Double(args[3]) ?? 390)
let dark = args.count > 4 && args[4] == "dark"

final class Delegate: NSObject, WKNavigationDelegate {
    let done: (WKWebView) -> Void
    init(_ done: @escaping (WKWebView) -> Void) { self.done = done }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done(webView) }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 800))
web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
let window = NSWindow(contentRect: web.frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.appearance = web.appearance
window.contentView = web
let delegate = Delegate { web in
    web.evaluateJavaScript("document.documentElement.scrollHeight") { h, _ in
        let height = CGFloat((h as? Double) ?? 800)
        web.frame = NSRect(x: 0, y: 0, width: width, height: height)
        window.setContentSize(web.frame.size)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = NSRect(x: 0, y: 0, width: width, height: height)
            web.takeSnapshot(with: cfg) { image, _ in
                if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: out)
                    print("wrote \(out.path) \(Int(width))x\(Int(height))")
                } else { print("snapshot failed") }
                exit(0)
            }
        }
    }
}
web.navigationDelegate = delegate
web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { print("timeout"); exit(1) }
app.run()
