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
// It uses RMS energy detection to dynamically switch the active source.
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
    
    // Thread-safe active speaker access
    private var _activeSpeaker: ActiveSpeaker = .none
    private let speakerLock = NSLock()
    private var activeSpeaker: ActiveSpeaker {
        get { speakerLock.withLock { _activeSpeaker } }
        set { speakerLock.withLock { _activeSpeaker = newValue } }
    }
    
    // Energy Detection
    private var micSpeechLevel: Float = 0
    private var systemSpeechLevel: Float = 0
    private let speechThreshold: Float = 0.01
    
    private var lastSpeakerUpdate = Date()
    private let speakerHoldTime: TimeInterval = 0.25
    
    // Utterance Management (Main Thread Only)
    private var lastPartial: String = ""
    private var lastCommittedText: String = ""
    private var utteranceStartDate: Date?
    private let maxUtteranceDuration: TimeInterval = 15
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.2
    
    // Track which source the CURRENT task is listening to
    private var currentTaskSource: ActiveSpeaker = .none

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

    func checkPermissions() {
        requestAllPermissions { [weak self] granted in
            guard let self = self else { return }
            self.appState?.updateOnMain {
                self.appState?.speechPermissionGranted = (SFSpeechRecognizer.authorizationStatus() == .authorized)
                self.appState?.micPermissionGranted = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
                self.appState?.systemAudioPermissionGranted = true // Assumed true for now as SCKit doesn't have a simple check without stream
            }
        }
    }

    func stop() {
        log("stop() called")
        DispatchQueue.main.async {
            self.appState?.updateOnMain {
                self.appState?.isRecording = false
            }
            
            // Stop Mic
            if self.micEngine.isRunning { self.micEngine.stop() }
            self.micEngine.inputNode.removeTap(onBus: 0)
            
            // Stop System
            self.systemStream?.stopCapture(completionHandler: { _ in })
            self.systemStream = nil
            
            // Cancel Task
            self.recognitionTask?.cancel()
            self.recognitionTask = nil
            self.recognitionRequest = nil
            
            self.silenceTimer?.invalidate()
            self.silenceTimer = nil
        }
    }
    
    deinit { stop() }

    // MARK: - Audio Pipelines Setup
    private func startAudioPipelines() {
        // 1. Start Mic Engine (Always running to detect energy)
        startMicEngine()
        
        // 2. Start System Stream (Always running to detect energy)
        startSystemStream()
        
        // 3. Start initial recognition
        // We start with .mic as default
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
        // This runs on audio threads, so we need to be careful.
        // We calculate the new state, but dispatch the SWITCH to main.
        
        let now = Date()
        
        let micSpeaking = micSpeechLevel > speechThreshold
        let systemSpeaking = systemSpeechLevel > speechThreshold
        
        var newSpeaker: ActiveSpeaker = .none
        
        if micSpeaking && !systemSpeaking {
            newSpeaker = .mic
        } else if systemSpeaking && !micSpeaking {
            newSpeaker = .system
        } else if systemSpeaking && micSpeaking {
            newSpeaker = .system // Priority to system
        } else {
            // Hold current speaker
            newSpeaker = activeSpeaker
        }
        
        // Debounce / Hold
        if newSpeaker != activeSpeaker && newSpeaker != .none {
             if now.timeIntervalSince(lastSpeakerUpdate) > speakerHoldTime {
                 // Update the atomic property immediately so audio buffers start flowing to the right place?
                 // OR wait for the switch?
                 // If we update `activeSpeaker` here, `req.append` will start appending immediately.
                 // But `recognitionRequest` might still be the OLD one until `switchRecognitionSource` runs on Main.
                 // That's actually fine! We just append to the current request until it's swapped.
                 
                 // However, we want to trigger the switch.
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
        // Ensure we are on main thread for state consistency
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.switchRecognitionSource(speaker) }
            return
        }

        // 1. Commit whatever we have from the OLD task
        commitUtterance()
        
        // 2. Cancel old task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // 3. Create NEW Request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = false
        req.shouldReportPartialResults = true
        
        if speaker == .system {
            req.contextualStrings = ["System Audio"]
        }
        
        self.recognitionRequest = req
        self.currentTaskSource = speaker
        
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        
        // 4. Start NEW Task
        print("[SpeechTranscriber] Starting Task for: \(speaker)")
        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.handlePartial(text: result.bestTranscription.formattedString, isFinal: result.isFinal)
            }
            
            if let error = error {
                 let nsError = error as NSError
                 if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1110 || nsError.code == 203) {
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
            
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
            self.micConverter = AVAudioConverter(from: hardwareFormat, to: targetFormat)
            
            tapNode.removeTap(onBus: 0)
            tapNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                // 1. Convert
                guard let converted = self.convertBuffer(buffer, using: self.micConverter) else { return }
                
                // 2. Detect Energy
                let rms = self.audioRMS(converted)
                self.micSpeechLevel = rms
                self.updateActiveSpeaker()
                
                // 3. Append IF active
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
                
                let audioQueue = DispatchQueue(label: "com.rtsh.audio", qos: .userInteractive)
                try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
                try await stream.startCapture()
                self.log("System Stream Started")
            } catch {
                self.log("System Stream Error: \(error)")
            }
        }
    }
    
    private func handleSystemSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let inputFormat = AVAudioFormat(streamDescription: asbd) else { return }
        
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        
        if let pcmBuffer = convertSampleBuffer(sampleBuffer, from: inputFormat, to: targetFormat) {
            
            // 1. Detect Energy
            let rms = audioRMS(pcmBuffer)
            self.systemSpeechLevel = rms
            self.updateActiveSpeaker()
            
            // 2. Append IF active
            if self.activeSpeaker == .system, let req = self.recognitionRequest {
                req.append(pcmBuffer)
            }
        }
    }
    
    // MARK: - Utterance Handling (Main Thread)
    private func handlePartial(text: String, isFinal: Bool) {
        DispatchQueue.main.async {
            if text != self.lastPartial {
                self.lastPartial = text
                self.appStateSetCurrentUtterance(text)
            }
            
            self.resetSilenceTimer()
            
            if let start = self.utteranceStartDate, Date().timeIntervalSince(start) > self.maxUtteranceDuration {
                self.commitUtterance()
                return
            }
            
            if isFinal {
                self.commitUtterance()
            }
        }
    }
    
    private func commitUtterance() {
        // Ensure Main Thread
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
        
        if chunk == lastCommittedText { return }
        
        print("[SpeechTranscriber] Committing (\(currentTaskSource)): '\(chunk)'")
        
        lastCommittedText = chunk
        lastPartial = ""
        appStateSetCurrentUtterance("")
        
        // Send to AppState with correct source
        let sourceKey = (currentTaskSource == .system) ? "system_audio" : "mic_mix"
        
        // AppState method is now thread-safe, but we are on main anyway
        appState?.appendChunkAndSend(chunk, source: sourceKey)
        
        utteranceStartDate = Date()
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.commitUtterance()
        }
    }
    
    private func appStateSetCurrentUtterance(_ text: String) {
        // Use updateOnMain for safety
        appState?.updateOnMain { [weak self] in
            guard let self = self else { return }
            if self.currentTaskSource == .system {
                self.appState?.systemCurrentUtterance = text
            } else {
                self.appState?.currentUtterance = text
            }
        }
    }

    // MARK: - Helpers & Permissions
    private func log(_ message: String) {
        print("[SpeechTranscriber] \(message)")
        appState?.updateOnMain { [weak self] in
            self?.appState?.debugMessage = message
        }
    }
    
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
    
    // MARK: - Converters
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter?) -> AVAudioPCMBuffer? {
        guard let converter = converter else { return buffer }
        let targetFormat = converter.outputFormat
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        return outputBuffer
    }
    
    private func convertSampleBuffer(_ sampleBuffer: CMSampleBuffer, from srcFormat: AVAudioFormat, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let audioBufferList = try? sampleBuffer.audioBufferList() else { return nil }
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let srcPCMBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: frameCount) else { return nil }
        srcPCMBuffer.frameLength = frameCount
        let abl = audioBufferList.unsafePointer.pointee
        guard let data = abl.mBuffers.mData else { return nil }
        let byteCount = Int(abl.mBuffers.mDataByteSize)
        if srcFormat.commonFormat == .pcmFormatFloat32, let dest = srcPCMBuffer.floatChannelData {
            memcpy(dest[0], data, byteCount)
        } else {
             if let dest = srcPCMBuffer.floatChannelData {
                 memcpy(dest[0], data, min(byteCount, Int(srcPCMBuffer.frameCapacity) * MemoryLayout<Float>.size))
             }
        }
        if srcFormat == targetFormat { return srcPCMBuffer }
        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else { return nil }
        guard let dstBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return nil }
        var error: NSError?
        var isDone = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if isDone { outStatus.pointee = .noDataNow; return nil }
            outStatus.pointee = .haveData; isDone = true; return srcPCMBuffer
        }
        converter.convert(to: dstBuffer, error: &error, withInputFrom: inputBlock)
        return dstBuffer
    }
    
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
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(self, bufferListSizeNeededOut: &ablSize, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: nil)
        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: ablSize)
        var blockBuffer: CMBlockBuffer?
        _ = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(self, bufferListSizeNeededOut: nil, bufferListOut: bufferListPtr, bufferListSize: ablSize, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)
        return AudioBufferListWrapper(unsafePointer: UnsafePointer(bufferListPtr)) { bufferListPtr.deallocate() }
    }
}

final class SystemAudioOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void
    init(_ handler: @escaping (CMSampleBuffer) -> Void) { self.handler = handler; super.init() }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}
