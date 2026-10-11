import AppKit
import SwiftUI

/// 演示模式：用真实的浮窗"打"几句示例，最后一句演示敏感内容被拦截。
/// 内容是写死的（不联网、不需要 key、不需要输入法），每次播放都一样，适合录 GIF：
///   ⌘⇧5 录屏 → open ~/Applications/Zh2En.app --args --demo
@MainActor
final class DemoPlayer {
    private let bubble = BubblePanel(recordable: true)   // 演示时允许被录屏
    private var m: BubbleModel { bubble.model }

    private struct Line {
        let zh: String, en: String, idiom: String?, note: String?, blocked: Bool
    }

    private let lines = [
        Line(zh: "今天加班加到吐了。", en: "I worked overtime today until I vomited.",
             idiom: "I'm so done with overtime today.", note: "so done = 受够了、累到不行", blocked: false),
        Line(zh: "这家店的咖啡绝了，下次还来。", en: "The coffee in this shop is amazing, come again next time.",
             idiom: "The coffee here is ridiculously good. I'm coming back for sure.",
             note: "ridiculously good = 好到离谱，比 very good 更口语", blocked: false),
        Line(zh: "我先摸会儿鱼，等下再说。", en: "I'll touch the fish for a while and talk about it later.",
             idiom: "I'm gonna slack off for a bit, talk later.", note: "slack off = 偷懒、摸鱼", blocked: false),
        Line(zh: "我的手机号是 138 1234 5678。", en: "My mobile phone number is 138 1234 5678.",
             idiom: nil, note: nil, blocked: true),
    ]

    func run() async {
        m.cloudAvailable = true
        m.cloudOn = true
        try? await Task.sleep(for: .seconds(1))
        for line in lines {
            await play(line)
            bubble.hide()
            try? await Task.sleep(for: .seconds(1.2))
        }
    }

    private func play(_ line: Line) async {
        m.en = ""; m.idiom = ""; m.note = ""; m.waiting = false; m.blocked = false
        let chars = Array(line.zh)
        // 一个字一个字地"上屏"：每两个字扫一道反光，光带随句子变长而增多
        for i in 1...chars.count {
            m.zh = String(chars[0..<i])
            m.intensity = min(1, Double(i) / 30)
            m.blocked = line.blocked && i == chars.count
            bubble.show()
            if i % 2 == 0 { bubble.typedSheen() }
            bubble.relayout()
            try? await Task.sleep(for: .milliseconds(150))
        }
        withAnimation(.smooth(duration: 0.35)) { m.en = line.en }
        bubble.relayout()
        try? await Task.sleep(for: .milliseconds(350))
        bubble.pulse()   // 一句话打完
        guard let idiom = line.idiom else {
            try? await Task.sleep(for: .seconds(3))
            return
        }
        withAnimation(.smooth(duration: 0.2)) { m.waiting = true }
        bubble.relayout()
        try? await Task.sleep(for: .milliseconds(800))   // 模拟等 DeepSeek
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
            m.waiting = false
            m.idiom = idiom
            m.note = line.note ?? ""
        }
        bubble.relayout()
        try? await Task.sleep(for: .seconds(3.5))
    }
}
