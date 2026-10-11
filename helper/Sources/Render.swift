import AppKit
import SwiftUI

/// 离线渲染演示 GIF 的每一帧：不录屏、不需要任何权限。
/// 背景是固定的示意壁纸，所以不会把你屏幕上的东西（聊天、文档）录进去。
///   Zh2En --render-demo 输出目录      → 输出目录/frame_0001.png …
/// 再用 ffmpeg 合成 GIF（命令见 docs/how-it-works.md）。离屏画不出液态玻璃，用半透明白底模拟。
/// 离屏渲染（截图、演示 GIF、宣传片）时用的两个开关
@MainActor
enum Offscreen {
    static var plainBackground = false   // 离屏画不出液态玻璃，换成半透明白底
    static var frameDate: Date?          // 虚拟时钟：逐帧渲染时代替真实时间
}

@MainActor
enum DemoRender {
    static let fps = 15.0
    static let canvas = CGSize(width: 900, height: 250)

    private struct Line {
        let zh: String, en: String, idiom: String?, note: String?
    }

    private static let lines = [
        Line(zh: "今天加班加到吐了。", en: "I worked overtime today until I vomited.",
             idiom: "I'm so done with overtime today.", note: "so done = 受够了、累到不行"),
        Line(zh: "我先摸会儿鱼，等下再说。", en: "I'll touch the fish for a while and talk about it later.",
             idiom: "I'm gonna slack off for a bit, talk later.", note: "slack off = 偷懒、摸鱼"),
        Line(zh: "我的手机号是 138 1234 5678。", en: "My mobile phone number is 138 1234 5678.",
             idiom: nil, note: nil),   // 敏感内容：只出直译，不发云端
    ]

    static func run(_ dir: String) {
        Offscreen.plainBackground = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let m = BubbleModel()
        m.cloudAvailable = true
        m.cloudOn = true
        m.animating = true
        var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)   // 虚拟时钟：每帧前进 1/fps 秒
        var count = 0
        var opacity = 0.0

        func frame() {
            Offscreen.frameDate = clock
            let scene = ZStack {
                Wallpaper()
                BubbleView(m: m).opacity(opacity)
            }
            .frame(width: canvas.width, height: canvas.height)
            let r = ImageRenderer(content: scene)
            r.scale = 2
            count += 1
            if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appending(path: String(format: "frame_%04d.png", count)))
            }
            clock += 1 / fps
        }
        /// 持续 seconds 秒，每帧先调用 each(进度 0…1) 再画
        func hold(_ seconds: Double, _ each: (Double) -> Void = { _ in }) {
            let k = max(1, Int((seconds * fps).rounded()))
            for i in 1...k { each(Double(i) / Double(k)); frame() }
        }

        hold(0.4)
        for line in lines {
            m.zh = ""; m.en = ""; m.idiom = ""; m.note = ""; m.waiting = false; m.blocked = false; m.idiomProgress = 1
            let chars = Array(line.zh)
            for i in 1...chars.count {                       // 一个字一个字上屏
                m.zh = String(chars[0..<i])
                m.intensity = min(1, Double(i) / 30)
                if i % 2 == 0 { m.sheenAt = clock; m.sheenStrength = 0.28 }   // 每两个字一道淡反光
                hold(0.15) { _ in opacity = min(1, opacity + 0.25) }        // 第一个字时淡入
            }
            m.en = line.en
            hold(0.35)
            m.sheenAt = clock; m.sheenStrength = 0.55; m.flashAt = clock     // 一句话打完：亮一下
            if let idiom = line.idiom {
                m.waiting = true
                hold(0.8)                                                    // 等 DeepSeek
                m.waiting = false; m.idiom = idiom; m.note = line.note ?? ""
                hold(0.45) { p in m.idiomProgress = 1 - pow(1 - p, 3) }      // 地道版从下面滑进来
                hold(3.0)
            } else {
                m.blocked = true                                             // 🔒 含敏感内容，未发送
                hold(3.0)
            }
            hold(0.5) { p in opacity = 1 - p }                               // 淡出
            hold(0.5)
        }
        print("已画 \(count) 帧到 \(dir)")
    }
}

/// 示意壁纸：柔和的渐变和色块，透过半透明的浮窗能看出"玻璃感"
struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.87, green: 0.91, blue: 0.95),
                                    Color(red: 0.93, green: 0.94, blue: 0.90),
                                    Color(red: 0.91, green: 0.88, blue: 0.94)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.64)).frame(width: 260).blur(radius: 45).offset(x: -270, y: -80)
            Circle().fill(Color(red: 0.64, green: 0.78, blue: 0.94)).frame(width: 300).blur(radius: 55).offset(x: 290, y: 85)
            Circle().fill(Color(red: 0.84, green: 0.76, blue: 0.95)).frame(width: 200).blur(radius: 45).offset(x: 40, y: -100)
        }
    }
}

/// 候选框示意图（README 用）：按雾凇的真实候选顺序 + 本项目词典的真实释义，用「清透」皮肤的样式画出来。
/// 真正的候选框是鼠须管画的，没法离屏渲染，所以这是示意图。
///   Zh2En --render-candidates out.png
extension DemoRender {
    static func candidates(_ path: String) {
        let r = ImageRenderer(content: CandidateMock().frame(width: 900, height: 190))
        r.scale = 2
        if let tiff = r.nsImage?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("已画到 \(path)")
        }
    }
}

private struct CandidateMock: View {
    // jiaban 在雾凇词库里的前 5 个候选，和 cedict.tsv 里的释义
    private let items: [(String, String?)] = [("加班", "work overtime"), ("甲板", "deck"),
                                              ("夹板", "wooden boards used to…"), ("假扮", "impersonate"), ("甲班", nil)]
    private let teal = Color(red: 0.06, green: 0.56, blue: 0.50)
    private let gray = Color(red: 0.54, green: 0.54, blue: 0.59)

    var body: some View {
        ZStack {
            Wallpaper()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {   // 输入框：正在打的拼音带下划线
                    Text("周末又要")
                    Text("jiaban").underline()
                    Rectangle().fill(Color(white: 0.2)).frame(width: 1.5, height: 20).padding(.leading, 1)
                }
                .font(.system(size: 17))
                .foregroundStyle(Color(white: 0.15))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(width: 420, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.85)))
                HStack(spacing: 6) {   // 候选框
                    ForEach(items.indices, id: \.self) { i in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(i + 1).").font(.system(size: 12)).foregroundStyle(gray)
                            Text(items[i].0).font(.system(size: 17)).foregroundStyle(Color(white: 0.16))
                            if let en = items[i].1 { Text(en).font(.system(size: 14)).foregroundStyle(teal) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background { if i == 0 { RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.85)) } }
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .padding(.leading, 90)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 40)
        }
    }
}
