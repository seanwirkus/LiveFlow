import AppKit
import ApplicationServices
import AVFoundation
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    let model = TranscriptModel()
    private var transcriber: Transcriber!
    private var overlay: OverlayPanel!
    private var statusItem: NSStatusItem!
    private var fnMonitor: FnKeyMonitor!
    private var toggleItem: NSMenuItem!
    private var isFinalizing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        transcriber = Transcriber(model: model)
        overlay = OverlayPanel(model: model)
        setupStatusItem()
        fnMonitor = FnKeyMonitor(
            onPress: { [weak self] in self?.startListening() },
            onRelease: { [weak self] in self?.stopListening() }
        )
        Vocabulary.ensureFileExists()
        requestPermissions()
    }

    // MARK: - Listening

    @objc func toggleListening() {
        if model.isListening { stopListening() } else { startListening() }
    }

    private func startListening() {
        guard !model.isListening, !isFinalizing else { return }
        model.reset()
        transcriber.start()
        guard model.isListening else { return }
        overlay.show()
        toggleItem.title = "Stop Dictation"
        statusItem.button?.image = symbol("record.circle.fill")
    }

    private func stopListening() {
        guard model.isListening else { return }
        isFinalizing = true
        transcriber.stop { [weak self] in
            self?.finishDictation()
        }
        overlay.hide()
        toggleItem.title = "Start Dictation  (or hold Fn)"
        statusItem.button?.image = symbol("waveform")
    }

    private func finishDictation() {
        isFinalizing = false
        let text = model.fullTranscript
        guard !text.isEmpty else { return }
        History.append(text)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if AXIsProcessTrusted() {
            pasteIntoFrontApp()
        }
    }

    private func pasteIntoFrontApp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .hidSystemState)
            let vDown = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            let vUp = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            vDown?.flags = .maskCommand
            vUp?.flags = .maskCommand
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = symbol("waveform")

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Dictation  (or hold Fn)",
                                action: #selector(toggleListening), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let copyItem = NSMenuItem(title: "Copy Last Transcript",
                                  action: #selector(copyTranscript), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let historyItem = NSMenuItem(title: "Open Transcript History",
                                     action: #selector(openHistory), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let vocabularyItem = NSMenuItem(title: "Open Custom Vocabulary",
                                        action: #selector(openVocabulary), keyEquivalent: "")
        vocabularyItem.target = self
        menu.addItem(vocabularyItem)

        let sizeItem = NSMenuItem(title: "Text Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in TextSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(setTextSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = (size == model.textSize) ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        let axItem = NSMenuItem(title: "Enable Fn Key + Auto-Paste (Accessibility)…",
                                action: #selector(promptAccessibility), keyEquivalent: "")
        axItem.target = self
        menu.addItem(axItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LiveFlow",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func copyTranscript() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(model.fullTranscript, forType: .string)
    }

    @objc private func openHistory() {
        NSWorkspace.shared.open(History.fileURL)
    }

    @objc private func openVocabulary() {
        Vocabulary.ensureFileExists()
        NSWorkspace.shared.open(Vocabulary.fileURL)
    }

    @objc private func setTextSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = TextSize(rawValue: raw) else { return }
        model.textSize = size
        sender.menu?.items.forEach { $0.state = ($0 === sender) ? .on : .off }
    }

    @objc private func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    private func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "LiveFlow")
        img?.isTemplate = true
        return img
    }

    // MARK: - Permissions

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            NSLog("LiveFlow: speech auth = \(status.rawValue)")
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            NSLog("LiveFlow: mic access = \(granted)")
        }
        // Fn-key monitoring (and auto-paste) need Accessibility; prompt on first launch.
        if !AXIsProcessTrusted() {
            promptAccessibility()
        }
    }
}
