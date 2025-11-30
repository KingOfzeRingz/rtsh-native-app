# askLio - Native macOS Negotiation Meeting Assistant

**askLio** is a native macOS application designed to provide real-time AI insights during your meetings. By intelligently capturing both your microphone and system audio, it transcribes the conversation and delivers context-aware suggestions, warnings, and summaries directly to your screen.

## 🚀 Features

-   **Dual-Channel Audio Capture**: Seamlessly listens to both your microphone (what you say) and system audio (what others say) using `ScreenCaptureKit` and `AVFoundation`.
-   **Smart Speaker Switching**: Automatically detects who is speaking and switches the transcription source to ensure clear, non-overlapping text.
-   **Real-Time Transcription**: Uses Apple's on-device `SFSpeechRecognizer` for fast, private, and accurate speech-to-text.
-   **AI Insights**: Connects to a backend via WebSockets to provide real-time "Events" (Questions, Warnings, Alerts, Success messages) based on the conversation context.
-   **Native Overlay UI**: Features a modern, "glassy" macOS interface that floats unobtrusively over your other windows.
-   **Session Summaries**: Generates a comprehensive AI summary and analytics (duration) after every session.
-   **Privacy Focused**: Microphone and System Audio permissions are explicitly requested and handled securely.

## 🛠 Tech Stack

-   **Language**: Swift 5
-   **UI Framework**: SwiftUI & AppKit (for window management)
-   **Audio**: `AVFoundation`, `ScreenCaptureKit` (System Audio), `SFSpeechRecognizer` (Transcription)
-   **Networking**: `URLSession` (WebSockets & HTTP)
-   **Architecture**: MVVM (Model-View-ViewModel)

## 🔌 API Integration

The app communicates with a backend service for real-time intelligence and data persistence.

### Endpoints
-   **Real-time Events**: `ws://3.67.9.62:8767` (WebSocket)
-   **Fetch Companies**: `GET /companies`
-   **Create Conversation**: `POST /conversations`
-   **Get Summary**: `GET /get_summary/{id}`

## 📋 Prerequisites

-   **macOS 13.0 (Ventura)** or later.
-   **Xcode 14.0** or later.
-   **CocoaPods** (if dependencies are added in the future, currently zero external dependencies).

## 🏃‍♂️ Getting Started

1.  **Clone the Repository**:
    ```bash
    git clone <repository-url>
    cd rtsh-native-app
    ```

2.  **Open the Project**:
    Open `rtsh-native-app/rtsh-native-app.xcodeproj` in Xcode.

3.  **Configure Signing**:
    -   Select the project in the Project Navigator.
    -   Go to **Signing & Capabilities**.
    -   Select your **Team**.
    -   Ensure the **Bundle Identifier** is unique if you plan to deploy.

4.  **Build & Run**:
    -   Press `Cmd + R` to build and run the app.
    -   **Permissions**: On first launch, grant permissions for:
        -   **Microphone**: To hear you.
        -   **Screen Recording (System Audio)**: To hear the meeting participants.
        -   **Speech Recognition**: To transcribe audio.

## 📱 Usage

1.  **Start**: Launch the app and click the **Start** button on the welcome screen.
2.  **Select Company**: Optionally select a vendor/company context for the AI.
3.  **During Meeting**:
    -   The app will display live transcription pills for both you and the system.
    -   AI events will appear in the feed as they are detected.
    -   Use **Pause/Resume** to temporarily stop listening.
4.  **End**: Click **End** to finish the session.
5.  **Summary**: Review the session summary and click **Done** to reset.

## 🧩 Architecture Highlights

-   **`SpeechTranscriber`**: The core engine. Manages audio buffers, energy detection, and the `SFSpeechRecognizer` task. Implements the logic for switching between `.mic` and `.system` sources.
-   **`AppState`**: The central source of truth. Manages UI state (`.welcome`, `.active`, `.summary`), transcripts, and events.
-   **`OverlayWindow`**: A custom `NSWindow` subclass that implements the `NSVisualEffectView` background for that premium macOS look.
-   **`BackendClient`**: Handles the WebSocket connection for real-time events and HTTP requests for summaries.

## 🔒 Permissions & Privacy

This app requires sensitive permissions to function:
-   `NSMicrophoneUsageDescription`: "We need access to your microphone to transcribe your speech."
-   `NSSpeechRecognitionUsageDescription`: "We use speech recognition to transcribe the meeting in real-time."
-   `NSSystemAudio`: Captured via `ScreenCaptureKit`. Note that macOS requires "Screen Recording" permission to capture system audio, even if no video is recorded.

## 📄 License
All Rights Reserved
