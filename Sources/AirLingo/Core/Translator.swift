import Foundation

enum TranslationError: LocalizedError {
    case missingAPIKey
    case badURL
    case http(Int, String)
    case emptyResult
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "还没填 API Key"
        case .badURL: return "接口地址无效"
        case .http(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = trimmed.count > 180 ? String(trimmed.prefix(180)) + "…" : trimmed
            return "接口返回 \(code)：\(snippet)"
        case .emptyResult: return "引擎返回了空结果"
        case .decode(let detail): return "解析失败：\(detail)"
        }
    }
}

struct TranslationOutput {
    var text: String
    var engineName: String
    var detectedSource: String?
}

enum Translator {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 40
        return URLSession(configuration: cfg)
    }()

    static func translate(_ text: String,
                          to target: String,
                          profile: EngineProfile,
                          detectedSource: String? = nil) async throws -> TranslationOutput {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyResult }

        switch profile.kind {
        case .apple:
            guard #available(macOS 15.0, *) else { throw AppleTranslateError.unsupportedOS }
            let result = try await AppleTranslateService.shared.translate(trimmed, to: target)
            return TranslationOutput(text: result.text,
                                     engineName: profile.name,
                                     detectedSource: result.source ?? detectedSource)
        case .google:
            let (result, detected) = try await google(trimmed, to: target, baseURL: profile.baseURL)
            return TranslationOutput(text: result, engineName: profile.name, detectedSource: detected)
        case .openai:
            let result = try await openAI(trimmed, to: target, profile: profile)
            return TranslationOutput(text: result, engineName: profile.name, detectedSource: detectedSource)
        case .deepl:
            let result = try await deepl(trimmed, to: target, profile: profile)
            return TranslationOutput(text: result, engineName: profile.name, detectedSource: detectedSource)
        case .ollama:
            let result = try await ollama(trimmed, to: target, profile: profile)
            return TranslationOutput(text: result, engineName: profile.name, detectedSource: detectedSource)
        }
    }

    // MARK: Google 免费接口

    private static func google(_ text: String, to target: String, baseURL: String) async throws -> (String, String?) {
        var comps = URLComponents(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/translate_a/single")
        comps?.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = comps?.url else { throw TranslationError.badURL }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.http(code, String(data: data, encoding: .utf8) ?? "")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw TranslationError.decode("非预期响应")
        }
        var pieces: [String] = []
        if let chunks = root.first as? [Any] {
            for chunk in chunks {
                if let arr = chunk as? [Any], let piece = arr.first as? String {
                    pieces.append(piece)
                }
            }
        }
        let detected = root.count > 2 ? root[2] as? String : nil
        let result = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResult }
        return (result, detected)
    }

    // MARK: OpenAI 兼容

    private static func openAI(_ text: String, to target: String, profile: EngineProfile) async throws -> String {
        guard !profile.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw TranslationError.missingAPIKey }
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else { throw TranslationError.badURL }

        let system = """
        You are a precise translation engine. Translate the user's text into \(AppLanguage.name(for: target)) \
        (\(target)). Preserve meaning, tone, formatting, code, and proper nouns. \
        Output only the translation — no explanations, no quotes, no preamble. \
        If the text is already in the target language, return it unchanged.
        """
        let body: [String: Any] = [
            "model": profile.model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw TranslationError.decode("缺少 choices.message.content") }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResult }
        return result
    }

    // MARK: DeepL

    private static func deepl(_ text: String, to target: String, profile: EngineProfile) async throws -> String {
        guard !profile.apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { throw TranslationError.missingAPIKey }
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/translate") else { throw TranslationError.badURL }

        let targetCode = AppLanguage.base(target).uppercased()
        var comps = URLComponents()
        comps.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: targetCode)
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.addValue("DeepL-Auth-Key \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["translations"] as? [[String: Any]],
              let first = list.first?["text"] as? String
        else { throw TranslationError.decode("缺少 translations[0].text") }
        return first
    }

    // MARK: Ollama

    private static func ollama(_ text: String, to target: String, profile: EngineProfile) async throws -> String {
        let base = profile.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/chat") else { throw TranslationError.badURL }
        let model = profile.model.isEmpty ? "qwen2.5:7b" : profile.model
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "options": ["temperature": 0.2],
            "messages": [
                ["role": "system", "content": "You are a precise translation engine. Translate into \(AppLanguage.name(for: target)). Output only the translation."],
                ["role": "user", "content": text]
            ]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw TranslationError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw TranslationError.decode("缺少 message.content") }
        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResult }
        return result
    }
}
