import AppKit
import WebKit

final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL
    init(root: URL) { self.root = root.standardizedFileURL }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.scheme == "jarvis", url.host == "app" else {
            task.didFailWithError(URLError(.unsupportedURL)); return
        }
        let relative = url.path == "/" || url.path.isEmpty ? "index.html" : String(url.path.dropFirst())
        let file = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist)); return
        }
        let types = ["html":"text/html", "js":"text/javascript", "css":"text/css", "svg":"image/svg+xml", "woff":"font/woff", "woff2":"font/woff2", "png":"image/png", "json":"application/json"]
        let response = URLResponse(url: url, mimeType: types[file.pathExtension] ?? "application/octet-stream", expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var statusItem: NSStatusItem!
    private let commands = MacCommands()
    private let ollama = OllamaClient()
    private let ownerVoice = OwnerVoiceService()
    private let ownerAuth = OwnerAuthenticator()
    private var capturingEnrollment = false
    private var voice: VoiceService!
    private var generation = UUID()
    private var busy = false
    private var modelNames: [String] = []
    private var model = UserDefaults.standard.string(forKey: "localModel") ?? "qwen3.5:4b"
    private var soundEnabled = UserDefaults.standard.object(forKey: "spokenReplies") as? Bool ?? true
    private var ollamaProcess: Process?
    private var isReady = false
    private var connected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        voice = VoiceService { [weak self] type, payload in self?.voiceEvent(type, payload) }
        voice.onCapturedSpeech = { [weak self] text, recording in self?.verifyVoice(text, recording: recording) }
        voice.recognitionLocale = UserDefaults.standard.string(forKey: "recognitionLocale")
        setupMenu()
        let config = WKWebViewConfiguration()
        let content = WKUserContentController()
        content.add(self, name: "jarvis")
        content.addUserScript(WKUserScript(source: "Object.defineProperty(window, '__JARVIS_DESKTOP__', {value: true, writable: false});", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = content
        config.setURLSchemeHandler(BundleSchemeHandler(root: Bundle.main.resourceURL!.appendingPathComponent("web")), forURLScheme: "jarvis")
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = NSColor(srgbRed: 0.02, green: 0.027, blue: 0.039, alpha: 1)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 940), styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView], backing: .buffered, defer: false)
        window.title = "J.A.R.V.I.S."
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(srgbRed: 0.02, green: 0.027, blue: 0.039, alpha: 1)
        window.contentView = webView
        window.minSize = NSSize(width: 800, height: 720)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setContentSize(NSSize(width: min(1380, visible.width - 48), height: min(940, visible.height - 48)))
            window.center()
        }
        webView.load(URLRequest(url: URL(string:"jarvis://app/index.html")!))
        showWindow()
    }

    private func setupMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About J.A.R.V.I.S.", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Show J.A.R.V.I.S.", action: #selector(showWindow), keyEquivalent: "j")
        appMenu.addItem(withTitle: "Stop current activity", action: #selector(stopCurrent), keyEquivalent: ".")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit J.A.R.V.I.S.", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title:"Edit"); editItem.submenu = editMenu
        editMenu.addItem(withTitle:"Undo",action:Selector(("undo:")),keyEquivalent:"z")
        editMenu.addItem(withTitle:"Cut",action:#selector(NSText.cut(_:)),keyEquivalent:"x")
        editMenu.addItem(withTitle:"Copy",action:#selector(NSText.copy(_:)),keyEquivalent:"c")
        editMenu.addItem(withTitle:"Paste",action:#selector(NSText.paste(_:)),keyEquivalent:"v")
        editMenu.addItem(withTitle:"Select All",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a")
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"circle.hexagongrid.fill", accessibilityDescription:"J.A.R.V.I.S.")
        let statusMenu = NSMenu()
        statusMenu.addItem(withTitle:"Show J.A.R.V.I.S.",action:#selector(showWindow),keyEquivalent:"").target = self
        statusMenu.addItem(withTitle:"Stop voice and thinking",action:#selector(stopCurrent),keyEquivalent:"").target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle:"Quit J.A.R.V.I.S.",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
        statusItem.menu = statusMenu
    }
    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"J.A.R.V.I.S.", .credits:NSAttributedString(string:"Your private Mac assistant. Local AI powered by Ollama. Voice and Mac commands stay on this device.")])
    }
    @objc func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldHandleReopen(_ sender:NSApplication, hasVisibleWindows:Bool)->Bool {showWindow();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func windowWillClose(_ notification:Notification) { stopCurrent() }
    func applicationWillTerminate(_ notification:Notification) {
        ownerAuth.cancel(); ownerVoice.endEnrollment(); voice.shutdown(); ollama.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(forName:"jarvis")
        if let process = ollamaProcess, process.isRunning {process.terminate()}
    }
    func webView(_ webView:WKWebView, decidePolicyFor action:WKNavigationAction, decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url = action.request.url else {decisionHandler(.cancel);return}
        decisionHandler(url.scheme == "jarvis" && url.host == "app" ? .allow : .cancel)
    }
    func webView(_ webView:WKWebView, createWebViewWith configuration:WKWebViewConfiguration, for action:WKNavigationAction, windowFeatures:WKWindowFeatures)->WKWebView? {nil}
    func webView(_ webView:WKWebView, didFailProvisionalNavigation navigation:WKNavigation!, withError error:Error) {showLoadError(error)}
    private func showLoadError(_ error:Error) {
        let alert=NSAlert();alert.messageText="J.A.R.V.I.S. could not load";alert.informativeText=error.localizedDescription;alert.runModal()
    }
    func userContentController(_ controller:WKUserContentController, didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "jarvis", message.frameInfo.request.url?.host == "app", let body=message.body as? [String:Any], let action=body["action"] as? String else {return}
        let payload=body["payload"] as? [String:Any] ?? [:]
        switch action {
        case "ready": isReady=true; emitConfig(); emitOwner(); refreshModels(startServer:true)
        case "command":
            guard let text=payload["text"] as? String, !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count <= 8000 else {return}
            execute(text)
        case "listen":
            stopCurrent(); emit("error",["message":""])
            guard ownerVoice.enrolled && ownerVoice.runtimeReady else {
                emit("error",["message":"Fardeen, enroll your voice below before using the microphone. Voice commands are locked until setup is complete."]);emitOwner();return
            }
            capturingEnrollment=false;voice.startListening()
        case "stopListening": voice.stopListening(submit:true)
        case "cancel": stopCurrent();ownerVoice.endEnrollment();emitOwner();log("Activity stopped")
        case "enroll": beginEnrollment()
        case "enrollSample":
            stopActivity(preservingEnrollment:true)
            guard ownerVoice.enrollmentIsAuthorized else { beginEnrollment();return }
            capturingEnrollment=true;emit("error",["message":""]);voice.startListening(enrollment:true);emitOwner()
        case "forgetVoice":
            stopCurrent();busy=true;emit("state",["state":"processing"])
            let token=generation
            ownerAuth.confirm("Delete Fardeen's saved JARVIS voice profile") { [weak self] result in
                guard let self=self,self.generation == token else{return}
                self.busy=false;self.emit("state",["state":"idle"])
                switch result {
                case .success:do{try self.ownerVoice.forget();self.log("Voice profile deleted; microphone locked");self.emitOwner()}catch{self.emit("error",["message":error.localizedDescription])}
                case .failure(let error):self.emit("error",["message":error.localizedDescription])
                }
            }
        case "recognitionLocale":
            guard let locale=payload["locale"] as? String,["","en-US","en-GB","en-IN","en-AU"].contains(locale) else{return}
            stopCurrent();voice.recognitionLocale=locale.isEmpty ? nil:locale
            UserDefaults.standard.set(locale.isEmpty ? nil:locale,forKey:"recognitionLocale");emitOwner()
        case "sound":
            guard let enabled=payload["enabled"] as? Bool else {return}
            soundEnabled=enabled;UserDefaults.standard.set(enabled,forKey:"spokenReplies")
            if !enabled {voice.stopSpeaking()};emitConfig()
        case "model":
            guard let name=payload["name"] as? String, modelNames.contains(name) else {return}
            stopCurrent();model=name;UserDefaults.standard.set(name,forKey:"localModel");ollama.clearHistory();emitConfig();log("Local model changed")
        case "refresh": refreshModels(startServer:true)
        case "clear": stopCurrent();ollama.clearHistory();emit("response",["text":""]);emit("transcript",["text":"", "final":false]);log("Conversation cleared")
        case "fullscreen":window.toggleFullScreen(nil)
        default:break
        }
    }
    @objc func stopCurrent() { stopActivity() }
    private func stopActivity(preservingEnrollment:Bool=false) {
        generation=UUID();busy=false
        ownerAuth.cancel()
        if preservingEnrollment {ownerVoice.cancel()} else {ownerVoice.endEnrollment()}
        capturingEnrollment=false
        commands.cancel();ollama.cancel();voice.stopListening(submit:false);voice.stopSpeaking()
        emit("state",["state":"idle"]);emit("amplitude",["value":0.0])
        emitOwner()
    }
    private func execute(_ text:String) {
        stopCurrent();emit("error",["message":""])
        let token=generation
        busy=true
        emit("command",["text":text]);emit("response",["text":""]);emit("state",["state":"processing"])
        log("Processing your request")
        if MacCommands.parse(text)?.requiresOwnerConfirmation == true {
            log("Waiting for Touch ID confirmation")
            ownerAuth.confirm("Confirm JARVIS action: \(String(text.prefix(160)))") { [weak self] result in
                guard let self=self,self.generation == token else{return}
                switch result {
                case .success:self.dispatch(text,token:token)
                case .failure(let error):self.busy=false;self.emit("state",["state":"idle"]);self.emit("error",["message":error.localizedDescription]);self.log("Mac action was not authorized",tone:"warning")
                }
            }
        } else {dispatch(text,token:token)}
    }
    private func dispatch(_ text:String,token:UUID) {
        guard generation == token else{return}
        commands.execute(text) { [weak self] result in
            guard let self=self, self.generation == token else {return}
            if let result=result {self.ollama.recordCommandResult(command:text,result:result.text,model:self.model);self.deliver(result.text, token:token);self.log(result.action);return}
            if !self.modelNames.contains(self.model) {self.busy=false;self.emit("state",["state":"idle"]);self.emit("error",["message":"The local AI model is not ready. Open Local AI below to refresh the connection. Mac commands still work."]);return}
            self.ollama.chat(message:text, model:self.model) { [weak self] result in
                guard let self=self,self.generation == token else {return}
                switch result {
                case .success(let response):self.deliver(response,token:token);self.log("Local response ready")
                case .failure(let error):self.busy=false;self.emit("state",["state":"idle"]);self.emit("error",["message":error.localizedDescription]);self.log("Local AI needs attention",tone:"warning")
                }
            }
        }
    }
    private func deliver(_ text:String,token:UUID) {
        guard generation == token else {return}
        busy=false;emit("response",["text":text])
        if soundEnabled {voice.speak(text)} else {emit("state",["state":"idle"])}
    }
    private func voiceEvent(_ type:String,_ payload:[String:Any]) {
        if !Thread.isMainThread {DispatchQueue.main.async{[weak self] in self?.voiceEvent(type,payload)};return}
        emit(type,payload)
        switch type {
        case "listening":
            if payload["active"] as? Bool == true {emit("state",["state":"listening"])}
            else if payload["finalizing"] as? Bool == true {emit("state",["state":"processing"])}
            else if payload["starting"] as? Bool != true && !busy {emit("state",["state":"idle"])}
        // Transcripts never execute directly. Only verified captures enter execute().
        case "speech":if payload["active"] as? Bool == true {emit("state",["state":"speaking"])} else if !busy {emit("state",["state":"idle"])}
        case "error":if !(payload["message"] as? String ?? "").isEmpty {log("Voice needs attention",tone:"warning");if !busy{emit("state",["state":"idle"])}}
        default:break
        }
    }
    private func refreshModels(startServer:Bool) {
        ollama.models { [weak self] result in
            guard let self=self else{return}
            switch result {
            case .success(let names):
                self.connected=true;self.modelNames=names
                if !names.contains(self.model),let first=names.first {self.model=names.contains("qwen3.5:4b") ? "qwen3.5:4b" : first}
                self.emitConfig();self.log(names.isEmpty ? "No local model installed" : "Local AI connected",tone:names.isEmpty ? "warning":"success")
            case .failure:
                self.connected=false;self.emitConfig()
                if startServer && self.startOllama() {DispatchQueue.main.asyncAfter(deadline:.now()+2){[weak self] in self?.refreshModels(startServer:false)}}
                else {self.log("Ollama is not running",tone:"warning")}
            }
        }
    }
    private func startOllama()->Bool {
        if let process=ollamaProcess,process.isRunning{return true}
        let paths=["/Applications/Ollama.app/Contents/Resources/ollama", NSHomeDirectory()+"/Applications/Ollama.app/Contents/Resources/ollama", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        guard let path=paths.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else{return false}
        let process=Process();process.executableURL=URL(fileURLWithPath:path);process.arguments=["serve"]
        var environment=ProcessInfo.processInfo.environment;environment["OLLAMA_HOST"]="127.0.0.1:11434";environment["OLLAMA_NO_CLOUD"]="1";process.environment=environment
        process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
        do{try process.run();ollamaProcess=process;return true}catch{return false}
    }
    private func emitConfig() {
        emit("config",["model":model,"models":modelNames,"connected":connected,"soundEnabled":soundEnabled,"device":"This Mac","memoryGB":Int(ProcessInfo.processInfo.physicalMemory/1_073_741_824)])
    }
    private func emitOwner() {
        emit("owner",["name":"Fardeen","enrolled":ownerVoice.enrolled,"runtimeReady":ownerVoice.runtimeReady,"enrolling":ownerVoice.enrolling,"samples":ownerVoice.sampleCount,"phrase":ownerVoice.phrase,"locale":voice.recognitionLocale ?? ""])
    }
    private func beginEnrollment() {
        stopCurrent();ownerVoice.endEnrollment();emit("error",["message":""])
        guard ownerVoice.runtimeReady else {emit("error",["message":"Install the local voice model before enrollment. Voice commands stay locked."]);emitOwner();return}
        busy=true;emit("state",["state":"processing"])
        let token=generation
        ownerAuth.confirm("Set up Fardeen's JARVIS voice profile. Only Fardeen should record the three samples.") { [weak self] result in
            guard let self=self,self.generation == token else{return}
            self.busy=false;self.emit("state",["state":"idle"])
            switch result {
            case .success:self.ownerVoice.beginEnrollment();self.emitOwner();self.log("Ready to record three voice samples")
            case .failure(let error):self.emit("error",["message":error.localizedDescription]);self.emitOwner()
            }
        }
    }
    private func verifyVoice(_ text:String,recording:URL) {
        let enrollment=capturingEnrollment
        capturingEnrollment=false
        let token=generation
        busy=true;emit("state",["state":"processing"])
        log(enrollment ? "Checking enrollment sample":"Checking voice match")
        ownerVoice.consume(recording,enrollment:enrollment) { [weak self] result in
            guard let self=self,self.generation == token else{return}
            self.busy=false;self.emit("state",["state":"idle"]);self.emitOwner()
            switch result {
            case .success(let accepted):
                if enrollment {
                    self.emit("transcript",["text":"","final":false])
                    self.log(self.ownerVoice.enrolling ? "Voice sample saved; record the next phrase":"Fardeen's voice profile is ready",tone:"success")
                    if !self.ownerVoice.enrolling {self.emit("response",["text":"Your voice profile is ready, Fardeen. Speak for at least three seconds per command so I can compare your voice. Mac actions also require Touch ID."])}
                } else if accepted {self.log("Voice matched Fardeen's profile",tone:"success");self.execute(text)}
                else {self.emit("transcript",["text":"","final":false]);self.emit("error",["message":"This voice did not match Fardeen's profile. The request was not sent to the assistant. Try a longer sentence in a quiet room."]);self.log("Unmatched voice rejected",tone:"warning")}
            case .failure(let error):self.emit("error",["message":error.localizedDescription]);self.log("Voice verification needs attention",tone:"warning")
            }
        }
    }
    private func log(_ message:String,tone:String="default") {emit("activity",["message":message,"tone":tone])}
    private func emit(_ type:String,_ payload:[String:Any]) {
        guard isReady else{return}
        var event=payload;event["type"]=type
        webView.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('jarvis:native', {detail: event}));",arguments:["event":event],in:nil,in:.page,completionHandler:nil)
    }
}

let application=NSApplication.shared
application.setActivationPolicy(.regular)
let delegate=AppDelegate()
application.delegate=delegate
application.run()
