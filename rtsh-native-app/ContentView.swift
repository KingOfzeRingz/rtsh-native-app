import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var transcriberHolder = TranscriberHolder()

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .welcome:
                StartView(transcriberHolder: transcriberHolder)
                    .transition(.opacity)
            case .active:
                ActiveMeetingView(transcriberHolder: transcriberHolder)
                    .transition(.opacity)
            case .summary:
                SummaryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: appState.currentScreen)

        // Removed fixed frame and opaque background
        .onAppear {
            appState.backendClient.connect(appState: appState)
            transcriberHolder.checkPermissions(appState: appState)
        }
    }
}

struct StartView: View {
    @ObservedObject var transcriberHolder: TranscriberHolder
    @EnvironmentObject var appState: AppState

    let backgroundColor = Color(red: 0.93, green: 0.93, blue: 0.93)
    let cardBackgroundColor = Color.white
    let permissionBoxColor = Color(red: 0.97, green: 0.97, blue: 0.97)

    var body: some View {
        ZStack {
            // Removed solid background


            VStack(spacing: 12) {

                Text("Sekundant  x  askLio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.regularMaterial) // Glassy
                    .cornerRadius(12)

                VStack(spacing: 0) {
                    Spacer()

                    Image("logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 50, height: 50)
                        .padding(.bottom, 20)

                    Text("Negotiation Assistant")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.bottom, 8)

                    Text("Real-time insights from your meeting. Nothing more.")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    
                    // Company Picker
                    if !appState.companies.isEmpty {
                        Picker("Select Company", selection: $appState.selectedCompany) {
                            ForEach(appState.companies) { company in
                                Text(company.name).tag(company as Company?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.top, 16)
                        .padding(.horizontal, 40)
                    }

                    Spacer()

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
                    .background(permissionBoxColor)
                    .cornerRadius(16)
                    .padding(16)
                }

                .background(.regularMaterial) // Glassy
                .cornerRadius(24)

                Button(action: {
                    appState.startNewConversation {
                        transcriberHolder.start(appState: appState)
                    }
                }) {
                    HStack(spacing: 8) {
                        if appState.isStarting {
                            ProgressView()
                                .controlSize(.small)
                                .colorInvert()
                                .brightness(1)
                        } else {
                            Image(systemName: "play")
                                .font(.system(size: 16, weight: .medium))
                            Text("Start")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .frame(height: 50)
                    .background(.regularMaterial) // Glassy
                    .cornerRadius(16)
                }
                .buttonStyle(.plain)
                .disabled(appState.isStarting)
            }
            .padding(12)
        }
        .onAppear {
            appState.backendClient.fetchCompanies(appState: appState)
        }
    }
}

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
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))

            Spacer()

            if isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.3, green: 0.7, blue: 0.3))
            }
        }
    }
}

struct ActiveMeetingView: View {
    @ObservedObject var transcriberHolder: TranscriberHolder
    @EnvironmentObject var appState: AppState

    let backgroundColor = Color(red: 0.93, green: 0.93, blue: 0.93)
    let cardBackgroundColor = Color.white
    let accentRed = Color(red: 0.8, green: 0.3, blue: 0.25)

    let containerPadding: CGFloat = 12
    let cardRadius: CGFloat = 24
    let innerItemRadius: CGFloat = 12

    var body: some View {
        ZStack {
            // Removed solid background


            VStack(spacing: 12) {
                Text("askLio")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.regularMaterial) // Glassy
                    .cornerRadius(12)

                VStack(spacing: 0) {
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

                    Spacer(minLength: 8)

                    VStack(spacing: 8) {
                        TranscriptPill(
                            text: appState.currentUtterance.isEmpty
                                ? "Listening to microphone..."
                                : appState.currentUtterance,
                            radius: innerItemRadius
                        )

                        TranscriptPill(
                            text: appState.systemCurrentUtterance.isEmpty
                                ? "Listening to system audio..."
                                : appState.systemCurrentUtterance,
                            radius: innerItemRadius
                        )
                    }
                    .padding(containerPadding)
                }

                .background(.regularMaterial) // Glassy
                .cornerRadius(cardRadius)
                // Controls
                HStack(spacing: 16) {
                    Button(action: {
                        if appState.isPaused {
                            transcriberHolder.resume(appState: appState)
                        } else {
                            transcriberHolder.pause(appState: appState)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(appState.isPaused ? "Resume" : "Pause")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        transcriberHolder.stop(appState: appState)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("End")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(12)
        }
    }

    func colorFor(_ type: EventType) -> Color {
        switch type {
        case .question: return .blue
        case .warning: return .red
        case .alert:   return .orange
        case .success: return .green
        }
    }

    func iconFor(_ type: EventType) -> String {
        switch type {
        case .question: return "bubble.left"
        case .warning:  return "exclamationmark.triangle"
        case .alert:    return "questionmark.circle"
        case .success:  return "checkmark.circle"
        }
    }
}

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
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(color.opacity(0.05))
                )
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
                .truncationMode(.head) // Show the latest text

            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial) // Glassy pill
        .cornerRadius(radius)
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}
