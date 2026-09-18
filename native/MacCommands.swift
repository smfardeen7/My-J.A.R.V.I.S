import AppKit
import CoreAudio
import IOKit.ps
import Darwin

enum MacCommand: Equatable {
    case openApp(String), time, date, systemStatus, volume(Int), mute(Bool), webSearch(String)

    /// The native owner gate must approve every action that changes the Mac or opens a URL.
    var requiresOwnerConfirmation: Bool {
        switch self {
        case .openApp, .volume, .mute, .webSearch: return true
        case .time, .date, .systemStatus: return false
        }
    }
}

struct MacCommandResult {
    let text: String
    let action: String
}

final class MacCommands {
    private let generationLock = NSLock()
    private var generation = UUID()

    /// Invalidates queued commands and late replies; already-started macOS actions are not undone.
    func cancel() {
        generationLock.lock()
        generation = UUID()
        generationLock.unlock()
    }

    private func currentGeneration() -> UUID {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation
    }

    /// Parsing is independent of execution; model replies never pass through this method.
    static func parse(_ text: String) -> MacCommand? {
        guard text.count <= 2_000, text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let spokenInput = normalizedCommand(text)
        // Search contents are literal user data: do not remove their punctuation or a final "please".
        if let query = capture(#"^search (?:the )?web for (.+)$"#, in: spokenInput)?.trimmingCharacters(in: .whitespaces),
           !query.isEmpty { return .webSearch(query) }
        let input = spokenInput.replacingOccurrences(of: #"(?:,?\s+please)[.!?]*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        let phrase = input.lowercased()
        switch phrase {
        case "time", "what time is it", "what is the time", "what's the time", "tell me the time", "tell me what time it is": return .time
        case "date", "what is today's date", "what's today's date", "what is the date", "what day is it", "what day is today", "what's the date", "tell me today's date": return .date
        case "system status", "system diagnostics", "diagnostics", "run diagnostics", "show system status", "show me the system status", "show me system status", "check system status": return .systemStatus
        case "mute", "mute audio", "mute volume", "mute sound", "mute the audio", "mute the sound": return .mute(true)
        case "unmute", "unmute audio", "unmute volume", "unmute sound", "unmute the audio", "unmute the sound": return .mute(false)
        default: break
        }
        if let raw = capture(#"^set (?:the )?volume(?: to)? ([a-z0-9 -]+?)(?:%| percent| per cent)?$"#, in: input),
           let value = spokenPercentage(raw) { return .volume(value) }
        if var name = capture(#"^(?:open|launch)(?: (?:app|application))? (.+)$"#, in: input) {
            if name.hasSuffix(".") { name.removeLast() }
            name = name.trimmingCharacters(in: .whitespaces)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-'’&()+"))
            guard !name.isEmpty, name.count <= 120,
                  name.rangeOfCharacter(from: allowed.inverted) == nil,
                  name.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
            return .openApp(name)
        }
        return nil
    }

    /// Only remove complete, anchored address/politeness phrases. Never search inside a sentence
    /// for an imperative: "explain how to open Safari" must stay a conversation, not an action.
    private static func normalizedCommand(_ text: String) -> String {
        var input = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        input = input.replacingOccurrences(of: #"^(?:(?:hey|okay|ok) )?(?:jarvis|j\.a\.r\.v\.i\.s\.?)(?:\s*[,!:]\s*|\s+)"#, with: "", options: [.regularExpression, .caseInsensitive])
        // Two rounds support both "please, can you ..." and "could you please ...".
        for _ in 0..<2 {
            input = input.replacingOccurrences(of: #"^(?:please[, ]+|(?:can|could|would) you )"#, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return input.trimmingCharacters(in: .whitespaces)
    }

    private static func spokenPercentage(_ text: String) -> Int? {
        let raw = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let value = Int(raw), (0...100).contains(value) { return value }
        let words = raw.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        let units = ["zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                     "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
                     "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
                     "eighteen": 18, "nineteen": 19]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        if words == ["one", "hundred"] || words == ["a", "hundred"] { return 100 }
        if words.count == 1 { return units[words[0]] ?? tens[words[0]] }
        if words.count == 2, let ten = tens[words[0]], let unit = units[words[1]], (1...9).contains(unit) { return ten + unit }
        return nil
    }

    func execute(_ text: String, completion: @escaping (MacCommandResult?) -> Void) {
        let requestGeneration = currentGeneration()
        let deliver: (MacCommandResult?) -> Void = { [weak self] result in
            guard let self = self, self.currentGeneration() == requestGeneration else { return }
            completion(result)
        }
        guard let command = Self.parse(text) else {
            DispatchQueue.main.async { deliver(nil) }
            return
        }
        DispatchQueue.main.async {
            guard self.currentGeneration() == requestGeneration else { return }
            self.perform(command, completion: deliver)
        }
    }

    private func perform(_ command: MacCommand, completion: @escaping (MacCommandResult?) -> Void) {
        switch command {
        case .openApp(let name):
            guard let url = applicationURL(named: name) else {
                completion(MacCommandResult(text: "I couldn't find an installed app named \(name). Try its exact application name.", action: "App not found"))
                return
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(MacCommandResult(text: "I couldn't open \(name): \(error.localizedDescription)", action: "App launch failed"))
                    } else if app != nil {
                        completion(MacCommandResult(text: "Opened \(name).", action: "Opened \(name)"))
                    } else {
                        completion(MacCommandResult(text: "macOS did not confirm that \(name) opened.", action: "App launch unconfirmed"))
                    }
                }
            }
        case .time, .date:
            let formatter = DateFormatter()
            formatter.dateStyle = command == .date ? .full : .none
            formatter.timeStyle = command == .time ? .short : .none
            completion(MacCommandResult(text: "It's \(formatter.string(from: Date())).", action: command == .time ? "Local time" : "Local date"))
        case .systemStatus:
            completion(MacCommandResult(text: Self.systemStatus(), action: "Live system diagnostics"))
        case .volume(let percent):
            let success = Self.setOutputVolume(percent)
            completion(MacCommandResult(text: success ? "Output volume set to \(percent)%." : "This output device doesn't allow software volume control. Use its hardware controls or select a different output in System Settings.", action: success ? "Volume \(percent)%" : "Volume unavailable"))
        case .mute(let muted):
            let success = Self.setOutputMute(muted)
            completion(MacCommandResult(text: success ? (muted ? "Output muted." : "Output unmuted.") : "This output device doesn't expose a mute control to macOS.", action: success ? (muted ? "Audio muted" : "Audio unmuted") : "Mute unavailable"))
        case .webSearch(let query):
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            let opened = components.url.map { NSWorkspace.shared.open($0) } ?? false
            completion(MacCommandResult(text: opened ? "Opened a web search for \(query)." : "I couldn't open the web search in your default browser.", action: opened ? "Web search opened" : "Web search failed"))
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func applicationURL(named requestedName: String) -> URL? {
        let name = requestedName.lowercased().replacingOccurrences(of: #"\.app$"#, with: "", options: .regularExpression)
        let aliases = [
            "safari": "com.apple.Safari", "finder": "com.apple.finder", "terminal": "com.apple.Terminal",
            "notes": "com.apple.Notes", "calendar": "com.apple.iCal", "calculator": "com.apple.calculator",
            "textedit": "com.apple.TextEdit", "preview": "com.apple.Preview", "music": "com.apple.Music",
            "mail": "com.apple.mail", "maps": "com.apple.Maps", "photos": "com.apple.Photos",
            "system settings": "com.apple.systempreferences", "settings": "com.apple.systempreferences",
            "activity monitor": "com.apple.ActivityMonitor", "app store": "com.apple.AppStore",
            "chrome": "com.google.Chrome", "google chrome": "com.google.Chrome",
            "vscode": "com.microsoft.VSCode", "visual studio code": "com.microsoft.VSCode"
        ]
        if let bundleID = aliases[name], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return url }

        let fileManager = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities"), fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        for root in roots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 3 { enumerator.skipDescendants(); continue }
                guard url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                guard let bundle = Bundle(url: url) else { continue }
                let names = [url.deletingPathExtension().lastPathComponent, bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, bundle.object(forInfoDictionaryKey: "CFBundleName") as? String].compactMap { $0?.lowercased() }
                if names.contains(name) { return url }
            }
        }
        return nil
    }

    private static func systemStatus() -> String {
        let process = ProcessInfo.processInfo
        let totalGB = Double(process.physicalMemory) / 1_073_741_824
        let uptime = Int(process.systemUptime)
        var parts = ["\(process.operatingSystemVersionString).", "\(process.activeProcessorCount) logical CPU cores.", String(format: "%.1f GB physical memory.", totalGB)]
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        if status == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS {
            let freeGB = Double(statistics.free_count) * Double(pageSize) / 1_073_741_824
            parts.append(String(format: "%.2f GB currently free (cached memory is separate).", freeGB))
        }
        parts.append("Uptime: \(uptime / 86_400)d \((uptime % 86_400) / 3_600)h \((uptime % 3_600) / 60)m.")
        if let battery = batteryStatus() { parts.append(battery) }
        return parts.joined(separator: " ")
    }

    private static func batteryStatus() -> String? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSIsPresentKey] as? Bool != false,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool == true
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let state = charging ? "charging" : (onAC ? "connected to power" : "on battery")
            return "Battery: \(Int((Double(current) / Double(maximum) * 100).rounded()))%, \(state)."
        }
        return nil
    }

    private static func outputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func writableAddresses(device: AudioObjectID, selector: AudioObjectPropertySelector) -> [AudioObjectPropertyAddress] {
        func writable(_ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress? {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return nil }
            return address
        }
        if let master = writable(kAudioObjectPropertyElementMain) { return [master] }
        return [AudioObjectPropertyElement(1), AudioObjectPropertyElement(2)].compactMap(writable)
    }

    private static func setOutputVolume(_ percent: Int) -> Bool {
        guard let device = outputDevice() else { return false }
        let addresses = writableAddresses(device: device, selector: kAudioDevicePropertyVolumeScalar)
        guard !addresses.isEmpty else { return false }
        var value = Float32(percent) / 100
        // Visit every channel even if one fails; never claim full success after a partial write.
        let results = addresses.map { address -> Bool in
            var property = address
            return AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
        }
        return results.allSatisfy { $0 }
    }

    private static func setOutputMute(_ muted: Bool) -> Bool {
        guard let device = outputDevice() else { return false }
        let addresses = writableAddresses(device: device, selector: kAudioDevicePropertyMute)
        guard !addresses.isEmpty else { return false }
        var value: UInt32 = muted ? 1 : 0
        let results = addresses.map { address -> Bool in
            var property = address
            return AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        }
        return results.allSatisfy { $0 }
    }
}
