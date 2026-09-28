import AVFoundation
import Foundation
import Speech

/// Streams microphone audio into Apple's on-device speech recognizer.
/// Partial (volatile) results are pushed into the model instantly; when the
/// recognizer finalizes a segment (or speech pauses), the text is handed to
/// the Cleaner and committed as colorized tokens.
final class Transcriber {
    private let model: TranscriptModel
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var generation = 0
    private(set) var running = false

    init(model: TranscriptModel) {
        self.model = model
    }

    func start() {
        guard !running else { return }
        running = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        prepareRecording(format: format)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
            do {
                try self.recordingFile?.write(from: buffer)
            } catch {
                NSLog("LiveFlow: could not save audio for final transcription: \(error)")
                self.recordingFile = nil
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("LiveFlow: audio engine failed to start: \(error)")
            running = false
            input.removeTap(onBus: 0)
            recordingFile = nil
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            recordingURL = nil
            return
        }

        startTask()
        model.isListening = true
    }

    func stop(completion: @escaping () -> Void = {}) {
        guard running else {
            completion()
            return
        }
        running = false
        generation += 1
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        commitPending()
        model.isListening = false

        // Closing the file before handing it to SpeechAnalyzer guarantees that
        // its header and final audio packet are complete.
        recordingFile = nil
        guard let url = recordingURL else {
            completion()
            return
        }
        recordingURL = nil

        guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable else {
            try? FileManager.default.removeItem(at: url)
            completion()
            return
        }

        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let finalText = try await AccurateFileTranscriber.transcribe(url: url)
                await MainActor.run {
                    if !finalText.isEmpty {
                        self.model.replaceTranscript(with: finalText)
                    }
                    completion()
                }
            } catch {
                NSLog("LiveFlow: high-accuracy final transcription failed: \(error)")
                await MainActor.run { completion() }
            }
        }
    }

    // MARK: - Recognition task lifecycle

    private func startTask() {
        guard let recognizer, recognizer.isAvailable else {
            NSLog("LiveFlow: speech recognizer unavailable")
            return
        }
        generation += 1
        let gen = generation

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.taskHint = .dictation
        req.contextualStrings = Vocabulary.phrases
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        req.addsPunctuation = true
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handle(result: result, error: error, gen: gen)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, gen: Int) {
        guard running, gen == generation else { return }
        if let result {
            model.volatileText = result.bestTranscription.formattedString
            if result.isFinal {
                commitAndRestart()
            }
        } else if error != nil {
            // "No speech detected" and friends — commit whatever we have and keep going.
            commitAndRestart()
        }
    }

    private func commitAndRestart() {
        guard running else { return }
        commitPending()
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        startTask()
    }

    private func commitPending() {
        let text = model.volatileText
        model.volatileText = ""
        guard !text.isEmpty else { return }
        model.commitRaw(text)
    }

    private func prepareRecording(format: AVAudioFormat) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveFlow-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        do {
            recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingURL = url
        } catch {
            NSLog("LiveFlow: could not create temporary audio recording: \(error)")
            recordingFile = nil
            recordingURL = nil
        }
    }
}

/// Re-runs the complete utterance through Apple's current-generation on-device
/// model after the Fn key is released. The legacy recognizer remains useful for
/// the instant overlay, while this pass supplies the more accurate pasted text.
@available(macOS 26.0, *)
private enum AccurateFileTranscriber {
    static func transcribe(url: URL) async throws -> String {
        let requestedLocale = Locale(identifier: "en-US")
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)
            ?? requestedLocale
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        if let installation = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installation.downloadAndInstall()
        }

        let options = SpeechAnalyzer.Options(priority: .userInitiated,
                                             modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: options)
        let context = AnalysisContext()
        context.contextualStrings[.general] = Vocabulary.phrases
        try? await analyzer.setContext(context)

        let resultTask = Task<String, Error> {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }

        let file = try AVAudioFile(forReading: url)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await resultTask.value
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
