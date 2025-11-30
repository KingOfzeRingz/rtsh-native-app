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

    // Generic send with your final schema
    func send(_ payload: [String: Any]) {
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

            // Keep listening
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
                appState.handleBackendMessage(
                    AssistantEvent(type: type, text: msg)
                )
            }
        }
    }
    
    // MARK: - HTTP API
    
    func fetchCompanies(appState: AppState) {
        guard let url = URL(string: "http://3.67.9.62:8000/companies") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching companies: \(error)")
                return
            }
            
            guard let data = data else { return }
            
            do {
                let companies = try JSONDecoder().decode([Company].self, from: data)
                appState.updateOnMain {
                    appState.companies = companies
                    // Select first company by default if none selected
                    if appState.selectedCompany == nil {
                        appState.selectedCompany = companies.first
                    }
                }
                print("Fetched \(companies.count) companies")
            } catch {
                print("Error decoding companies: \(error)")
            }
        }.resume()
    }
    
    func createConversation(companyId: Int, completion: @escaping (Int?) -> Void) {
        guard let url = URL(string: "http://3.67.9.62:8000/conversations") else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["vendor_id": companyId]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                print("Error creating conversation: \(String(describing: error))")
                completion(nil)
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? Int {
                completion(id)
            } else {
                print("Failed to parse conversation ID from response")
                completion(nil)
            }
        }.resume()
    }
    
    func fetchSummary(conversationId: Int, completion: @escaping (SummaryData?) -> Void) {
        guard let url = URL(string: "http://3.67.9.62:8000/get_summary/\(conversationId)") else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching summary: \(error)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                let summary = try JSONDecoder().decode(SummaryData.self, from: data)
                completion(summary)
            } catch {
                print("Error decoding summary: \(error)")
                // Fallback for "too short" or other errors where summary is missing
                // We construct a SummaryData with the error message
                let errorSummary = SummaryData(
                    summary: nil,
                    detail: "Meeting was too short to generate a summary.",
                    message: nil
                )
                completion(errorSummary)
            }
        }.resume()
    }
}
