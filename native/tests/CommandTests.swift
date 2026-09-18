import Foundation

@main
enum CommandTests {
    static func main() throws {
        var failures: [String] = []
        var count = 0
        func expect(_ condition: Bool, _ label: String) {
            count += 1
            if !condition { failures.append(label) }
        }

        expect(MacCommands.parse("open Safari") == .openApp("Safari"), "Explicit app opening")
        expect(MacCommands.parse(" Launch app Visual Studio Code. ") == .openApp("Visual Studio Code"), "App names with spaces")
        expect(MacCommands.parse("open Calculator") == .openApp("Calculator"), "Built-in app")
        expect(MacCommands.parse("what time is it?") == .time, "Time question")
        expect(MacCommands.parse("what is today's date?") == .date, "Date question")
        expect(MacCommands.parse("run diagnostics") == .systemStatus, "Diagnostics")
        expect(MacCommands.parse("set volume to 40 percent") == .volume(40), "Volume percentage")
        expect(MacCommands.parse("set volume 0") == .volume(0), "Volume lower bound")
        expect(MacCommands.parse("set volume to 100%") == .volume(100), "Volume upper bound")
        expect(MacCommands.parse("mute") == .mute(true), "Mute")
        expect(MacCommands.parse("unmute audio") == .mute(false), "Unmute")
        expect(MacCommands.parse("search web for Swift & macOS") == .webSearch("Swift & macOS"), "Search preserves query")

        // Dictation includes punctuation, polite prefixes, and numbers spelled as words.
        expect(MacCommands.parse("Hey Jarvis, please open Safari.") == .openApp("Safari"), "Wake phrase and polite prefix")
        expect(MacCommands.parse("J.A.R.V.I.S., could you open Calculator, please?") == .openApp("Calculator"), "Punctuated name and polite question")
        expect(MacCommands.parse("Please, can you tell me the time?") == .time, "Natural time question")
        expect(MacCommands.parse("Jarvis what is today’s date?") == .date, "Dictation apostrophe")
        expect(MacCommands.parse("Could you show me the system status, please?") == .systemStatus, "Natural diagnostic request")
        expect(MacCommands.parse("Please set the volume to forty percent.") == .volume(40), "Spoken tens")
        expect(MacCommands.parse("Jarvis, set volume to twenty-five percent") == .volume(25), "Spoken hyphenated number")
        expect(MacCommands.parse("set volume to one hundred percent") == .volume(100), "Spoken upper bound")
        expect(MacCommands.parse("set volume to zero") == .volume(0), "Spoken zero")
        expect(MacCommands.parse("Can you unmute the sound?") == .mute(false), "Natural unmute")
        expect(MacCommands.parse("Jarvis, search the web for Swift & macOS") == .webSearch("Swift & macOS"), "Wake phrase preserves search query")
        expect(MacCommands.parse("search web for how to say please?") == .webSearch("how to say please?"), "Politeness normalization preserves literal search data")
        for command: MacCommand in [.openApp("Safari"), .volume(40), .mute(true), .webSearch("local weather")] {
            expect(command.requiresOwnerConfirmation, "Mutating or browser command requires native owner confirmation: \(command)")
        }
        for command: MacCommand in [.time, .date, .systemStatus] {
            expect(!command.requiresOwnerConfirmation, "Read-only local information needs no Mac action approval: \(command)")
        }

        for input in ["", "Can you explain how to open Safari?", "I want to open Terminal", "open /tmp/script.sh", "open https://example.com", "open Safari; rm -rf /", "open Safari\nopen Terminal", "set volume 101", "set volume -1", "set volume 1.5", "volume is 50", "mute everyone on this call", "search web for", "tell me about system status", "Jarvis, explain how to mute audio", "Please don't open Safari", "Do not set volume to forty", "please set volume to one hundred one", "set volume to twenty five five", "set volume to forty and then mute", "pretend Jarvis open Safari", "Can you explain what time is it?"] {
            expect(MacCommands.parse(input) == nil, "Reject ambiguous or invalid command: \(input)")
        }

        let tags = Data(#"{"models":[{"name":"llama3.2:3b"},{"name":"local:latest","remote_model":"cloud-model"},{"name":"hosted:latest","remote_host":"https://ollama.com"},{"name":"gemma4:cloud"},{"name":"old-cloud:latest","details":{"remote_host":"https://ollama.com"}},{"name":"gpt-oss:120b-cloud"},{"name":"llama3.2:3b"},{"name":"qwen3:4b","remote_host":""}]}"#.utf8)
        expect(try OllamaClient.localModelNames(from: tags) == ["llama3.2:3b", "qwen3:4b"], "Only local model entries, unique and sorted")
        expect(try OllamaClient.localModelNames(from: Data(#"{"models":[]}"#.utf8)).isEmpty, "Empty model library")
        do {
            _ = try OllamaClient.localModelNames(from: Data(#"{"error":"not ready"}"#.utf8))
            expect(false, "Invalid tags payload must fail")
        } catch { expect(true, "Invalid tags payload fails") }

        // These use only date/time reads: a failed cancellation test cannot mutate the Mac.
        let commands = MacCommands()
        var canceledReplyDelivered = false
        var canceledFallbackDelivered = false
        var freshReply: MacCommandResult?
        commands.execute("what time is it?") { _ in canceledReplyDelivered = true }
        commands.execute("Explain orbital mechanics") { _ in canceledFallbackDelivered = true }
        commands.cancel()
        commands.execute("what is today's date?") { freshReply = $0 }
        let deadline = Date().addingTimeInterval(2)
        while freshReply == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        expect(!canceledReplyDelivered, "Canceled queued command cannot deliver a reply")
        expect(!canceledFallbackDelivered, "Canceled unknown input cannot start an AI fallback")
        expect(freshReply?.action == "Local date", "New commands still work after cancellation")

        if !failures.isEmpty {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("\(count) command/model checks passed; no apps launched or system settings changed.")
    }
}
