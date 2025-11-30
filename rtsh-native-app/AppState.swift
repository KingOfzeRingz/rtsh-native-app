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

struct Company: Identifiable, Decodable, Hashable {
    let firmen_id: Int
    let name: String
    let logo: String
    
    var id: Int { firmen_id }
}

// MARK: - AppState

final class AppState: ObservableObject {

    // MARK: - Microphone / System Transcripts
    @Published var micTranscript: String = ""
    @Published var currentUtterance: String = ""

    @Published var systemTranscript: String = ""
    @Published var systemCurrentUtterance: String = ""

    // MARK: - App Status & Permissions
    @Published var isRecording: Bool = false
    @Published var debugMessage: String = "Initializing..."

    @Published var speechPermissionGranted: Bool = false
    @Published var micPermissionGranted: Bool = false
    @Published var systemAudioPermissionGranted: Bool = false

    // MARK: - Conversation / Company Metadata
    @Published var convId: Int = 123       // Dynamic per session
    @Published var companyId: Int = 1      // Derived from selectedCompany
    
    @Published var companies: [Company] = []
    @Published var selectedCompany: Company? {
        didSet {
            if let company = selectedCompany {
                companyId = company.firmen_id
            }
        }
    }

    // MARK: - Events
    @Published var events: [AssistantEvent] = []

    // MARK: - Backend Interaction
    let backendClient = BackendClient()
    
    @Published var isStarting: Bool = false
    @Published var isPaused: Bool = false

    func startNewConversation(completion: @escaping () -> Void) {
        isStarting = true
        backendClient.createConversation(companyId: companyId) { [weak self] newId in
            self?.updateOnMain {
                if let newId = newId {
                    self?.convId = newId
                    print("Created new Conversation ID: \(newId)")
                } else {
                    print("Failed to create conversation, using fallback/random")
                    self?.convId = Int.random(in: 100000...999999)
                }
                self?.isStarting = false
                completion()
            }
        }
    }

    // Thread-safe helper for publishing changes
    func updateOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async {
                update()
            }
        }
    }

    // MARK: - Sending Transcript Chunks to Backend

    func sendTranscriptChunk(text: String, from speaker: ActiveSpeaker) {
        let author: String = (speaker == .system ? "vendor" : "user")

        let payload: [String: Any] = [
            "conv_id": convId,
            "company_id": companyId,
            "author": author,
            "text": text
        ]

        backendClient.send(payload)
    }

    // MARK: - Backend events → UI

    func handleBackendMessage(_ event: AssistantEvent) {
        updateOnMain {
            self.events.insert(event, at: 0)
        }
    }
}
