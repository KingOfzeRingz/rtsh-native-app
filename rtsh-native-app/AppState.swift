import Foundation
import Combine

// MARK: - Event Models
enum EventType: String {
    case question, warning, alert, success
}

struct AssistantEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let text: String
}

// MARK: - AppState
final class AppState: ObservableObject {
    
    // MARK: - Microphone Transcripts
    @Published var micTranscript: String = ""
    @Published var currentUtterance: String = "" // Used by Mic pipeline

    // MARK: - System Audio Transcripts (Fixes 'Value has no member...')
    @Published var systemTranscript: String = ""
    @Published var systemCurrentUtterance: String = "" // <--- Fixes the error
    
    // MARK: - App Status & Permissions
    @Published var isRecording: Bool = false
    @Published var debugMessage: String = "Initializing..."
    
    @Published var speechPermissionGranted: Bool = false
    @Published var micPermissionGranted: Bool = false
    @Published var systemAudioPermissionGranted: Bool = false

    // MARK: - Events
    @Published var events: [AssistantEvent] = []

    // MARK: - Backend Interaction
    let backendClient = BackendClient()

    // Unified method to send text from any source
    func appendChunkAndSend(_ text: String, source: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Update UI based on source (Thread-Safe)
        updateOnMain {
            if source == "mic_mix" {
                self.micTranscript += (self.micTranscript.isEmpty ? "" : " ") + text
            } else if source == "system_audio" {
                self.systemTranscript += (self.systemTranscript.isEmpty ? "" : " ") + text
            }
        }

        // Send to Backend
        backendClient.sendText(
            convId: "1",
            source: source,
            text: text
        )
    }

    func handleBackendMessage(_ event: AssistantEvent) {
        updateOnMain {
            self.events.insert(event, at: 0)
        }
    }
}

extension AppState {
    func updateOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }
}
