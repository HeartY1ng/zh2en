import AppKit
import SwiftUI
import os

/// 只记事件、不记内容的日志（/usr/bin/log show --predicate 'subsystem == "<bundle id>"'）
let flowLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "zh2en", category: "flow")

/// 隐私过滤：哪些内容根本不处理，哪些内容只在本地处理（硬盘上不留任何句子）
enum Privacy {
    /// 不含汉字的内容一律不处理（英文模式下打的密码、命令、验证码）
    static func hasChinese(_ s: String) -> Bool {
        s.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    /// 含敏感内容：照常显示苹果本地直译，但不发云端、不记笔记
    static func isSensitive(_ s: String) -> Bool {
        let patterns = [
            "(\\d[\\s-]?){5,}",                                  // 5 位以上数字：手机号、验证码、卡号、证件号
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",   // 邮箱
            "https?://|www\\.",                                  // 网址
            "密码|口令|验证码|身份证|银行卡|卡号|账号|住址|地址",
        ]
        return patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }
}

/// 把各部分串起来：live.json 变了 → 直译 → 一句话打完 → 地道版 → 淡出并删掉状态文件
@MainActor
final class Controller {
    let bubble = BubblePanel()
    private let feed = LiveFeed()
    private let apple = AppleTranslator()
    private let llm = LLMClient()

    private var sid = -1                 // 当前这句话的编号
    private var translated = ""          // 已经直译过的中文（同样的不再翻）
    private var finishedSid = -1         // 已经收尾过的句子
    private var committedCount = 0       // 已上屏几个字（变多了就扫一道反光）
    private var debounce: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    /// 菜单里显示的最近状态
    private(set) var status = "等待输入…"

    private var m: BubbleModel { bubble.model }

    /// 配了 DeepSeek key 没有。没配就只用系统翻译，浮窗上也不显示开关
    var cloudAvailable: Bool { llm.isConfigured }

    func start() {
        m.cloudAvailable = cloudAvailable
        m.cloudOn = !Settings.localOnly
        m.onToggleMode = { [weak self] in
            Settings.localOnly.toggle()
            self?.modeChanged()
        }
        feed.onChange = { [weak self] s in self?.handle(s) }
        feed.start()
    }

    func pauseChanged() {
        if Settings.paused { debounce?.cancel(); hideNow() }
    }

    /// 浮窗上的开关或菜单切换了 本地 / DeepSeek
    func modeChanged() {
        withAnimation(.snappy(duration: 0.25)) { m.cloudOn = !Settings.localOnly }
        // 刚打完的这句还没有地道版：切到 DeepSeek 就立刻补上
        if m.cloudOn, m.cloudAvailable, finishedSid == sid, m.idiom.isEmpty, !m.waiting, !m.blocked, bubble.isShown {
            let text = m.zh, thisSid = sid
            Task { await fetchIdiom(thisSid, text) }
        }
    }

    private func handle(_ s: LiveState) {
        guard !Settings.paused else { return }
        if s.sid != sid {                 // 新的一句：清空上一句的结果
            sid = s.sid
            translated = ""
            m.en = ""; m.idiom = ""; m.note = ""; m.waiting = false
            committedCount = 0
            m.cloudAvailable = cloudAvailable   // 每句开头看一眼：中途补配了 key 也能马上用上
        }
        let text = s.text
        guard Privacy.hasChinese(text) else {   // 删光了 / 作废了 / 根本不是中文
            if !text.isEmpty { flowLog.notice("skip: no Chinese") }
            debounce?.cancel()
            scheduleHide(after: 0.6)
            return
        }
        m.zh = text
        m.blocked = Privacy.isSensitive(text)
        m.intensity = min(1, Double(text.count) / 30)   // 大约 30 个字光带最多
        bubble.show()
        if s.committed.count > committedCount && !s.done { bubble.typedSheen() }   // 上屏了新字：反光掠过
        committedCount = s.committed.count
        if !s.done { scheduleHide(after: 20) }          // 打了一半去干别的了：20 秒后收起

        debounce?.cancel()
        debounce = Task { [weak self] in
            if !s.done { try? await Task.sleep(for: .milliseconds(250)) }   // 停顿一下再翻，不是每个键都翻
            guard !Task.isCancelled, let self else { return }
            await self.translate(s, text)
        }
    }

    private func translate(_ s: LiveState, _ text: String) async {
        if text != translated, let en = await apple.translate(text) {
            guard s.sid == sid, !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.35)) { m.en = en }   // 直译柔和地变过去
            translated = text
            bubble.relayout()
        } else if let err = apple.lastError {
            setStatus("苹果翻译出错：\(err)")
        }
        if s.done && finishedSid != s.sid { await finish(s.sid, text) }
    }

    /// 一句话打完：亮一下；DeepSeek 模式且不敏感才去要地道版
    private func finish(_ thisSid: Int, _ text: String) async {
        finishedSid = thisSid
        bubble.pulse()
        if m.cloudAvailable && m.cloudOn && !m.blocked {
            await fetchIdiom(thisSid, text)
        } else {
            let why = !m.cloudAvailable ? "no key, system translation only" : (m.blocked ? "blocked, not sent" : "local mode, not sent")
            flowLog.notice("done: \(why, privacy: .public)")
            scheduleHide(after: 6)
        }
    }

    private func fetchIdiom(_ thisSid: Int, _ text: String) async {
        hideTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) { m.waiting = true }
        bubble.relayout()
        var idiom: Idiom?
        let t0 = Date()
        do {
            idiom = try await llm.idiom(for: text)
            setStatus(String(format: "地道版：%@，%.1f 秒", llm.modelName, Date().timeIntervalSince(t0)))
            flowLog.notice("idiom ok \(Date().timeIntervalSince(t0), format: .fixed(precision: 1))s")
        } catch {
            setStatus("地道版出错：\(error.localizedDescription)")   // 静默退回只有直译
            flowLog.error("idiom failed: \(String(describing: type(of: error)), privacy: .public)")
        }
        guard thisSid == sid else { return }   // 等的时候已经开始打下一句了
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {   // 地道版从下面滑进来
            m.waiting = false
            if let idiom { m.idiom = idiom.en; m.note = idiom.note ?? "" }
        }
        bubble.relayout()
        scheduleHide(after: idiom == nil ? 6 : 9)
    }

    /// 到点收起浮窗；鼠标停在浮窗上时先不收
    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            while !Task.isCancelled, self?.m.hovering == true { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            self?.hideNow()
        }
    }

    /// 收起浮窗，同时删掉状态文件
    private func hideNow() {
        if bubble.isShown { flowLog.notice("hide + clear state file") }
        bubble.hide()
        feed.clear()
    }

    private func setStatus(_ s: String) {
        status = s
    }
}
