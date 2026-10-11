import Foundation

/// sentence_tap.lua 写进 live.json 的内容
struct LiveState: Decodable, Equatable {
    let seq: Int
    let sid: Int          // 句子编号：变了就是新的一句
    let committed: String // 已上屏的部分
    let composing: String // 正在打、还没上屏的部分
    let done: Bool        // 这句话打完了（。！？ 或回车）

    var text: String { (committed + composing).trimmingCharacters(in: .whitespaces) }
}

/// 盯着 live.json：文件变了由系统通知（kqueue），闲着的时候零唤醒、零耗电
@MainActor
final class LiveFeed {
    var onChange: ((LiveState) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var last: Data?

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.liveDir, withIntermediateDirectories: true)
        try? fm.removeItem(at: Paths.live)   // 上次留下的旧内容，不显示也不留
        // 监听的是目录：Lua 用"写临时文件再改名"的方式更新，文件本身每次都是新的
        let fd = open(Paths.liveDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.read() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func read() {
        guard let data = try? Data(contentsOf: Paths.live), data != last else { return }
        last = data
        if let s = try? JSONDecoder().decode(LiveState.self, from: data) { onChange?(s) }
    }

    /// 浮窗消失时调用：删掉状态文件，硬盘上不留正在打的句子
    func clear() {
        try? FileManager.default.removeItem(at: Paths.live)
        last = nil
    }
}
