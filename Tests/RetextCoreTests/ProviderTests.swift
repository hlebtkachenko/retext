import Foundation
import Testing
@testable import RetextCore

@Suite struct ProviderSettingsTests {
    @Test func oldSettingsLoadAsClaude() throws {
        let settings = try JSONDecoder().decode(RetextSettings.self, from: Data(#"{"actions":[],"claudePath":"/x/claude"}"#.utf8))
        #expect(settings.provider == .claude && settings.codexPath.isEmpty && settings.chatGPTModels.isEmpty)
        #expect(settings.custom == CustomProviderSettings())
        #expect(settings.model(for: .high) == ProviderModel(model: Model.sonnet, effort: "medium"))
    }

    @Test func modelsRoundTripAsObjectsKeyedByLevel() throws {
        var settings = RetextSettings()
        settings.provider = .custom
        settings.chatGPTModels[.high] = ProviderModel(model: "gpt-x", effort: "")
        settings.custom = CustomProviderSettings(baseURL: "http://localhost:11434/v1", models: [.medium: ProviderModel(model: "llama", effort: "low")])
        let json = String(decoding: try settings.encoded(), as: UTF8.self)
        #expect(json.contains(#""chatGPTModels" : {"#) && json.contains(#""high" : {"#))
        #expect(!json.lowercased().contains("key\""))  // no API key field
        let back = try JSONDecoder().decode(RetextSettings.self, from: Data(json.utf8))
        #expect(back == settings)
        // An unknown provider or a broken models block falls back instead of failing the whole file.
        let odd = try JSONDecoder().decode(RetextSettings.self, from: Data(#"{"actions":[],"provider":"gemini","custom":{"baseURL":"u","models":7}}"#.utf8))
        #expect(odd.provider == .claude && odd.custom.baseURL == "u" && odd.custom.models.isEmpty)
    }

    @Test func chatGPTOverridesFallBackPerField() {
        var settings = RetextSettings()
        settings.provider = .chatgpt
        #expect(settings.model(for: .medium) == ProviderModel(model: "gpt-6-luna", effort: "low"))
        #expect(settings.model(for: .high) == ProviderModel(model: "gpt-5.6-terra", effort: "high"))
        #expect(settings.model(for: .max) == ProviderModel(model: "gpt-6-luna", effort: "max"))
        settings.chatGPTModels[.max] = ProviderModel(model: " gpt-5.6-luna ", effort: "")
        settings.chatGPTModels[.high] = ProviderModel(model: "", effort: "low")
        #expect(settings.model(for: .max) == ProviderModel(model: "gpt-5.6-luna", effort: "max"))
        #expect(settings.model(for: .high) == ProviderModel(model: "gpt-5.6-terra", effort: "high"))
    }

    @Test func jobsUseTheActiveProvider() {
        var settings = RetextSettings()
        settings.provider = .custom
        settings.custom.models[.high] = ProviderModel(model: "mistral-large-latest", effort: "")
        let job = Engine.job(for: settings.actions[0], level: .high, settings: settings, bundleID: nil)
        #expect(job.provider == .custom && job.model == "mistral-large-latest" && job.effort.isEmpty)
        #expect(job.system.contains(Engine.highAddOn))
        settings.provider = .chatgpt
        #expect(Engine.job(instruction: "shorter", level: .medium, settings: settings, bundleID: nil).model == "gpt-6-luna")
    }

    @Test func cacheKeySeparatesProvidersAndServers() {
        let claude = Job(title: "t", model: "m", effort: "low", system: "s")
        let chatgpt = Job(title: "t", provider: .chatgpt, model: "m", effort: "low", system: "s")
        let custom = Job(title: "t", provider: .custom, model: "m", effort: "low", system: "s")
        #expect(Engine.cacheKey(claude, text: "x") == Engine.cacheKey(provider: "claude", model: "m", effort: "low", system: "s", text: "x"))
        let keys = [Engine.cacheKey(claude, text: "x"), Engine.cacheKey(chatgpt, text: "x"),
                    Engine.cacheKey(custom, baseURL: "http://a/v1", text: "x"), Engine.cacheKey(custom, baseURL: "http://b/v1", text: "x")]
        #expect(Set(keys).count == 4)
    }

    @Test func endpointNeedsAnHTTPBase() {
        #expect(CustomProviderSettings(baseURL: " https://openrouter.ai/api/v1/ ").endpoint?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(CustomProviderSettings(baseURL: "").endpoint == nil)
        #expect(CustomProviderSettings(baseURL: "localhost:11434").endpoint == nil)
        #expect(CustomProviderSettings(baseURL: "file:///etc").endpoint == nil)
    }

    @Test func apiKeyIsBoundToTheHost() {
        let account = CustomProviderSettings(baseURL: "https://OpenRouter.ai/api/v1").keyAccount
        #expect(account == "custom-api-key:https://openrouter.ai")
        #expect(CustomProviderSettings(baseURL: "https://openrouter.ai/other/v2/").keyAccount == account)
        #expect(CustomProviderSettings(baseURL: "https://evil.example/api/v1").keyAccount != account)
        #expect(CustomProviderSettings(baseURL: "https://openrouter.ai.evil.example/api/v1").keyAccount != account)
        #expect(CustomProviderSettings(baseURL: "http://openrouter.ai/api/v1").keyAccount != account)
        #expect(CustomProviderSettings(baseURL: "http://localhost:11434/v1").keyAccount == "custom-api-key:http://localhost:11434")
        #expect(CustomProviderSettings(baseURL: "http://localhost:1234/v1").keyAccount != CustomProviderSettings(baseURL: "http://localhost:11434/v1").keyAccount)
        #expect(CustomProviderSettings(baseURL: "not a url").keyAccount == nil)
    }

    @Test func localHostsFromRealURLs() {
        func local(_ base: String) -> Bool {
            CustomProviderSettings(baseURL: base).endpoint?.host.map(CustomProviderSettings.isLocal) ?? false
        }
        for base in ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:11434/v1", "http://studio.local:1234/v1",
                     "http://10.0.0.5/v1", "http://172.16.0.1/v1", "http://172.31.255.1/v1", "http://192.168.1.20:11434/v1",
                     "http://169.254.1.1/v1", "http://[fd00::1]:11434/v1", "http://[fc00::1]/v1", "http://[fe80::1]/v1"] {
            #expect(local(base), "\(base)")
        }
        for base in ["https://openrouter.ai/api/v1", "http://10.0.0.1.evil.example/v1", "http://192.168.1.1.nip.io/v1",
                     "http://172.32.0.1/v1", "http://172.15.0.1/v1", "http://[fc::1]/v1", "http://[2001:db8::1]/v1",
                     "http://8.8.8.8/v1", "http://local.evil.example/v1"] {
            #expect(!local(base), "\(base)")
        }
    }

    @Test func keysGoOverHTTPSUnlessTheServerIsLocal() {
        #expect(CustomProviderSettings(baseURL: "http://api.example/v1").needsHTTPS)
        #expect(!CustomProviderSettings(baseURL: "https://api.example/v1").needsHTTPS)
        #expect(!CustomProviderSettings(baseURL: "http://192.168.1.20:11434/v1").needsHTTPS)
        #expect(!CustomProviderSettings(baseURL: "").needsHTTPS)
    }

    @Test func redirectsStayOnTheSameServer() {
        func allows(_ a: String, _ b: String) -> Bool { OpenAICompatible.allowsRedirect(from: URL(string: a)!, to: URL(string: b)!) }
        #expect(allows("https://api.example/v1/chat/completions", "https://API.example:443/v2/chat/completions"))
        #expect(allows("http://localhost:11434/v1", "http://localhost:11434/v1/"))
        #expect(!allows("https://api.example/v1", "https://evil.example/v1"))
        #expect(!allows("https://api.example/v1", "http://api.example/v1"))
        #expect(!allows("http://api.example/v1", "https://api.example/v1"))
        #expect(!allows("https://api.example/v1", "https://api.example:8443/v1"))
        #expect(!allows("https://api.example/v1", "https://api.example.evil.example/v1"))
    }

    @Test func messagesNameTheProvider() {
        #expect(ClaudeFailure.notFound.message(for: .chatgpt).hasPrefix("Codex not found"))
        #expect(ClaudeFailure.notLoggedIn.message(for: .custom) == "API key rejected. Check it in Settings → AI.")
        #expect(ClaudeFailure.other("").message(for: .chatgpt) == "ChatGPT didn't answer. Your text is unchanged.")
        #expect(ClaudeFailure.limit.message == "Claude usage limit reached. Try again later.")
    }
}

@Suite struct CodexTests {
    @Test func tomlStringEscapesEverythingTOMLNeeds() {
        #expect(Codex.tomlString("plain") == #""plain""#)
        #expect(Codex.tomlString("a\"b\\c") == #""a\"b\\c""#)
        #expect(Codex.tomlString("line1\nline2\r\tx") == #""line1\nline2\r\tx""#)
        #expect(Codex.tomlString("\u{1}\u{7F}") == #""\u0001\u007F""#)
        #expect(Codex.tomlString("<text-…> Čeština 😀") == "\"<text-…> Čeština 😀\"")
    }

    @Test func argumentsDisableToolsAndCarryTheSystemPrompt() {
        let args = Codex.arguments(model: "gpt-6-luna", effort: "low", system: "Fix \"it\".\nNow.")
        #expect(args.prefix(6) == ["exec", "--ephemeral", "--skip-git-repo-check", "--ignore-rules", "-s", "read-only"])
        for feature in ["shell_tool", "unified_exec", "computer_use", "browser_use"] {
            #expect(args.contains(feature) && args[args.firstIndex(of: feature)! - 1] == "--disable")
        }
        #expect(args.contains("model_reasoning_effort=\"low\""))
        #expect(args.contains("skills.include_instructions=false") && args[args.firstIndex(of: "skills.include_instructions=false")! - 1] == "-c")
        #expect(args.contains(#"developer_instructions="Fix \"it\".\nNow.""#))
        #expect(args.suffix(2) == ["--json", "-"])
        #expect(!Codex.arguments(model: "m", effort: "", system: "s").contains { $0.hasPrefix("model_reasoning_effort") })
    }

    @Test func parsesTheLastAgentMessageAndUsage() {
        let lines = """
        {"type":"thread.started","thread_id":"t1"}
        {"type":"turn.started"}
        {"type":"item.completed","item":{"id":"i0","type":"reasoning","text":"thinking"}}
        {"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"draft"}}
        {"type":"item.completed","item":{"id":"i2","type":"agent_message","text":"I have two cats.\\n"}}
        {"type":"turn.completed","usage":{"input_tokens":1200,"cached_input_tokens":1000,"output_tokens":9,"reasoning_output_tokens":4}}
        """
        let output = Codex.parse(Data(lines.utf8))
        #expect(output == Codex.Output(text: "I have two cats.", inputTokens: 1200, outputTokens: 13, error: ""))
        #expect(output.claudeOutput.text == "I have two cats." && output.claudeOutput.costUSD == 0)
    }

    @Test func parsesFailuresAndClassifiesThem() {
        let badModel = """
        Reading additional input from stdin...
        {"type":"thread.started","thread_id":"t1"}
        {"type":"error","message":"The 'gpt-9' model is not supported when using Codex with a ChatGPT account."}
        {"type":"turn.failed","error":{"message":"The 'gpt-9' model is not supported when using Codex with a ChatGPT account."}}
        """
        let output = Codex.parse(Data(badModel.utf8))
        #expect(output.text.isEmpty && output.error.contains("not supported"))
        #expect(Codex.classify(output.error) == .unknownModel)
        let noLogin = #"{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: Missing bearer or basic authentication in header"}}"#
        #expect(Codex.classify(Codex.parse(Data(noLogin.utf8)).error) == .notLoggedIn)
        #expect(Codex.classify("You've hit your usage limit. Upgrade to Pro") == .limit)
        #expect(Codex.classify("stream disconnected") == .other("stream disconnected"))
    }

    @Test func listsOnlyVisibleModels() {
        let json = #"{"models":[{"slug":"gpt-reserve","visibility":"hide"},{"slug":"gpt-6-luna","visibility":"list"},{"slug":"gpt-5.6-terra","visibility":"list"}]}"#
        #expect(Codex.listedModels(Data(json.utf8)) == ["gpt-6-luna", "gpt-5.6-terra"])
        #expect(Codex.listedModels(Data("nope".utf8)).isEmpty)
    }
}

@Suite struct OpenAICompatibleTests {
    @Test func bodyHasSystemAndUserAndEffortOnlyWhenSet() throws {
        let object = try #require(JSONSerialization.jsonObject(with: OpenAICompatible.body(model: "m", effort: "", system: "S", user: "U")) as? [String: Any])
        #expect(object["model"] as? String == "m" && object["reasoning_effort"] == nil && object["max_tokens"] == nil)
        let messages = try #require(object["messages"] as? [[String: String]])
        #expect(messages == [["role": "system", "content": "S"], ["role": "user", "content": "U"]])
        let withEffort = try #require(JSONSerialization.jsonObject(with: OpenAICompatible.body(model: "m", effort: "high", system: "S", user: "U")) as? [String: Any])
        #expect(withEffort["reasoning_effort"] as? String == "high")
    }

    @Test func parsesContentAndUsage() throws {
        let json = #"{"id":"x","choices":[{"index":0,"message":{"role":"assistant","content":" I have two cats. "},"finish_reason":"stop"}],"usage":{"prompt_tokens":50,"completion_tokens":6,"total_tokens":56}}"#
        let output = try #require(OpenAICompatible.parse(Data(json.utf8)))
        #expect(output.text == "I have two cats." && output.inputTokens == 50 && output.outputTokens == 6)
        #expect(OpenAICompatible.parse(Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8)) == nil)
        #expect(OpenAICompatible.parse(Data(#"{"choices":[]}"#.utf8)) == nil)
        #expect(!output.isCutOff)
        let cut = try #require(OpenAICompatible.parse(Data(#"{"choices":[{"message":{"content":"I have"},"finish_reason":"length"}]}"#.utf8)))
        #expect(cut.isCutOff)
        #expect(ClaudeFailure.cutOff.message(for: .custom) == "The answer was cut off. Your text is unchanged.")
    }

    @Test func mapsHTTPErrors() {
        let body = Data(#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8)
        #expect(OpenAICompatible.errorMessage(body) == "Incorrect API key provided")
        #expect(OpenAICompatible.failure(status: 401, body: body) == .notLoggedIn)
        #expect(OpenAICompatible.failure(status: 403, body: Data()) == .notLoggedIn)
        #expect(OpenAICompatible.failure(status: 429, body: Data()) == .limit)
        #expect(OpenAICompatible.failure(status: 404, body: Data(#"{"error":{"message":"model 'x' not found"}}"#.utf8)) == .unknownModel)
        #expect(OpenAICompatible.failure(status: 400, body: Data(#"{"error":{"message":"x is not a valid model ID","code":400}}"#.utf8)) == .unknownModel)
        #expect(OpenAICompatible.errorMessage(Data(#"{"code":502,"message":"Provider returned error"}"#.utf8)) == "Provider returned error")
        #expect(OpenAICompatible.failure(status: 500, body: Data()) == .other("HTTP 500"))
    }
}
