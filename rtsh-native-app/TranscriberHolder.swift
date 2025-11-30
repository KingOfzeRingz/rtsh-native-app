import Foundation
import Combine
import Speech
import AVFoundation

final class TranscriberHolder: ObservableObject {
    @Published var isRunning = false
    private var transcriber: SpeechTranscriber?

    func checkPermissions(appState: AppState) {
        SFSpeechRecognizer.requestAuthorization { status in
            appState.updateOnMain {
                appState.speechPermissionGranted = (status == .authorized)
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            appState.updateOnMain { appState.micPermissionGranted = true }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                appState.updateOnMain { appState.micPermissionGranted = granted }
            }
        default:
            appState.updateOnMain { appState.micPermissionGranted = false }
        }

        // System audio assumed true for now
        appState.updateOnMain { appState.systemAudioPermissionGranted = true }
    }

    func start(appState: AppState) {
        let t = SpeechTranscriber(appState: appState)
        transcriber = t
        t.start()
        isRunning = true
        appState.isRecording = true
    }

    func stop(appState: AppState) {
        transcriber?.stop()
        transcriber = nil
        isRunning = false
        appState.isRecording = false
    }
    
    func pause(appState: AppState) {
        transcriber?.pause()
    }
    
    func resume(appState: AppState) {
        transcriber?.resume()
    }
}
