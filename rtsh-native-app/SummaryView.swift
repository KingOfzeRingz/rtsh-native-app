import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var appState: AppState
    
    var durationString: String {
        guard let start = appState.sessionStartTime else { return "00:00" }
        let duration = Date().timeIntervalSince(start)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                Text("Session Summary")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(.bottom, 10)
            
            // Analytics
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DURATION")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(durationString)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            
            // AI Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("AI ANALYSIS")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                if let summary = appState.summaryData {
                    ScrollView {
                        Text(summary.summary)
                            .font(.body)
                            .lineSpacing(4)
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Generating summary...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // Done Button
            Button(action: {
                appState.resetSession()
            }) {
                Text("Done")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
