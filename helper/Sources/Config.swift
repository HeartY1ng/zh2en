import Foundation

/// 本程序会碰到的所有路径都集中在这里（卸载脚本按同样的清单清理）。
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    /// Rime 里的 sentence_tap.lua 写的状态文件：放在系统临时目录（不进备份、重启清空），浮窗消失就删
    static let liveDir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "zh2en")
    static let live = liveDir.appending(path: "live.json")
    /// 可选的模型配置（不存在就用默认值；本程序从不创建它）
    static let llmConfig = home.appending(path: ".config/zh2en/config.json")
}

/// 地道版用的模型。走 OpenAI 兼容接口，换 Ollama 等只要改 ~/.config/zh2en/config.json。
struct LLMConfig: Codable {
    var baseURL = "https://api.deepseek.com"
    var model = "deepseek-flash"
    /// 钥匙串里的账户名（服务名固定是 zh2en）；为空表示不需要 key（比如本地 Ollama）
    var keychainAccount = "deepseek"

    static func load() -> LLMConfig {
        var c = LLMConfig()
        if let data = try? Data(contentsOf: Paths.llmConfig),
           let loaded = try? JSONDecoder().decode(LLMConfig.self, from: data) { c = loaded }
        // 环境变量可以临时换一个钥匙串账户（测试"没配 key"时用）
        if let a = ProcessInfo.processInfo.environment["ZH2EN_KEYCHAIN_ACCOUNT"] { c.keychainAccount = a }
        return c
    }
}

/// 菜单栏里的开关，存在 ~/Library/Preferences/<bundle id>.plist
enum Settings {
    private static let d = UserDefaults.standard
    static func registerDefaults() {
        d.register(defaults: ["paused": false, "localOnly": false])
    }
    static var paused: Bool { get { d.bool(forKey: "paused") } set { d.set(newValue, forKey: "paused") } }
    /// 只用苹果本地翻译，不把句子发给云端模型
    static var localOnly: Bool { get { d.bool(forKey: "localOnly") } set { d.set(newValue, forKey: "localOnly") } }
    /// 浮窗被拖到的位置（浮窗底边中点，屏幕坐标）；nil = 默认的屏幕下方正中
    static var bubbleAnchor: NSPoint? {
        get {
            guard d.object(forKey: "bubbleAnchorX") != nil else { return nil }
            return NSPoint(x: d.double(forKey: "bubbleAnchorX"), y: d.double(forKey: "bubbleAnchorY"))
        }
        set {
            if let p = newValue { d.set(p.x, forKey: "bubbleAnchorX"); d.set(p.y, forKey: "bubbleAnchorY") }
            else { d.removeObject(forKey: "bubbleAnchorX"); d.removeObject(forKey: "bubbleAnchorY") }
        }
    }
}
