import Foundation

/// Where the requests go. One is active at a time (Settings → Engine).
public enum Provider: String, Codable, CaseIterable, Sendable {
    /// `claude -p` with the user's Claude Code login.
    case claude
    /// `codex exec` with the user's ChatGPT login.
    case chatgpt
    /// Any OpenAI-compatible Chat Completions API (OpenRouter, Ollama, LM Studio, Gemini, Mistral, Groq…).
    case custom

    public var title: String {
        switch self {
        case .claude: "Claude Code"
        case .chatgpt: "ChatGPT (Codex)"
        case .custom: "Custom API"
        }
    }

    /// Who answered, for messages such as "Claude didn't answer".
    public var shortTitle: String {
        switch self {
        case .claude: "Claude"
        case .chatgpt: "ChatGPT"
        case .custom: "The API"
        }
    }

    /// Built-in model and effort per level; Custom has none (the user sets them).
    public func defaultModel(_ level: Level) -> ProviderModel {
        switch self {
        case .claude: ProviderModel(model: level.model, effort: level.effort)
        case .chatgpt: Codex.defaultModels[level]!
        case .custom: ProviderModel()
        }
    }
}

/// A model id and its reasoning effort ("" = the model's default).
public struct ProviderModel: Codable, Hashable, Sendable {
    public var model: String
    public var effort: String

    public init(model: String = "", effort: String = "") {
        self.model = model
        self.effort = effort
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = (try? c.decodeIfPresent(String.self, forKey: .model)) ?? ""
        effort = (try? c.decodeIfPresent(String.self, forKey: .effort)) ?? ""
    }

    var trimmed: ProviderModel {
        ProviderModel(model: model.trimmingCharacters(in: .whitespacesAndNewlines), effort: effort.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Encodes `[Level: …]` as a JSON object keyed by the level name, not as an alternating array.
extension Level: CodingKeyRepresentable {}

/// An OpenAI-compatible API. The API key is kept in the Keychain, never here.
public struct CustomProviderSettings: Codable, Equatable, Sendable {
    /// Up to and without `/chat/completions`, e.g. https://openrouter.ai/api/v1.
    public var baseURL = ""
    public var models: [Level: ProviderModel] = [:]

    public init(baseURL: String = "", models: [Level: ProviderModel] = [:]) {
        self.baseURL = baseURL
        self.models = models
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = (try? c.decodeIfPresent(String.self, forKey: .baseURL)) ?? ""
        models = (try? c.decodeIfPresent([Level: ProviderModel].self, forKey: .models)) ?? [:]
    }

    /// Base URL presets offered in Settings.
    public static let presets: [(name: String, url: String)] = [
        ("OpenRouter", "https://openrouter.ai/api/v1"),
        ("Ollama", "http://localhost:11434/v1"),
        ("LM Studio", "http://localhost:1234/v1"),
        ("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai"),
        ("Mistral", "https://api.mistral.ai/v1"),
        ("Groq", "https://api.groq.com/openai/v1"),
    ]

    /// The Keychain account of the API key for this base URL: "custom-api-key:<host>[:port]". The key is saved per host and
    /// looked up for the request's own host, so a base URL changed to another server (by hand or by an imported
    /// settings file) never receives the key saved for the old one. nil without a valid endpoint.
    public var keyAccount: String? {
        guard let url = endpoint, let host = url.host?.lowercased() else { return nil }
        return "custom-api-key:\(host)\(url.port.map { ":\($0)" } ?? "")"
    }

    /// `{base}/chat/completions`, or nil when the base URL isn't an http(s) URL.
    public var endpoint: URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions"), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { return nil }
        return url
    }
}

extension RetextSettings {
    /// The active provider's model and effort for a level: ChatGPT overrides fall back to the built-in ones per field.
    public func model(for level: Level) -> ProviderModel {
        switch provider {
        case .claude: return provider.defaultModel(level)
        case .chatgpt:
            let base = provider.defaultModel(level), own = chatGPTModels[level]?.trimmed ?? ProviderModel()
            return own.model.isEmpty ? base : ProviderModel(model: own.model, effort: own.effort.isEmpty ? base.effort : own.effort)
        case .custom: return custom.models[level]?.trimmed ?? ProviderModel()
        }
    }
}

// MARK: Codex

/// `codex exec --json` with everything that could act on the Mac turned off; see ARCHITECTURE.md.
public enum Codex {
    /// Tested on a ChatGPT Plus account (2026-11-19). Availability varies by plan, so each level can be overridden.
    public static let defaultModels: [Level: ProviderModel] = [
        .medium: ProviderModel(model: "gpt-6-luna", effort: "low"),
        .high: ProviderModel(model: "gpt-5.6-terra", effort: "high"),
        .max: ProviderModel(model: "gpt-6-luna", effort: "max"),
    ]

    /// Tools Codex would otherwise offer the model; `-s read-only` alone still let it run shell commands.
    static let disabledFeatures = ["shell_tool", "unified_exec", "apps", "plugins", "multi_agent", "image_generation", "view_image",
                                   "computer_use", "browser_use", "goals", "hooks", "skill_search", "tool_suggest", "sleep_tool"]

    /// Arguments for `codex exec`; the text goes in on stdin (`-`).
    public static func arguments(model: String, effort: String, system: String) -> [String] {
        var args = ["exec", "--ephemeral", "--skip-git-repo-check", "--ignore-rules", "-s", "read-only"]
        for feature in disabledFeatures { args += ["--disable", feature] }
        args += ["-m", model]
        if !effort.isEmpty { args += ["-c", "model_reasoning_effort=\(tomlString(effort))"] }
        // skills.include_instructions=false: otherwise the list of the user's skills (~/.agents/skills, Codex's system
        // skills) goes into every prompt.
        args += ["-c", "approval_policy=never", "-c", "web_search=disabled", "-c", "skills.include_instructions=false",
                 "-c", "developer_instructions=\(tomlString(system))", "--json", "-"]
        return args
    }

    /// A TOML basic string: `-c key=value` parses the value as TOML.
    public static func tomlString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F: out += String(format: "\\u%04X", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// The last agent message, the token counts and any error from `codex exec --json` (one JSON object per line).
    public struct Output: Sendable, Equatable {
        public var text = ""
        public var inputTokens = 0
        public var outputTokens = 0
        /// `turn.failed` or `error` messages, joined; "" when there were none.
        public var error = ""

        public var claudeOutput: ClaudeOutput {
            ClaudeOutput(result: text, inputTokens: inputTokens, outputTokens: outputTokens)
        }
    }

    public static func parse(_ data: Data) -> Output {
        var output = Output()
        var errors: [String] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            switch event["type"] as? String {
            case "item.completed":
                if let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message", let text = item["text"] as? String {
                    output.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "turn.completed":
                let usage = event["usage"] as? [String: Any] ?? [:]
                output.inputTokens += usage["input_tokens"] as? Int ?? 0
                output.outputTokens += (usage["output_tokens"] as? Int ?? 0) + (usage["reasoning_output_tokens"] as? Int ?? 0)
            case "turn.failed":
                if let message = (event["error"] as? [String: Any])?["message"] as? String { errors.append(message) }
            case "error":
                if let message = event["message"] as? String { errors.append(message) }
            default: break
            }
        }
        output.error = errors.joined(separator: "\n")
        return output
    }

    /// Visible model slugs from `codex debug models` (JSON `{"models":[{"slug","visibility",…}]}`).
    public static func listedModels(_ data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.filter { $0["visibility"] as? String == "list" }.compactMap { $0["slug"] as? String }
    }

    /// Sorts Codex's error text. Note: substring matching on Codex's wording; extend when its messages change.
    public static func classify(_ text: String) -> ClaudeFailure {
        let t = text.lowercased()
        if t.contains("model is not supported") || t.contains("model_not_found") || t.contains("does not exist") { return .unknownModel }
        if ["401", "unauthorized", "missing bearer", "not logged in", "codex login"].contains(where: t.contains) { return .notLoggedIn }
        if ["usage limit", "rate limit", "429", "too many requests", "quota"].contains(where: t.contains) { return .limit }
        return ClaudeFailure.classify(text)
    }
}

// MARK: OpenAI-compatible

public enum OpenAICompatible {
    /// The Chat Completions request body; `reasoning_effort` only when set.
    public static func body(model: String, effort: String, system: String, user: String) -> Data {
        var body: [String: Any] = ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        if !effort.isEmpty { body["reasoning_effort"] = effort }
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// `choices[0].message.content` and the token counts, or nil when the answer has no text.
    public static func parse(_ data: Data) -> ClaudeOutput? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let usage = object["usage"] as? [String: Any] ?? [:]
        return ClaudeOutput(result: content, inputTokens: usage["prompt_tokens"] as? Int ?? 0, outputTokens: usage["completion_tokens"] as? Int ?? 0)
    }

    /// `{"error":{"message"}}`, `{"error":"…"}` or `{"message"}` (OpenRouter), else the body as text.
    public static func errorMessage(_ data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let error = object?["error"]
        let message = (error as? [String: Any])?["message"] as? String ?? error as? String ?? object?["message"] as? String
        return message ?? String(decoding: data.prefix(300), as: UTF8.self)
    }

    /// From the HTTP status and the error body.
    public static func failure(status: Int, body: Data) -> ClaudeFailure {
        let message = errorMessage(body)
        switch status {
        case 401, 403: return .notLoggedIn
        case 429: return .limit
        case 404 where message.lowercased().contains("model"): return .unknownModel
        default:
            let t = message.lowercased()
            if t.contains("model") && (t.contains("not found") || t.contains("does not exist") || t.contains("invalid model") || t.contains("not a valid model")) { return .unknownModel }
            return ClaudeFailure.classify(message.isEmpty ? "HTTP \(status)" : message)
        }
    }
}
