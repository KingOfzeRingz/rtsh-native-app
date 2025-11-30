import SwiftUI
import Combine
import Speech
import AVFoundation

// MARK: - Main Content View
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
        .frame(width: 380, height: 650) // Fixed size to match phone-like aspect ratio in screenshot
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.backendClient.connect(appState: appState)
            // Trigger a permission check on load so checkmarks update
            transcriberHolder.checkPermissions(appState: appState)
        }
    }
}

// MARK: - Start View (Matches Screenshot)
struct StartView: View {
    @ObservedObject var transcriberHolder: TranscriberHolder
    @EnvironmentObject var appState: AppState
    
    // Custom color for the light gray background seen in the image
    let backgroundColor = Color(red: 0.93, green: 0.93, blue: 0.93)
    let cardBackgroundColor = Color.white
    let permissionBoxColor = Color(red: 0.97, green: 0.97, blue: 0.97)

    var body: some View {
        ZStack {
            backgroundColor
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 12) {
                
                // 1. Header "askLio"
                Text("askLio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(cardBackgroundColor)
                    .cornerRadius(12)
                
                // 2. Main Center Card
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Icon
                    Image("logo") // Using the asset found in the project
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .padding(.bottom, 20)
                    
                    // Title
                    Text("askLio Assistant")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.bottom, 8)
                    
                    // Subtitle
                    Text("Real-time insights from your\nmeeting. Nothing more.")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    Spacer()
                    
                    // Permissions Box
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Permissions")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                        
                        VStack(spacing: 14) {
                            PermissionRow(
                                icon: "mic",
                                title: "Microphone Access",
                                isGranted: appState.micPermissionGranted
                            )
                            PermissionRow(
                                icon: "ear",
                                title: "Audio Access",
                                isGranted: appState.systemAudioPermissionGranted
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(permissionBoxColor) // Very light gray inside the white card
                    .cornerRadius(16)
                    .padding(16) // Padding from the edge of the white card
                }
                .background(cardBackgroundColor)
                .cornerRadius(24)
                
                // 3. Start Button
                Button(action: {
                    transcriberHolder.start(appState: appState)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play") // Outline play icon like screenshot
                            .font(.system(size: 16, weight: .medium))
                        Text("Start")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(cardBackgroundColor)
                    .cornerRadius(16)
                }
                .buttonStyle(.plain) // Removes default button styling
            }
            .padding(12) // Outer padding for the whole window
        }
    }
}

// MARK: - Helper Components
struct PermissionRow: View {
    let icon: String
    let title: String
    let isGranted: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.black)
                .frame(width: 24, alignment: .center)
            
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2)) // Dark gray
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.3, green: 0.7, blue: 0.3)) // Muted Green
            }
        }
    }
}

// MARK: - Logic Holder
final class TranscriberHolder: ObservableObject {
    @Published var isRunning = false
    private var transcriber: SpeechTranscriber?

    func checkPermissions(appState: AppState) {
        // Safe check without creating SpeechTranscriber instance
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
}

// MARK: - Active Meeting View
struct ActiveMeetingView: View {
    @ObservedObject var transcriberHolder: TranscriberHolder
    @EnvironmentObject var appState: AppState
    
    // Design Constants
    let backgroundColor = Color(red: 0.93, green: 0.93, blue: 0.93) // Light Gray
    let cardBackgroundColor = Color.white
    let accentRed = Color(red: 0.8, green: 0.3, blue: 0.25) // The reddish-brown from screenshot
    
    // Layout Constants for "Perfect Corners"
    let containerPadding: CGFloat = 12
    let cardRadius: CGFloat = 24
    let innerItemRadius: CGFloat = 12 // cardRadius (24) - containerPadding (12) = 12
    
    var body: some View {
        ZStack {
            backgroundColor
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 12) {
                
                // 1. Header
                Text("askLio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(cardBackgroundColor)
                    .cornerRadius(12) // Standalone element, radius 12 looks standard
                
                // 2. Main White Card
                VStack(spacing: 0) {
                    
                    // A. Scrollable Events Area
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(appState.events) { event in
                                EventRow(
                                    icon: iconFor(event.type),
                                    color: colorFor(event.type),
                                    text: event.text,
                                    radius: innerItemRadius
                                )
                            }
                        }
                        .padding(containerPadding)
                    }
                    
                    Spacer()
                    
                    // B. Live Transcript Bubbles (Bottom of Card)
                    VStack(spacing: 8) {
                        // Mic Transcript Bubble
                        TranscriptPill(
                            text: appState.currentUtterance.isEmpty ? "Listening to microphone..." : appState.currentUtterance,
                            radius: innerItemRadius
                        )
                        
                        // System Transcript Bubble
                        TranscriptPill(
                            text: appState.systemCurrentUtterance.isEmpty ? "Listening to system audio..." : appState.systemCurrentUtterance,
                            radius: innerItemRadius
                        )
                    }
                    .padding(containerPadding)
                }
                .background(cardBackgroundColor)
                .cornerRadius(cardRadius)
                
                // 3. Footer Controls
                HStack(spacing: 12) {
                    // Pause Button
                    Button(action: {
                        // Pause logic here
                    }) {
                        HStack {
                            Image(systemName: "pause")
                            Text("Pause")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(cardBackgroundColor)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    
                    // End Button
                    Button(action: {
                        transcriberHolder.stop(appState: appState)
                    }) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("End")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(accentRed)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12) // Outer padding
        }
    }
    
    // Helpers for dynamic mapping
    func colorFor(_ type: EventType) -> Color {
        switch type {
        case .question: return .blue
        case .warning: return .red
        case .alert: return .orange
        case .success: return .green
        }
    }
    
    func iconFor(_ type: EventType) -> String {
        switch type {
        case .question: return "bubble.left"
        case .warning: return "exclamationmark.triangle"
        case .alert: return "questionmark.circle"
        case .success: return "checkmark.circle"
        }
    }
}

// MARK: - Subcomponents

struct EventRow: View {
    let icon: String
    let color: Color
    let text: String
    let radius: CGFloat
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .padding(.top, 2)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: radius)
                .stroke(color, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: radius).fill(color.opacity(0.05)))
        )
    }
}

struct TranscriptPill: View {
    let text: String
    let radius: CGFloat
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundColor(.green)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.black)
                .lineLimit(1)
            
            Spacer()
        }
        .padding(12)
        .background(Color(red: 0.96, green: 0.96, blue: 0.96)) // Very light gray pill
        .cornerRadius(radius)
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}
