import AppKit
import SwiftUI

/// 菜单栏图标和菜单
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let controller = Controller()
    private var item: NSStatusItem!
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停翻译", action: #selector(togglePause), keyEquivalent: "")
    private let cloudItem = NSMenuItem(title: "地道版（发送到 DeepSeek）", action: #selector(toggleCloud), keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        Settings.registerDefaults()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "边打边学")

        let menu = NSMenu()
        menu.autoenablesItems = false   // 由我们自己决定哪一项可点（比如没配 key 时灰掉地道版）
        menu.delegate = self
        menu.addItem(withTitle: "边打边学 Zh2En", action: nil, keyEquivalent: "").isEnabled = false
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        for i in [pauseItem, cloudItem] { i.target = self; menu.addItem(i) }
        let reset = menu.addItem(withTitle: "浮窗回到默认位置", action: #selector(resetBubble), keyEquivalent: "")
        reset.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        controller.start()
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusLine.title = controller.status
        pauseItem.state = Settings.paused ? .on : .off
        let available = controller.cloudAvailable
        cloudItem.isEnabled = available
        cloudItem.title = available ? "地道版（发送到 DeepSeek）" : "地道版（未配置 DeepSeek key，只用系统翻译）"
        cloudItem.state = available && !Settings.localOnly ? .on : .off
        item.button?.appearsDisabled = Settings.paused
    }

    @objc private func togglePause() {
        Settings.paused.toggle()
        item.button?.appearsDisabled = Settings.paused
        controller.pauseChanged()
    }
    @objc private func resetBubble() { controller.bubble.resetPosition() }
    @objc private func toggleCloud() { Settings.localOnly.toggle(); controller.modeChanged() }
}

/// 命令行测试：不经过 Rime 和浮窗，直接测两层翻译
///   Zh2En --demo              用真实浮窗播放几句示例（录 GIF 用；不联网、不需要 key 和输入法）
///   Zh2En --test [句子…]
///   Zh2En --snapshot out.png   把浮窗画成图片（看排版用；玻璃效果画不出来）
@MainActor
enum Debug {
    static let samples = ["今天加班加到吐了。", "我先摸会儿鱼，等下再说。", "你吃了吗？"]

    static func test(_ sentences: [String]) async {
        let apple = AppleTranslator(), llm = LLMClient()
        print(llm.isConfigured ? "DeepSeek：已配置 key（\(llm.modelName)）\n" : "DeepSeek：没配置 key → 只用系统翻译\n")
        for zh in sentences.isEmpty ? samples : sentences {
            print("中文：\(zh)")
            print("直译：\(await apple.translate(zh) ?? "（失败：\(apple.lastError ?? "")）")")
            guard llm.isConfigured else { print(""); continue }
            let t0 = Date()
            do {
                let r = try await llm.idiom(for: zh)
                print(String(format: "地道：%@   (%@, %.1fs)", r.en, llm.modelName, Date().timeIntervalSince(t0)))
                print("要点：\(r.note ?? "")")
            } catch {
                print("地道版出错：\(error.localizedDescription)")
            }
            print("")
        }
    }

    static func snapshot(_ path: String, intensity: Double = 0.6, blocked: Bool = false) {
        let m = BubbleModel()
        m.blocked = blocked
        m.zh = "今天加班加到吐了。"
        m.en = "I worked overtime today until I vomited."
        m.idiom = "I'm so done with overtime today."
        m.note = "so done = 受够了、累到不行"
        m.intensity = intensity
        Offscreen.plainBackground = true
        let r = ImageRenderer(content: BubbleView(m: m).background(Color(white: 0.85)))
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("已画到 \(path)")
        }
    }
}

let args = CommandLine.arguments
if args.contains("--demo") {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let player = DemoPlayer()
        Task { @MainActor in await player.run(); exit(0) }
        app.run()
    }
} else if let i = args.firstIndex(of: "--test") {
    let sentences = Array(args[(i + 1)...])
    Task { @MainActor in
        await Debug.test(sentences)
        exit(0)
    }
    RunLoop.main.run()
} else if let i = args.firstIndex(of: "--render-candidates"), i + 1 < args.count {
    MainActor.assumeIsolated { DemoRender.candidates(args[i + 1]) }
} else if let i = args.firstIndex(of: "--render-demo"), i + 1 < args.count {
    MainActor.assumeIsolated { DemoRender.run(args[i + 1]) }
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let t = i + 2 < args.count ? Double(args[i + 2]) ?? 0.6 : 0.6
    MainActor.assumeIsolated { Debug.snapshot(args[i + 1], intensity: t, blocked: args.contains("--blocked")) }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // 只在菜单栏，不出现在 Dock
        app.run()
    }
}
