import Foundation
import Speech
import AVFoundation
import Combine

final class SpeechTranscriber: NSObject, ObservableObject {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.2
    private let maxUtteranceDuration: TimeInterval = 15
    private var utteranceStartDate: Date?

    private var lastCommittedText: String = ""
    private var lastPartial: String = ""

    private weak var appState: AppState?

    // Prevent overlapping restarts
    private var isRestarting = false

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    // MARK: - Public API
    func start() {
        requestMicrophoneAndSpeechPermissions { [weak self] granted in
            guard let self = self else { return }
            guard granted else {
                print("Permissions not granted for mic and/or speech recognition.")
                return
            }
            DispatchQueue.main.async {
                self.startRecording()
            }
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = nil

            if self.audioEngine.isRunning {
                self.audioEngine.stop()
            }
            self.audioEngine.inputNode.removeTap(onBus: 0)

            self.task?.cancel()
            self.task = nil
            self.request = nil
        }
    }

    deinit {
        stop()
    }

    // MARK: - Recording Pipeline
    private func startRecording() {
        assert(Thread.isMainThread)

        stop() // ensure clean state

        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = false
        req.shouldReportPartialResults = true
        self.request = req

        // Reset state
        lastCommittedText = ""
        lastPartial = ""
        appStateSetCurrentUtterance("")
        utteranceStartDate = Date()

        // Start recognition task
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let text = result.bestTranscription.formattedString
                self.handlePartial(text: text, isFinal: result.isFinal)
            }

            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.restartRecognition()
                }
            }
        }

        // Install Audio Engine Tap
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self, let req = self.request else { return }
            req.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine couldn't start: \(error)")
        }
    }

    private func restartRecognition() {
        DispatchQueue.main.async {
            guard !self.isRestarting else { return }
            self.isRestarting = true
            self.stop()
            self.startRecording()
            self.isRestarting = false
        }
    }

    // MARK: - Partial & Commit Logic
    private func handlePartial(text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            guard self.appState != nil else { return }

            if text != self.lastPartial {
                self.lastPartial = text
                self.appStateSetCurrentUtterance(text)
            }

            self.resetSilenceTimer()

            if let start = self.utteranceStartDate,
               Date().timeIntervalSince(start) > self.maxUtteranceDuration {
                self.commitUtterance()
                return
            }

            if isFinal {
                self.commitUtterance()
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.commitUtterance()
        }
        if let timer = silenceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func commitUtterance() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        guard let appState = appState else { return }

        let chunk = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !chunk.isEmpty else {
            lastPartial = ""
            appStateSetCurrentUtterance("")
            utteranceStartDate = Date()
            return
        }

        if chunk == lastCommittedText {
            return
        }

        lastCommittedText = chunk
        lastPartial = ""
        appStateSetCurrentUtterance("")

        appState.appendChunkAndSend(chunk)

        utteranceStartDate = Date()
    }

    // MARK: - Permissions (macOS)
    private func requestMicrophoneAndSpeechPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechAllowed = (speechStatus == .authorized)

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                DispatchQueue.main.async { completion(speechAllowed) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                    DispatchQueue.main.async { completion(speechAllowed && micGranted) }
                }
            case .denied, .restricted:
                DispatchQueue.main.async { completion(false) }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - AppState thread-safe setter
    private func appStateSetCurrentUtterance(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.appState?.currentUtterance = text
        }
    }
}
