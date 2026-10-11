import Foundation
import Translation

/// 苹果离线翻译：边打边出的直译（免费、离线、约 0.03 秒一句）
@MainActor
final class AppleTranslator {
    private var session: TranslationSession?
    private(set) var lastError: String?

    func translate(_ text: String) async -> String? {
        if session == nil {
            session = TranslationSession(installedSource: Locale.Language(identifier: "zh-Hans"),
                                         target: Locale.Language(identifier: "en"))
        }
        do {
            let r = try await session!.translate(text)
            lastError = nil
            return r.targetText
        } catch {
            lastError = "\(error)"
            session = nil   // 下次重建
            return nil
        }
    }
}

/// 地道版的结果
struct Idiom: Decodable {
    let en: String
    let note: String?
}

enum LLMError: LocalizedError {
    case noKey, http(Int, String), badReply(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "钥匙串里没有 key（服务名 zh2en）"
        case .http(let code, let body): return "HTTP \(code) \(body.prefix(120))"
        case .badReply(let s): return "回复看不懂：\(s.prefix(120))"
        }
    }
}

/// 地道版：一句话打完后调一次大模型（默认 DeepSeek flash，OpenAI 兼容接口）
final class LLMClient {
    static let system = """
    You help a Chinese speaker learn natural, idiomatic English. They just typed a Chinese sentence, \
    usually in casual chat. Say it the way a native English speaker would actually say it in the same \
    situation and tone: idiomatic, not a literal translation, about as short as the original. \
    If the Chinese is a culturally specific phrase (for example 吃了吗 used as a greeting), give what a \
    native speaker would naturally say in that situation, not a word-for-word version. \
    Then pick the single most useful expression from your English and explain it briefly in Chinese. \
    The expression before "=" must be copied exactly from your English sentence (same words, same tense), so it can be highlighted there. \
    Never claim something is common in English unless it really is. \
    Respond in json only: {"en": "...", "note": "expression = 中文解释"}
    """

    private let config = LLMConfig.load()
    private var key: String?
    /// 临时会话：不在磁盘上留网络缓存、cookie
    private let http: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    var modelName: String { config.model }

    private var configuredAt = Date.distantPast
    private var configuredCache = false
    /// 配了 key 没有（只查"有没有"，不读内容）。结果缓存 30 秒，中途补配 key 不用重启
    var isConfigured: Bool {
        if config.keychainAccount.isEmpty { return true }   // 本地模型（比如 Ollama）不需要 key
        if key != nil { return true }
        if Date().timeIntervalSince(configuredAt) < 30 { return configuredCache }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "zh2en", "-a", config.keychainAccount]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        configuredCache = (try? p.run()) != nil && { p.waitUntilExit(); return p.terminationStatus == 0 }()
        configuredAt = Date()
        return configuredCache
    }

    /// 用系统自带的 security 命令读 key，不弹钥匙串授权框，key 也不落地
    private func apiKey() throws -> String? {
        if config.keychainAccount.isEmpty { return nil }
        if let key { return key }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "zh2en", "-a", config.keychainAccount, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let k = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0, !k.isEmpty else { throw LLMError.noKey }
        key = k
        return k
    }

    func idiom(for zh: String) async throws -> Idiom {
        let key = try apiKey()
        var req = URLRequest(url: URL(string: config.baseURL + "/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": Self.system], ["role": "user", "content": zh]],
            "response_format": ["type": "json_object"],
            "thinking": ["type": "disabled"],   // 不关的话，模型先"思考"几百个 token，又慢又贵
            "temperature": 0.7,
            "max_tokens": 300,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await http.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw LLMError.http(code, String(decoding: data, as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String,
              let idiom = try? JSONDecoder().decode(Idiom.self, from: Data(content.utf8)) else {
            throw LLMError.badReply(String(decoding: data, as: UTF8.self))
        }
        return idiom
    }
}
