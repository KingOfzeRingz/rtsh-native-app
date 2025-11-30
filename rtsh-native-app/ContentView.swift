import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var transcriberHolder = TranscriberHolder()

    var body: some View {
        Group {
            if appState.isRecording {
                ActiveMeetingView(transcriberHolder: transcriberHolder)
            } else {
                StartView(transcriberHolder: transcriberHolder)
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            // Ensure backend is connected
            appState.backendClient.connect(appState: appState)
        }
    }
}

// MARK: - Start View
struct StartView: View {
    @ObservedObject var transcriberHolder: TranscriberHolder
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            Text("Meeting Assistant")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Ready to transcribe your meeting.")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button(action: {
                transcriberHolder.start(appState: appState)
            }) {
                Text("Start Meeting")
                    .font(.headline)
                    .padding()
                    .frame(width: 200)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
}

// MARK: - Active Meeting View
struct ActiveMeetingView: View {
    @ObservedObject var transcriberHolder: TranscriberHolder
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🔴 Recording")
                    .font(.headline)
                    .foregroundColor(.red)
                Spacer()
                Button("Stop") {
                    transcriberHolder.stop(appState: appState)
                }
            }
            .padding(.bottom, 8)

            // Transcript area
            VStack(alignment: .leading, spacing: 4) {
                Text("Microphone Transcript")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(appState.micTranscript + 
                         (appState.currentUtterance.isEmpty ? "" : " " + appState.currentUtterance))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)

                Text("System Audio Transcript")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                ScrollView {
                    Text(appState.systemTranscript + 
                         (appState.systemCurrentUtterance.isEmpty ? "" : " " + appState.systemCurrentUtterance))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
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
            
            // Debug / Status
            HStack {
                Text(appState.debugMessage)
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
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
        appState.isRecording = true
    }
    
    func stop(appState: AppState) {
        transcriber?.stop()
        transcriber = nil
        isRunning = false
        appState.isRecording = false
    }
}
