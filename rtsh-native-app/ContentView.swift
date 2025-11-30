import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var transcriberHolder = TranscriberHolder()

    var body: some View {
        VStack(spacing: 8) {
            Text("Meeting Assistant")
                .font(.headline)

            // Transcript area
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcript")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(appState.micTranscript + 
                         (appState.currentUtterance.isEmpty ? "" : " " + appState.currentUtterance))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
            }

            // Events list
            VStack(alignment: .leading, spacing: 4) {
                Text("Assistant Events")
                    .font(.caption)
                    .foregroundColor(.secondary)

                List(appState.events) { event in
                    HStack {
                        Circle()
                            .fill(color(for: event.type))
                            .frame(width: 8, height: 8)
                        Text(event.text)
                    }
                }
                .frame(minHeight: 150)
            }
        }
        .padding()
        .onAppear {
            appState.backendClient.connect(appState: appState)
            transcriberHolder.start(appState: appState)
        }
    }

    private func color(for type: EventType) -> Color {
        switch type {
        case .warning: return .red
        case .alert:   return .orange
        case .success: return .green
        case .question: return .blue
        }
    }
}

final class TranscriberHolder: ObservableObject {
    @Published var isRunning = false
    private var transcriber: SpeechTranscriber?

    func start(appState: AppState) {
        let t = SpeechTranscriber(appState: appState)
        transcriber = t
        t.start()
        isRunning = true
    }
}
