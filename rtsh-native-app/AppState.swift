import Foundation
import Combine

enum EventType: String {
    case question, warning, alert, success
}

struct AssistantEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let text: String
}

final class AppState: ObservableObject {
    @Published var micTranscript: String = ""
    @Published var currentUtterance: String = ""
    @Published var events: [AssistantEvent] = []

    let backendClient = BackendClient()

    func appendChunkAndSend(_ chunk: String) {
        guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        micTranscript += (micTranscript.isEmpty ? "" : " ") + chunk

        backendClient.sendText(
            convId: "1",
            source: "mic_mix",
            text: chunk
        )
    }

    func handleBackendMessage(_ event: AssistantEvent) {
        events.insert(event, at: 0)
    }
}
