import Foundation

final class BackendClient {
    private var task: URLSessionWebSocketTask?
    private let url = URL(string: "ws://3.67.9.62:8767")!

    func connect(appState: AppState) {
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        listen(appState: appState)
    }

    func sendText(convId: String, source: String, text: String) {
        let payload: [String: Any] = [
            "conv_id": convId,
            "source": source,
            "text": text
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }

        task?.send(.string(string)) { error in
            if let error = error {
                print("WS send error:", error)
            }
        }
    }

    private func listen(appState: AppState) {
        task?.receive { [weak self] result in
            switch result {
            case .failure(let error):
                print("WS receive error:", error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text, appState: appState)
                default:
                    break
                }
            }

            self?.listen(appState: appState)
        }
    }

    private func handleMessage(_ text: String, appState: AppState) {
        guard let data = text.data(using: .utf8) else { return }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msg = obj["MESSAGE"] as? String,
               let color = obj["MESSAGE_COLOR"] as? String {
                let type: EventType
                switch color.lowercased() {
                case "red": type = .warning
                case "orange": type = .alert
                case "green": type = .success
                default: type = .question
                }
                DispatchQueue.main.async {
                    appState.handleBackendMessage(
                        AssistantEvent(type: type, text: msg)
                    )
                }
            }
        }
    }
}
