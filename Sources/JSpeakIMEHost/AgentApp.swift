import AppKit
import AVFoundation
@preconcurrency import ApplicationServices

final class AgentAppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var statusItem: NSStatusItem?
    private var isRecording = false
    private var fnDown = false
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // Capture focus at start/stop to avoid inserting into the wrong app when
    // the user clicks the menubar / switches focus during transcription.
    private var startTarget: AXUIElement?
    private var startPID: pid_t?

    private let audio = AudioCapture()
    private let injector = TextInjector()
    private let transcriber = SpeechTranscriber()

    // Mode 1 (fastest): no partial transcription, no floating caption.
    private let asrQueue = DispatchQueue(label: "jspeak.asr.serial", qos: .userInitiated)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        NSLog("JSpeakAgent: started")
        requestPermissionsOnLaunch()
        checkPythonAvailability()
        transcriber.warmUp()
        startHotkeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopHotkeyMonitor()
    }

    @MainActor
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "JSpeak"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Dictation (Fn)", action: #selector(toggleMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Permissions…", action: #selector(openPermissionsHelp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Prompt…", action: #selector(openPromptFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @MainActor
    @objc private func openPermissionsHelp() {
        requestPermissionsOnLaunch(showAlerts: true)
    }

    @MainActor
    @objc private func toggleMenu() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    @MainActor
    @objc private func openPromptFile() {
        guard let url = SpeechTranscriber.ensurePromptFileExists() else {
            showAlert(title: "无法打开词库", message: "创建/打开 prompt.txt 失败。", openURL: nil)
            return
        }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startHotkeyMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: { [weak self] event in
            guard let self else { return }
            let eventType = event.type
            let flags = event.modifierFlags
            let keyCode = event.keyCode
            Task { @MainActor in
                if eventType == .flagsChanged { self.handleFlagsChanged(flags: flags) }
                if eventType == .keyDown { self.handleKeyDown(keyCode: keyCode) }
            }
        })

        if globalMonitor == nil {
            Task { @MainActor in
                showAlert(
                    title: "需要“输入监控”权限",
                    message: "JSpeak 需要“输入监控 (Input Monitoring)”才能在其他应用里监听 Fn/F6。\n\n请前往：系统设置 → 隐私与安全性 → 输入监控，勾选 JSpeak。",
                    openURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                )
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            let eventType = event.type
            let flags = event.modifierFlags
            let keyCode = event.keyCode
            Task { @MainActor in
                if eventType == .flagsChanged { self.handleFlagsChanged(flags: flags) }
                if eventType == .keyDown { self.handleKeyDown(keyCode: keyCode) }
            }
            return event
        }
    }

    private func stopHotkeyMonitor() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    @MainActor
    private func handleFlagsChanged(flags: NSEvent.ModifierFlags) {
        let hasFn = flags.contains(.function)
        if hasFn && !fnDown {
            fnDown = true
            startRecording()
        } else if !hasFn && fnDown {
            fnDown = false
            stopRecording()
        }
    }

    @MainActor
    private func handleKeyDown(keyCode: UInt16) {
    }

    @MainActor
    private func startRecording() {
        NSLog("JSpeakAgent: startRecording")
        guard !isRecording else { return }

        startTarget = captureFocusedElement()
        startPID = frontmostPID()
        do {
            try audio.start(onChunk: nil)
            isRecording = true
            NSSound.beep()
            updateStatusTitle(recording: true)
        } catch {
            NSLog("JSpeak: failed to start audio: \(error)")
            isRecording = false
            updateStatusTitle(recording: false)
        }
    }

    @MainActor
    private func stopRecording() {
        NSLog("JSpeakAgent: stopRecording")

        var target = captureFocusedElement()
        var pid = frontmostPID()

        // If the frontmost app at stop-time is us (or system UI), fall back
        // to the start-time capture.
        if !AgentAppDelegate.isValidInjectionTarget(pid: pid) {
            target = startTarget
            pid = startPID
        }

        startTarget = nil
        startPID = nil

        guard isRecording else { return }
        isRecording = false
        NSSound.beep()
        updateStatusTitle(recording: false)

        let pcm = audio.stop()

        statusItem?.button?.title = "JSpeak …"

        asrQueue.async { [injector] in
            do {
                NSLog("JSpeakAgent: transcribing...")
                let result = try self.transcriber.transcribePCM16(pcmData: pcm, mixed: true)
                let actions = result["actions"] as? [[String: Any]] ?? []
                NSLog("JSpeakAgent: actions count=\(actions.count)")

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let pid, AgentAppDelegate.isValidInjectionTarget(pid: pid) {
                        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    }
                    let statusItem = self.statusItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        injector.applyActions(actions, target: target)
                        statusItem?.button?.title = "JSpeak"
                    }
                }
            } catch {
                NSLog("JSpeak: transcription failed: \(error)")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateStatusTitle(recording: false)
                    self.statusItem?.button?.title = "JSpeak !"
                    self.showAlert(
                        title: "转写失败",
                        message: "\(error.localizedDescription)\n\n如果是首次运行，可能正在创建 Python 环境/安装依赖，请稍等后再试。\n\n如果一直失败：请确认已安装 python3，或设置环境变量 JSPEAK_PYTHON 指向可用的 python。",
                        openURL: nil
                    )
                }
            }
        }
    }

    private func requestPermissionsOnLaunch(showAlerts: Bool = false) {
        // Accessibility (required for AX text injection and CGEvent paste fallback)
        let axOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let axTrusted = AXIsProcessTrustedWithOptions(axOptions)
        if showAlerts && !axTrusted {
            showAlert(
                title: "需要“辅助功能”权限",
                message: "JSpeak 需要“辅助功能 (Accessibility)”才能把识别结果输入到任何应用。\n\n请前往：系统设置 → 隐私与安全性 → 辅助功能，勾选 JSpeak。",
                openURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            )
        }

        // Microphone
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.showAlert(
                            title: "需要“麦克风”权限",
                            message: "JSpeak 需要“麦克风”才能录音转写。\n\n请前往：系统设置 → 隐私与安全性 → 麦克风，勾选 JSpeak。",
                            openURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                        )
                    }
                }
            }
        case .denied, .restricted:
            if showAlerts {
                showAlert(
                    title: "需要“麦克风”权限",
                    message: "JSpeak 需要“麦克风”才能录音转写。\n\n请前往：系统设置 → 隐私与安全性 → 麦克风，勾选 JSpeak。",
                    openURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                )
            }
        case .authorized:
            break
        @unknown default:
            break
        }
    }

    private func checkPythonAvailability() {
        // Fast upfront check so double-click users get a clear actionable error.
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("PythonRuntime/bin/python3").path
            if FileManager.default.fileExists(atPath: bundled) {
                return
            }
        }

        if let env = ProcessInfo.processInfo.environment["JSPEAK_PYTHON"], !env.isEmpty {
            return
        }

        let candidates = [
            "/opt/homebrew/opt/python@3.14/bin/python3.14",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3",
        ]
        if candidates.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            return
        }

        showAlert(
            title: "缺少 Python 运行时",
            message: "JSpeak 需要 Python 才能运行本地转写服务。\n\n解决方式：\n1) 安装 python3 (Homebrew 或官方安装包)，或\n2) 设置环境变量 JSPEAK_PYTHON 指向 python3，或\n3) 使用打包版（内置 PythonRuntime）。",
            openURL: nil
        )
    }

    private func showAlert(title: String, message: String, openURL: URL?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            if openURL != nil {
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后")
            } else {
                alert.addButton(withTitle: "好")
            }

            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn, let openURL {
                NSWorkspace.shared.open(openURL)
            }
        }
    }

    private func captureFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        if err != .success { return nil }
        guard let focused else { return nil }
        if CFGetTypeID(focused) != AXUIElementGetTypeID() {
            return nil
        }
        return unsafeDowncast(focused, to: AXUIElement.self)
    }

    private func frontmostPID() -> pid_t? {
        return NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private static func isValidInjectionTarget(pid: pid_t?) -> Bool {
        guard let pid else { return false }

        // Never treat ourselves as the injection target.
        if pid == ProcessInfo.processInfo.processIdentifier {
            return false
        }

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }

        // Avoid system UI processes that can become frontmost when interacting with the menubar.
        let badBundleIDs: Set<String> = [
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
        ]
        if let bid = app.bundleIdentifier, badBundleIDs.contains(bid) {
            return false
        }

        return true
    }

    private func updateStatusTitle(recording: Bool) {
        statusItem?.button?.title = recording ? "JSpeak ●" : "JSpeak"
    }
}
