import Foundation
import Security

enum GeminiError: LocalizedError {
    case noKeys
    case exhausted(String)
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noKeys:
            return "Добавьте ключ Gemini: Похудение → ⚙︎ → Ключи Gemini."
        case .exhausted(let last):
            return "Все ключи и модели сейчас недоступны (лимиты или ошибки). Последняя ошибка: \(last)"
        case .badResponse(let text):
            return "Не удалось разобрать ответ ИИ: \(text)"
        case .network(let text):
            return "Нет соединения: \(text)"
        }
    }
}

/// Ключи Gemini: введённые в приложении (Keychain) и, для личной локальной сборки, встроенные из .secrets/gemini_keys.
enum GeminiKeys {
    private static let account = "gemini.keys"

    static var userKeys: [String] {
        guard let raw = Keychain.read(account) else { return [] }
        return raw.split(separator: "\n").map { String($0) }.filter { !$0.isEmpty }
    }

    static func setUserKeys(_ keys: [String]) {
        let cleaned = keys.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        Keychain.write(account, value: cleaned.isEmpty ? nil : cleaned.joined(separator: "\n"))
    }

    static var embedded: [String] { BuildSecrets.geminiKeys }

    /// Сначала свои ключи, потом встроенные; каждый следующий используется, только когда предыдущий упёрся в лимит.
    static var all: [String] {
        var seen = Set<String>()
        return (userKeys + embedded).filter { seen.insert($0).inserted }
    }

    /// Короткий отпечаток для отображения и учёта лимитов — сам ключ нигде не сохраняется открыто.
    static func fingerprint(_ key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }

    static func masked(_ key: String) -> String {
        guard key.count > 8 else { return "••••" }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }
}

enum GeminiSettings {
    private static let modelsKey = "gemini.models"

    /// Порядок важен: при ошибке модели берётся следующая. Устаревшие модели пропускаются автоматически.
    static let defaultModels = [
        "gemini-flash-latest",
        "gemini-2.5-flash",
        "gemini-flash-lite-latest",
        "gemini-2.5-flash-lite",
        "gemini-2.0-flash",
    ]

    static var models: [String] {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: modelsKey) ?? []
            return stored.isEmpty ? defaultModels : stored
        }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            UserDefaults.standard.set(cleaned, forKey: modelsKey)
        }
    }
}

enum Keychain {
    private static let service = "com.pulsar.app"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        // Запасной вариант, если подпись не дала доступ к Keychain.
        return UserDefaults.standard.string(forKey: "fallback." + account)
    }

    static func write(_ account: String, value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fallback." + account)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(value, forKey: "fallback." + account)
        }
    }
}

struct GeminiSource: Codable, Hashable {
    var title: String
    var url: String
}

struct GeminiUsage: Codable {
    var day: String
    var requests: Int
    var tokens: Int
}

/// Клиент Gemini с автоматическим переключением:
/// ошибка модели → следующая модель, лимит (429) → следующий ключ.
/// Блокировки запоминаются, чтобы не тратить запросы на заведомо недоступные пары «ключ + модель».
actor GeminiClient {
    static let shared = GeminiClient()

    struct Request {
        var prompt: String
        var system: String
        var useSearch = false
        var maxOutputTokens = 1200
        var temperature = 0.2
    }

    struct Response {
        var text: String
        var model: String
        var sources: [GeminiSource]
        var tokens: Int
    }

    private enum Failure {
        case rateLimit(TimeInterval)
        case badKey
        case model(TimeInterval)
        case badRequest
        case network
    }

    private static let cooldownKey = "gemini.cooldowns"
    private static let usageKey = "gemini.usage"
    private var cooldowns: [String: Date]

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.cooldownKey) as? [String: Double] ?? [:]
        cooldowns = stored.mapValues { Date(timeIntervalSince1970: $0) }.filter { $0.value > Date() }
    }

    // MARK: Публичное API

    func generate(_ request: Request) async throws -> Response {
        let keys = GeminiKeys.all
        guard !keys.isEmpty else { throw GeminiError.noKeys }
        var lastError = "нет ответа"

        for model in GeminiSettings.models where !isCooling("model|\(model)") {
            keyLoop: for key in keys {
                let id = GeminiKeys.fingerprint(key)
                if isCooling("key|\(id)") || isCooling("quota|\(id)|\(model)") { continue }
                var useThinkingBudget = Self.supportsThinkingBudget(model)

                while true {
                    let (result, message) = await call(model: model, key: key, request: request, thinkingBudget: useThinkingBudget)
                    if let response = result {
                        recordUsage(tokens: response.tokens)
                        return response
                    }
                    lastError = "\(model): \(message)"
                    switch Self.classify(message: message) {
                    case .rateLimit(let wait):
                        setCooldown("quota|\(id)|\(model)", for: wait)
                        continue keyLoop
                    case .badKey:
                        setCooldown("key|\(id)", for: 6 * 3600)
                        continue keyLoop
                    case .badRequest where useThinkingBudget:
                        useThinkingBudget = false
                        continue
                    case .badRequest:
                        setCooldown("model|\(model)", for: 3600)
                        break keyLoop
                    case .model(let wait):
                        setCooldown("model|\(model)", for: wait)
                        break keyLoop
                    case .network:
                        throw GeminiError.network(message)
                    }
                }
            }
        }
        throw GeminiError.exhausted(lastError)
    }

    func resetCooldowns() {
        cooldowns = [:]
        persistCooldowns()
    }

    /// Сколько пар «ключ/модель» сейчас заблокировано.
    func activeCooldowns() -> Int {
        cooldowns.values.filter { $0 > Date() }.count
    }

    nonisolated static func usageToday() -> GeminiUsage {
        let today = dayString()
        if let data = UserDefaults.standard.data(forKey: usageKey),
           let usage = try? JSONDecoder().decode(GeminiUsage.self, from: data), usage.day == today {
            return usage
        }
        return GeminiUsage(day: today, requests: 0, tokens: 0)
    }

    // MARK: Запрос

    /// Возвращает ответ либо текст ошибки с HTTP-кодом в начале («429 …»).
    private func call(model: String, key: String, request: Request, thinkingBudget: Bool) async -> (Response?, String) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            return (nil, "404 bad model name")
        }
        var generation: [String: Any] = [
            "temperature": request.temperature,
            "maxOutputTokens": request.maxOutputTokens,
        ]
        if !request.useSearch {
            generation["responseMimeType"] = "application/json"
        }
        if thinkingBudget {
            // Без «размышлений» ответы короче и дешевле — для подсчёта калорий этого достаточно.
            generation["thinkingConfig"] = ["thinkingBudget": 0]
        }
        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": request.prompt]]]],
            "systemInstruction": ["parts": [["text": request.system]]],
            "generationConfig": generation,
        ]
        if request.useSearch {
            body["tools"] = [["google_search": [String: Any]()]]
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: request.useSearch ? 60 : 30)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        // Позволяет ограничить ключ в Google Cloud только этим приложением.
        if let bundleID = Bundle.main.bundleIdentifier {
            urlRequest.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let status: Int
        do {
            let (responseData, response) = try await URLSession.shared.data(for: urlRequest)
            data = responseData
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            return (nil, "network \(error.localizedDescription)")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let error = json["error"] as? [String: Any]
            let message = error?["message"] as? String ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            let statusName = error?["status"] as? String ?? ""
            var retry = ""
            if let details = error?["details"] as? [[String: Any]] {
                for detail in details {
                    if let delay = detail["retryDelay"] as? String { retry = " retryDelay=\(delay)" }
                }
            }
            return (nil, "\(status) \(statusName) \(message)\(retry)")
        }

        let candidate = (json["candidates"] as? [[String: Any]])?.first
        let parts = ((candidate?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            let reason = candidate?["finishReason"] as? String ?? "пустой ответ"
            return (nil, "500 EMPTY \(reason)")
        }

        var sources: [GeminiSource] = []
        if let grounding = candidate?["groundingMetadata"] as? [String: Any],
           let chunks = grounding["groundingChunks"] as? [[String: Any]] {
            for chunk in chunks {
                if let web = chunk["web"] as? [String: Any], let uri = web["uri"] as? String {
                    sources.append(GeminiSource(title: web["title"] as? String ?? uri, url: uri))
                }
            }
        }
        let tokens = (json["usageMetadata"] as? [String: Any])?["totalTokenCount"] as? Int ?? 0
        return (Response(text: text, model: model, sources: sources, tokens: tokens), "")
    }

    // MARK: Классификация ошибок

    private static func classify(message: String) -> Failure {
        let lower = message.lowercased()
        if lower.hasPrefix("network") { return .network }
        let code = Int(message.prefix(3)) ?? 0
        switch code {
        case 429:
            if lower.contains("perday") || lower.contains("per day") || lower.contains("daily") {
                return .rateLimit(secondsUntilQuotaReset())
            }
            if let range = lower.range(of: "retrydelay=") {
                let digits = lower[range.upperBound...].prefix { $0.isNumber }
                if let seconds = Double(digits) { return .rateLimit(seconds + 1) }
            }
            return .rateLimit(60)
        case 401, 403:
            return .badKey
        case 400:
            if lower.contains("api key") || lower.contains("api_key") { return .badKey }
            if lower.contains("model") && (lower.contains("not found") || lower.contains("not supported")) {
                return .model(24 * 3600)
            }
            return .badRequest
        case 404:
            return .model(24 * 3600)
        case 500, 502, 503, 504:
            return .model(120)
        default:
            return .model(300)
        }
    }

    /// Дневные лимиты Gemini сбрасываются в полночь по тихоокеанскому времени.
    private static func secondsUntilQuotaReset() -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        return midnight.timeIntervalSince(now) + 60
    }

    private static func supportsThinkingBudget(_ model: String) -> Bool {
        model.contains("2.5") || model.contains("latest") || model.contains("gemini-3")
    }

    // MARK: Состояние

    private func isCooling(_ key: String) -> Bool {
        guard let until = cooldowns[key] else { return false }
        return until > Date()
    }

    private func setCooldown(_ key: String, for seconds: TimeInterval) {
        cooldowns[key] = Date().addingTimeInterval(seconds)
        persistCooldowns()
    }

    private func persistCooldowns() {
        let now = Date()
        let active = cooldowns.filter { $0.value > now }.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(active, forKey: Self.cooldownKey)
    }

    private func recordUsage(tokens: Int) {
        var usage = Self.usageToday()
        usage.requests += 1
        usage.tokens += tokens
        if let data = try? JSONEncoder().encode(usage) {
            UserDefaults.standard.set(data, forKey: Self.usageKey)
        }
    }

    private static func dayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
