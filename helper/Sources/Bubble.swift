import AppKit
import SwiftUI

/// 浮窗上显示的内容
@MainActor
final class BubbleModel: ObservableObject {
    @Published var zh = ""        // 正在打的中文
    @Published var en = ""        // 苹果直译
    @Published var idiom = ""     // 地道版
    @Published var note = ""      // 要点（"说法 = 中文解释"）
    @Published var waiting = false // 正在等地道版
    @Published var intensity = 0.0 // 0…1：这句话越长越大 → 光带越多、飘得越快
    @Published var animating = false
    // 反光：每上屏一个字扫一道淡的，一句话打完扫一道亮的
    @Published var sheenAt = Date.distantPast
    @Published var sheenStrength = 0.0
    // 一句话打完：光带亮一下
    @Published var flashAt = Date.distantPast
    @Published var cloudAvailable = true // 配了 DeepSeek key 没有；没配就只用系统翻译、不显示开关
    @Published var cloudOn = true   // true = 打完一句发给 DeepSeek；false = 只用苹果本地翻译
    @Published var blocked = false  // 这句含敏感内容：不发云端、不记笔记
    @Published var hovering = false // 鼠标停在浮窗上：先不收起
    @Published var idiomProgress = 1.0 // 离线渲染演示时手动推进"地道版滑进来"（正常使用时一直是 1，由系统动画负责）
    var onToggleMode: (() -> Void)?
    @Published var dragging = false
    var onDragChanged: (() -> Void)?   // 拖动浮窗
    var onDragEnded: (() -> Void)?
}

/// 「A 极光玻璃」第二版：几条光带从玻璃里飘过（句子越长越多），打字时有反光掠过，关键说法带流光
struct BubbleView: View {
    @ObservedObject var m: BubbleModel
    @Environment(\.colorScheme) private var scheme
    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !m.animating)) { tl in
            let now = Offscreen.frameDate ?? tl.date   // 离线渲染演示时用虚拟时钟
            let time = now.timeIntervalSinceReferenceDate
            let boost = max(0, 1 - now.timeIntervalSince(m.flashAt) / 0.9)          // 打完一句后 0.9 秒内由 1 降到 0
            let sheen = now.timeIntervalSince(m.sheenAt) / 0.85                     // 反光扫过的进度 0…1
            content(time: time)
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .frame(minWidth: 240, maxWidth: 600, alignment: .leading)
                .background(
                    ZStack {
                        AuroraRibbons(t: m.intensity, time: time, boost: boost, dark: scheme == .dark)
                        if sheen >= 0 && sheen <= 1 { Sheen(progress: sheen, strength: m.sheenStrength) }
                    }
                    .clipShape(shape)
                )
                .modifier(Glass(shape: shape))
                .overlay(shape.strokeBorder(.white.opacity(scheme == .dark ? 0.22 : 0.65), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)
                .onHover { m.hovering = $0 }
                .contentShape(shape)
                .pointerStyle(m.dragging ? .grabActive : .grabIdle)
                .gesture(DragGesture(minimumDistance: 2)   // 按住浮窗任意位置都能拖（右上角开关照常点击）
                    .onChanged { _ in m.onDragChanged?() }
                    .onEnded { _ in m.onDragEnded?() })
                .padding(24)   // 给阴影留地方
        }
    }

    private func content(time: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(m.zh)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
                Spacer(minLength: 0)
                if m.cloudAvailable { ModeToggle(cloudOn: m.cloudOn) { m.onToggleMode?() } }
            }
            if !m.en.isEmpty {
                Text(m.en)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary.opacity(0.85))
                    .contentTransition(.interpolate)   // 直译更新时柔和地变过去
            }
            if m.blocked && m.cloudAvailable && m.cloudOn {   // 只在"本来会发出去"的时候提示
                Label("含敏感内容，未发送给 DeepSeek", systemImage: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .transition(.opacity)
            } else if !m.idiom.isEmpty {
                idiomLine(time: time)
                    .padding(.top, 3)
                    .opacity(m.idiomProgress)
                    .offset(y: 8 * (1 - m.idiomProgress))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                if let n = parsedNote {
                    Text("\(Text(n.expr).foregroundStyle(Self.shimmer(time)).fontWeight(.medium))\(Text(" = " + n.meaning))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .opacity(m.idiomProgress)
                        .transition(.opacity)
                }
            } else if m.waiting {
                Text("✦ …")
                    .font(.system(size: 15))
                    .foregroundStyle(.tertiary)
                    .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 地道版：句子里的关键说法带一层缓缓流动的渐变（像镭射贴纸）
    private func idiomLine(time: Double) -> some View {
        let g = Self.shimmer(time)
        let star = Text("✦ ").foregroundStyle(g)
        let body: Text
        if let n = parsedNote, let r = m.idiom.range(of: n.expr, options: .caseInsensitive) {
            let key = Text(String(m.idiom[r])).foregroundStyle(g)
            body = Text("\(Text(String(m.idiom[..<r.lowerBound])))\(key)\(Text(String(m.idiom[r.upperBound...])))")
        } else {
            body = Text(m.idiom)
        }
        return Text("\(star)\(body)")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
    }

    /// "so done = 受够了" → ("so done", "受够了")
    private var parsedNote: (expr: String, meaning: String)? {
        guard let r = m.note.range(of: "=") else { return m.note.isEmpty ? nil : ("", m.note) }
        let expr = m.note[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
        let meaning = m.note[r.upperBound...].trimmingCharacters(in: .whitespaces)
        return expr.isEmpty ? nil : (expr, meaning)
    }

    /// 流光渐变：粉 → 紫 → 青 循环两遍，整体向右平移，首尾无缝
    static func shimmer(_ time: Double) -> LinearGradient {
        let p = (time * 0.3).truncatingRemainder(dividingBy: 1)
        let c = [Color(red: 1, green: 0.31, blue: 0.6), Color(red: 0.48, green: 0.42, blue: 1), Color(red: 0.07, green: 0.66, blue: 0.81)]
        return LinearGradient(colors: c + c + [c[0]],
                              startPoint: UnitPoint(x: -1 + p, y: 0.5), endPoint: UnitPoint(x: 1 + p, y: 0.5))
    }
}

/// 右上角的小开关：本地 ↔ DeepSeek。点它不会抢走输入框的光标
private struct ModeToggle: View {
    let cloudOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                segment("本地", icon: "desktopcomputer", on: !cloudOn)
                segment("DeepSeek", icon: "sparkles", on: cloudOn)
            }
            .padding(2)
            .background(.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .fixedSize()
    }

    private func segment(_ title: String, icon: String, on: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 11, weight: on ? .semibold : .regular))
        .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            if on { Capsule().fill(.white.opacity(0.55)).shadow(color: .black.opacity(0.08), radius: 2, y: 1) }
        }
    }
}

/// 极光光带：4 条柔和的彩色光带从左往右飘过，带一点上下起伏和倾斜。
/// 句子越长，光带一条一条地出现，飘得也更快——是"更多、更活"，不是"更浓"。
private struct AuroraRibbons: View {
    let t: Double
    let time: Double
    let boost: Double
    let dark: Bool

    // 每条光带：两端色相、速度倍数、相位
    private static let ribbons: [(a: Double, b: Double, speed: Double, phase: Double)] = [
        (0.93, 0.08, 1.00, 0.0),   // 粉 → 杏
        (0.47, 0.56, 0.80, 1.7),   // 薄荷 → 天蓝
        (0.74, 0.90, 1.20, 3.1),   // 紫 → 粉紫
        (0.12, 0.42, 0.65, 4.4),   // 琥珀 → 薄荷
    ]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let span = w * 1.9                                  // 从左边看不见的地方飘到右边看不见的地方
            ZStack {
                ForEach(0..<Self.ribbons.count, id: \.self) { i in
                    let r = Self.ribbons[i]
                    // 第 1 条一开始就在（淡淡的），后面几条随句子变长依次出现
                    let appear = i == 0 ? 0.6 + 0.4 * min(1, t / 0.15)
                                        : min(1, max(0, (t - Double(i) * 0.2) / 0.18))
                    let speed = (26 + 46 * t) * r.speed         // 点/秒
                    let x = (time * speed + Double(i) * span / 4 + r.phase * 40)
                        .truncatingRemainder(dividingBy: span) - w * 0.45
                    let y = h * 0.5 + sin(time * 0.7 * r.speed + r.phase) * h * 0.28
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hue: r.a, saturation: 0.5, brightness: 1),
                                                      Color(hue: r.b, saturation: 0.5, brightness: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * 0.55, height: h * 0.5)
                        .rotationEffect(.degrees(sin(time * 0.35 + r.phase) * 14))
                        .position(x: x, y: y)
                        .opacity(appear)
                }
            }
            .blur(radius: 20)
            .opacity((dark ? 0.32 + 0.18 * t : 0.28 + 0.22 * t) * (1 + 0.7 * boost))
            .blendMode(dark ? .plusLighter : .normal)
        }
        .drawingGroup()
    }
}

/// 反光：一道斜着的白光从左到右扫过玻璃
private struct Sheen: View {
    let progress: Double
    let strength: Double

    var body: some View {
        GeometryReader { g in
            LinearGradient(colors: [.white.opacity(0), .white.opacity(strength), .white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 70, height: g.size.height * 2.2)
                .rotationEffect(.degrees(20))
                .position(x: -50 + (g.size.width + 100) * easeInOut(progress), y: g.size.height / 2)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
}

/// 液态玻璃（macOS 26+），老系统退回毛玻璃
private struct Glass<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if Offscreen.plainBackground {                       // 截图模式：离屏画不出玻璃，换成普通底色
            content.background(Color.white.opacity(0.45), in: shape)   // 半透明白底，叠在壁纸上模拟毛玻璃
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// 永远不会变成"当前窗口"的面板：点上面的开关时，光标还留在你正在打字的输入框里
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 第一次点击就生效（不用先点一下"激活"窗口）
private final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 承载浮窗的面板：不抢焦点、所有桌面空间都显示、不出现在截图和屏幕共享里
@MainActor
final class BubblePanel {
    let model = BubbleModel()
    private let panel: NSPanel
    private let measurer: NSHostingController<BubbleView>   // 只用来量尺寸，不显示
    private var shown = false
    var isShown: Bool { shown }
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    /// 点了浮窗外面的任何地方（别的程序的窗口、桌面……）
    var onClickOutside: (() -> Void)?
    private var clickMonitor: Any?
    /// 现在不该自动收起：鼠标真的在浮窗上，或者正在拖
    var holdsOpen: Bool { dragStart != nil || (shown && panel.frame.contains(NSEvent.mouseLocation)) }

    /// recordable: 演示模式下允许被录屏（平时不出现在截图和屏幕共享里）
    init(recordable: Bool = false) {
        measurer = NSHostingController(rootView: BubbleView(m: model))
        let view = FirstClickHostingView(rootView: BubbleView(m: model))
        view.sizingOptions = []
        panel = NonKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = false        // 要能点开关；透明的地方点击会穿过去
        panel.sharingType = recordable ? .readOnly : .none   // 平时：截图、录屏、屏幕共享里不出现（个别软件可能仍能录到）
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.contentView = view
        panel.alphaValue = 0
        model.onDragChanged = { [weak self] in self?.dragChanged() }
        model.onDragEnded = { [weak self] in self?.dragEnded() }
        // 全局鼠标监听只收得到"点在别的程序上"的事件；点浮窗本身不会触发。监听鼠标不需要辅助功能权限
        if !recordable {
            clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.shown, self.dragStart == nil else { return }
                    self.onClickOutside?()
                }
            }
        }
    }

    /// 拖动：用屏幕坐标算位移（窗口自己在动，用窗口内坐标会抖）
    private func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            dragStart = (mouse, panel.frame.origin)
            model.hovering = true   // 拖的时候不许自动收起
            model.dragging = true
        }
        guard let s = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x, y: s.origin.y + mouse.y - s.mouse.y))
    }

    private func dragEnded() {
        guard dragStart != nil else { return }
        endDrag()
        relayout()   // 拖出了屏幕的话收回来
    }

    private func endDrag() {
        dragStart = nil
        model.dragging = false
        model.hovering = false
        Settings.bubbleAnchor = NSPoint(x: panel.frame.midX, y: panel.frame.minY)   // 记住：底边中点
    }

    /// 菜单里的"浮窗回到默认位置"
    func resetPosition() {
        Settings.bubbleAnchor = nil
        relayout()
    }

    /// 内容变了以后重新算大小。位置：拖到过哪就在哪（底边中点不动，往上长），否则在屏幕下方正中
    func relayout() {
        if dragStart != nil, NSEvent.pressedMouseButtons == 0 { endDrag() }   // 拖动被系统打断、没收到"结束"：鼠标已经松开就当结束
        guard dragStart == nil else { return }   // 正在拖，别跟用户抢
        let size = measurer.sizeThatFits(in: NSSize(width: 660, height: 800))
        var frame: NSRect
        if let a = Settings.bubbleAnchor, let screen = NSScreen.screens.first(where: { $0.frame.contains(a) }) {
            let vf = screen.visibleFrame
            frame = NSRect(x: (a.x - size.width / 2).rounded(), y: a.y, width: size.width, height: size.height)
            frame.origin.x = min(max(frame.minX, vf.minX), vf.maxX - frame.width)    // 收进屏幕里
            frame.origin.y = min(max(frame.minY, vf.minY), vf.maxY - frame.height)
        } else {   // 默认位置；拖到过的位置已经不在任何屏幕上（比如拔了外接显示器）也回到这里
            let vf = (NSScreen.main ?? NSScreen.screens.first!).visibleFrame
            frame = NSRect(x: (vf.midX - size.width / 2).rounded(), y: vf.minY + 40, width: size.width, height: size.height)
        }
        guard frame != panel.frame else { return }
        if shown {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func show() {
        relayout()
        guard !shown else { return }
        shown = true
        model.animating = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
    }

    func hide() {
        guard shown else { return }
        shown = false
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; panel.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated {
                if !self.shown { self.panel.orderOut(nil); self.model.animating = false }
            }
        }
    }

    /// 上屏了新的字：一道淡淡的反光
    func typedSheen() {
        guard Date().timeIntervalSince(model.sheenAt) > 0.5 else { return }   // 打得很快时别扫个不停
        model.sheenStrength = 0.28
        model.sheenAt = Date()
    }

    /// 一句话打完：一道亮的反光 + 光带亮一下
    func pulse() {
        model.sheenStrength = 0.55
        model.sheenAt = Date()
        model.flashAt = Date()
    }
}
