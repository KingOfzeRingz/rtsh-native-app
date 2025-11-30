import Foundation
import Speech
import AVFoundation
import Combine
import ScreenCaptureKit
import CoreMedia
import Accelerate

// MARK: - Active Speaker Enum

enum ActiveSpeaker {
    case mic
    case system
    case none
}

// This class manages two audio inputs (Mic & System) but feeds only ONE to SFSpeechRecognizer at a time.
final class SpeechTranscriber: NSObject, ObservableObject, SCStreamDelegate {

    // Shared recognizer
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // Single Recognition Task & Request
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Audio Engines / Streams
    private let micEngine = AVAudioEngine()
    private let tapNode = AVAudioMixerNode()
    private var micConverter: AVAudioConverter?

    private var systemStream: SCStream?
    private var systemAudioOutput: SystemAudioOutput?

    // State
    private weak var appState: AppState?

    // Thread-safe active speaker
    private var _activeSpeaker: ActiveSpeaker = .none
    private let speakerLock = NSLock()
    private var activeSpeaker: ActiveSpeaker {
        get { speakerLock.withLock { _activeSpeaker } }
        set { speakerLock.withLock { _activeSpeaker = newValue } }
    }
    
    // Pause state
    private var _isPaused: Bool = false
    private let pauseLock = NSLock()
    private var isPaused: Bool {
        get { pauseLock.withLock { _isPaused } }
        set { pauseLock.withLock { _isPaused = newValue } }
    }

    // Energy Detection
    private var micSpeechLevel: Float = 0
    private var systemSpeechLevel: Float = 0
    private let speechThreshold: Float = 0.01

    private var lastSpeakerUpdate = Date()
    private let speakerHoldTime: TimeInterval = 0.25

    // Utterance Management
    private var lastPartial: String = ""
    private var lastCommittedText: String = ""
    private var utteranceStartDate: Date?
    private let maxUtteranceDuration: TimeInterval = 15
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.2

    // What source the current task is listening to
    private var currentTaskSource: ActiveSpeaker = .none

    // Minimum length before sending to backend (optional heuristic)
    private let minChunkLength = 5

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    // MARK: - Public API

    func start() {
        log("start() called")
        requestAllPermissions { [weak self] granted in
            guard let self = self else { return }
            if !granted { self.log("Warning: Permissions missing.") }

            DispatchQueue.main.async {
                self.appState?.updateOnMain {
                    self.appState?.isRecording = true
                }
                self.startAudioPipelines()
            }
        }
    }

    // Flag to prevent double cleanup
    private var isStopped = false

    func stop() {
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.cleanup()
            }
        }
    }
    
    func pause() {
        log("pause() called - cancelling task")
        isPaused = true
        
        // Flush any pending text
        commitUtterance()
        
        // Cancel the current recognition task to stop listening completely
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        DispatchQueue.main.async {
            self.appState?.updateOnMain {
                self.appState?.isPaused = true
            }
        }
    }
    
    func resume() {
        log("resume() called - restarting task")
        isPaused = false
        
        // Restart the recognition task
        switchRecognitionSource(activeSpeaker)
        
        DispatchQueue.main.async {
            self.appState?.updateOnMain {
                self.appState?.isPaused = false
            }
        }
    }

    private func cleanup() {
        if isStopped { return }
        isStopped = true
        
        log("stop() called")
        
        appState?.updateOnMain {
            self.appState?.isRecording = false
        }

        // Stop Mic
        if micEngine.isRunning { micEngine.stop() }
        micEngine.inputNode.removeTap(onBus: 0)

        // Stop System
        systemStream?.stopCapture(completionHandler: { _ in })
        systemStream = nil

        // Cancel Task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    deinit {
        // If we are being deallocated, we should try to cleanup if not already done.
        // However, we cannot dispatch async safely.
        // If we are on main thread, we can cleanup.
        // If not, we rely on property deinitialization and the fact that we likely called stop() explicitly.
        if Thread.isMainThread {
            cleanup()
        }
    }

    // MARK: - Permissions

    private func requestAllPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechAllowed = (speechStatus == .authorized)

            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                DispatchQueue.main.async { completion(speechAllowed) }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                    DispatchQueue.main.async { completion(speechAllowed && micGranted) }
                }
            default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Audio Pipelines Setup

    private func startAudioPipelines() {
        // 1. Start Mic Engine (always running to detect energy)
        startMicEngine()

        // 2. Start System Stream
        startSystemStream()

        // 3. Start initial recognition for Mic
        activeSpeaker = .mic
        switchRecognitionSource(.mic)
    }

    // MARK: - RMS Calculation

    private func audioRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        vDSP_svesq(data, 1, &sum, vDSP_Length(count))
        return sqrt(sum / Float(count))
    }

    // MARK: - Active Speaker Logic

    private func updateActiveSpeaker() {
        let now = Date()

        let micSpeaking = micSpeechLevel > speechThreshold
        let systemSpeaking = systemSpeechLevel > speechThreshold

        var newSpeaker: ActiveSpeaker = activeSpeaker

        if micSpeaking && !systemSpeaking {
            newSpeaker = .mic
        } else if systemSpeaking && !micSpeaking {
            newSpeaker = .system
        } else if systemSpeaking && micSpeaking {
            newSpeaker = .system // system has priority
        }

        if newSpeaker != activeSpeaker && newSpeaker != .none {
            if now.timeIntervalSince(lastSpeakerUpdate) > speakerHoldTime {
                activeSpeaker = newSpeaker
                lastSpeakerUpdate = now

                print("🎙️ Switching speaker to: \(newSpeaker)")
                DispatchQueue.main.async {
                    self.switchRecognitionSource(newSpeaker)
                }
            }
        }
    }

    // MARK: - Switching Logic (Main Thread)

    private func switchRecognitionSource(_ speaker: ActiveSpeaker) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.switchRecognitionSource(speaker) }
            return
        }

        // Commit any existing utterance from previous source
        commitUtterance()

        // Cancel old task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // New request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = false
        req.shouldReportPartialResults = true

        recognitionRequest = req
        currentTaskSource = speaker
        lastPartial = ""
        lastCommittedText = ""
        utteranceStartDate = Date()

        guard let recognizer = recognizer, recognizer.isAvailable else { return }

        print("[SpeechTranscriber] Starting Task for: \(speaker)")
        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                self.handlePartial(text: result.bestTranscription.formattedString,
                                   isFinal: result.isFinal)
            }

            if let error = error {
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" &&
                    (nsError.code == 1110 || nsError.code == 203) {
                    // silence / timeout, do not spam restarts
                    return
                }
                print("Task Error (\(speaker)): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Mic Engine

    private func startMicEngine() {
        if !micEngine.isRunning {
            let inputNode = micEngine.inputNode
            let hardwareFormat = inputNode.outputFormat(forBus: 0)

            micEngine.attach(tapNode)
            micEngine.connect(inputNode, to: tapNode, format: hardwareFormat)
            micEngine.connect(tapNode, to: micEngine.mainMixerNode, format: hardwareFormat)
            micEngine.mainMixerNode.outputVolume = 0

            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )!
            self.micConverter = AVAudioConverter(from: hardwareFormat, to: targetFormat)

            tapNode.removeTap(onBus: 0)
            tapNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                if self.isPaused { return }

                guard let converted = self.convertBuffer(buffer, using: self.micConverter) else { return }

                let rms = self.audioRMS(converted)
                self.micSpeechLevel = rms
                self.updateActiveSpeaker()

                if self.activeSpeaker == .mic, let req = self.recognitionRequest {
                    req.append(converted)
                }
            }

            do {
                micEngine.prepare()
                try micEngine.start()
                log("Mic Engine Started")
            } catch {
                log("Mic Engine Failed: \(error)")
            }
        }
    }

    // MARK: - System Stream

    private func startSystemStream() {
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else { return }

                let streamConfig = SCStreamConfiguration()
                streamConfig.width = 100
                streamConfig.height = 100
                streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                streamConfig.capturesAudio = true
                streamConfig.excludesCurrentProcessAudio = true
                if #available(macOS 13.0, *) {
                    streamConfig.sampleRate = 48000
                    streamConfig.channelCount = 1
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
                self.systemStream = stream

                let output = SystemAudioOutput { [weak self] sampleBuffer in
                    self?.handleSystemSampleBuffer(sampleBuffer)
                }
                self.systemAudioOutput = output

                let audioQueue = DispatchQueue(label: "com.asklio.systemaudio",
                                               qos: .userInteractive)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
                try await stream.startCapture()
                self.log("System Stream Started")
            } catch {
                self.log("System Stream Error: \(error)")
            }
        }
    }

    private func handleSystemSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if isPaused { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let inputFormat = AVAudioFormat(streamDescription: asbd) else { return }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        if let pcmBuffer = convertSampleBuffer(sampleBuffer, from: inputFormat, to: targetFormat) {
            let rms = audioRMS(pcmBuffer)
            self.systemSpeechLevel = rms
            self.updateActiveSpeaker()

            if self.activeSpeaker == .system, let req = self.recognitionRequest {
                req.append(pcmBuffer)
            }
        }
    }

    // MARK: - Utterance Handling

    private func handlePartial(text: String, isFinal: Bool) {
        DispatchQueue.main.async {
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

    private func commitUtterance() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.commitUtterance() }
            return
        }

        silenceTimer?.invalidate()
        silenceTimer = nil

        let chunk = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else {
            lastPartial = ""
            appStateSetCurrentUtterance("")
            utteranceStartDate = Date()
            return
        }

        // Prevent duplicate sends of same string
        if chunk == lastCommittedText { return }
        lastCommittedText = chunk
        lastPartial = ""

        // Clear live bubble text
        appStateSetCurrentUtterance("")

        // Append to UI transcripts
        appState?.updateOnMain { [weak self] in
            guard let self = self, let appState = self.appState else { return }

            if self.currentTaskSource == .system {
                if !appState.systemTranscript.isEmpty {
                    appState.systemTranscript += " "
                }
                appState.systemTranscript += chunk
            } else {
                if !appState.micTranscript.isEmpty {
                    appState.micTranscript += " "
                }
                appState.micTranscript += chunk
            }
        }

        // Only send sufficiently long chunks
        if chunk.count >= minChunkLength {
            appState?.sendTranscriptChunk(text: chunk, from: currentTaskSource)
        }

        utteranceStartDate = Date()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout,
                                            repeats: false) { [weak self] _ in
            self?.commitUtterance()
        }
        if let timer = silenceTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func appStateSetCurrentUtterance(_ text: String) {
        appState?.updateOnMain { [weak self] in
            guard let self = self, let appState = self.appState else { return }
            if self.currentTaskSource == .system {
                appState.systemCurrentUtterance = text
            } else {
                appState.currentUtterance = text
            }
        }
    }

    // MARK: - Logging

    private func log(_ message: String) {
        print("[SpeechTranscriber] \(message)")
        appState?.updateOnMain { [weak self] in
            self?.appState?.debugMessage = message
        }
    }

    // MARK: - Converters

    private func convertBuffer(_ buffer: AVAudioPCMBuffer,
                               using converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let converter = converter else { return buffer }
        let targetFormat = converter.outputFormat
        let capacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
        )

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: capacity) else { return nil }

        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        return outputBuffer
    }

    private func convertSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                     from srcFormat: AVAudioFormat,
                                     to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let audioBufferList = try? sampleBuffer.audioBufferList() else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let srcPCMBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat,
                                                  frameCapacity: frameCount) else { return nil }
        srcPCMBuffer.frameLength = frameCount

        let abl = audioBufferList.unsafePointer.pointee
        guard let data = abl.mBuffers.mData else { return nil }
        let byteCount = Int(abl.mBuffers.mDataByteSize)

        if srcFormat.commonFormat == .pcmFormatFloat32,
           let dest = srcPCMBuffer.floatChannelData {
            memcpy(dest[0], data, byteCount)
        } else {
            if let dest = srcPCMBuffer.floatChannelData {
                memcpy(dest[0], data,
                       min(byteCount,
                           Int(srcPCMBuffer.frameCapacity) * MemoryLayout<Float>.size))
            }
        }

        if srcFormat == targetFormat { return srcPCMBuffer }

        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else { return nil }
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                               frameCapacity: frameCount) else { return nil }

        var error: NSError?
        var isDone = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if isDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            isDone = true
            return srcPCMBuffer
        }
        converter.convert(to: dstBuffer, error: &error, withInputFrom: inputBlock)
        return dstBuffer
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("SCStream stopped: \(error.localizedDescription)")
    }
}

// MARK: - CMSampleBuffer Helper

private extension CMSampleBuffer {
    struct AudioBufferListWrapper {
        let unsafePointer: UnsafePointer<AudioBufferList>
        let deallocator: () -> Void
    }

    func audioBufferList() throws -> AudioBufferListWrapper {
        var ablSize: Int = 0
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: &ablSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: nil
        )

        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: ablSize)
        var blockBuffer: CMBlockBuffer?
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            self,
            bufferListSizeNeededOut: nil,
            bufferListOut: bufferListPtr,
            bufferListSize: ablSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        return AudioBufferListWrapper(
            unsafePointer: UnsafePointer(bufferListPtr),
            deallocator: { bufferListPtr.deallocate() }
        )
    }
}

// MARK: - ScreenCaptureKit Audio Output

final class SystemAudioOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void
    init(_ handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
        super.init()
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}
