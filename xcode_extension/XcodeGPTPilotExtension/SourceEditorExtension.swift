import Foundation
import XcodeKit
import SwiftUI
import SocketIO

class SourceEditorExtension: NSObject, XCSourceEditorExtension {
    
    static let shared = SourceEditorExtension()
    var socket: SocketIOClient?
    var manager: SocketManager?
    var connectedUsers: [String] = []
    
    override init() {
        super.init()
        setupSocket()
    }
    
    func setupSocket() {
        manager = SocketManager(socketURL: URL(string: "http://localhost:5000")!, config: [.log(true), .compress])
        socket = manager?.defaultSocket
        
        socket?.on(clientEvent: .connect) { data, ack in
            print("Socket connected")
        }
        
        socket?.on("user_list") { [weak self] data, ack in
            if let users = data[0] as? [String] {
                self?.connectedUsers = users
                NotificationCenter.default.post(name: .connectedUsersUpdated, object: nil)
            }
        }
        
        socket?.on("code_update") { data, ack in
            if let codeData = data[0] as? [String: Any],
               let code = codeData["code"] as? String,
               let filePath = codeData["file_path"] as? String {
                NotificationCenter.default.post(name: .codeUpdated, object: nil, userInfo: ["code": code, "file_path": filePath])
            }
        }
        
        socket?.on("chat_message") { data, ack in
            if let messageData = data[0] as? [String: Any],
               let user = messageData["user"] as? String,
               let message = messageData["message"] as? String {
                NotificationCenter.default.post(name: .chatMessageReceived, object: nil, userInfo: ["user": user, "message": message])
            }
        }
        
        socket?.connect()
    }
    
    func extensionDidFinishLaunching() {
        // If your extension needs to do any setup when it is loaded, implement this optional method.
    }
    
    var commandDefinitions: [[XCSourceEditorCommandDefinitionKey: Any]] {
        return [
            [
                .identifierKey: "com.yourcompany.XcodeGPTPilot.GenerateCodeCommand",
                .classNameKey: "SourceEditorCommand",
                .nameKey: "Generate Code"
            ],
            [
                .identifierKey: "com.yourcompany.XcodeGPTPilot.RefactorCodeCommand",
                .classNameKey: "RefactorCodeCommand",
                .nameKey: "Suggest Refactoring"
            ],
            [
                .identifierKey: "com.yourcompany.XcodeGPTPilot.SettingsCommand",
                .classNameKey: "SettingsCommand",
                .nameKey: "Settings"
            ],
            [
                .identifierKey: "com.yourcompany.XcodeGPTPilot.CollaborationCommand",
                .classNameKey: "CollaborationCommand",
                .nameKey: "Collaboration"
            ],
            [
                .identifierKey: "com.yourcompany.XcodeGPTPilot.RecommendResourcesCommand",
                .classNameKey: "RecommendResourcesCommand",
                .nameKey: "Recommend Learning Resources"
            ]
        ]
    }
}

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        guard let buffer = invocation.buffer else {
            showAlert(message: "Unable to access buffer")
            completionHandler(NSError(domain: "XcodeGPTPilot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access buffer"]))
            return
        }
        
        let selectedText = buffer.selections.compactMap { $0 as? XCSourceTextRange }.first.flatMap { range in
            buffer.lines.compactMap { $0 as? String }[range.start.line...range.end.line].joined(separator: "\n")
        } ?? ""
        
        generateCode(context: selectedText) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let generatedCode):
                    self.insertGeneratedCode(generatedCode, into: buffer)
                    completionHandler(nil)
                case .failure(let error):
                    self.showAlert(message: error.localizedDescription)
                    completionHandler(error)
                }
            }
        }
    }
    
    private func insertGeneratedCode(_ code: String, into buffer: XCSourceTextBuffer) {
        let insertionIndex = buffer.selections.last!.end.line + 1
        buffer.lines.insert("\n// Generated code:\n\(code)\n", at: insertionIndex)
        
        // Update selection to include the newly inserted code
        let newRange = XCSourceTextRange(start: XCSourceTextPosition(line: insertionIndex, column: 0),
                                         end: XCSourceTextPosition(line: insertionIndex + code.components(separatedBy: "\n").count + 2, column: 0))
        buffer.selections.removeAllObjects()
        buffer.selections.add(newRange)
    }
    
    private func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Xcode GPT Pilot"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func generateCode(context: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://localhost:5000/api/generate_code") else {
            completion(.failure(NSError(domain: "XcodeGPTPilot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
        let body: [String: Any] = ["context": context, "prompt": "Generate code based on this context", "model": selectedModel]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Network error: \(error.localizedDescription)"])))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 5, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 6, userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let generatedCode = json["generated_code"] as? String {
                    completion(.success(generatedCode))
                } else {
                    completion(.failure(NSError(domain: "XcodeGPTPilot", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from server"])))
                }
            } catch {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 8, userInfo: [NSLocalizedDescriptionKey: "Error parsing server response: \(error.localizedDescription)"])))
            }
        }.resume()
    }
}

class RefactorCodeCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        guard let buffer = invocation.buffer else {
            showAlert(message: "Unable to access buffer")
            completionHandler(NSError(domain: "XcodeGPTPilot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access buffer"]))
            return
        }
        
        let selectedText = buffer.selections.compactMap { $0 as? XCSourceTextRange }.first.flatMap { range in
            buffer.lines.compactMap { $0 as? String }[range.start.line...range.end.line].joined(separator: "\n")
        } ?? ""
        
        suggestRefactoring(codeSnippet: selectedText) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let suggestions):
                    self.insertRefactoringSuggestions(suggestions, into: buffer)
                    completionHandler(nil)
                case .failure(let error):
                    self.showAlert(message: error.localizedDescription)
                    completionHandler(error)
                }
            }
        }
    }
    
    private func insertRefactoringSuggestions(_ suggestions: String, into buffer: XCSourceTextBuffer) {
        let insertionIndex = buffer.selections.last!.end.line + 1
        buffer.lines.insert("\n// Refactoring suggestions:\n\(suggestions)\n", at: insertionIndex)
        
        // Update selection to include the newly inserted suggestions
        let newRange = XCSourceTextRange(start: XCSourceTextPosition(line: insertionIndex, column: 0),
                                         end: XCSourceTextPosition(line: insertionIndex + suggestions.components(separatedBy: "\n").count + 2, column: 0))
        buffer.selections.removeAllObjects()
        buffer.selections.add(newRange)
    }
    
    private func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Xcode GPT Pilot"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func suggestRefactoring(codeSnippet: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://localhost:5000/api/refactor") else {
            completion(.failure(NSError(domain: "XcodeGPTPilot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
        let body: [String: Any] = ["code_snippet": codeSnippet, "model": selectedModel]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Network error: \(error.localizedDescription)"])))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 5, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 6, userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let suggestions = json["refactoring_suggestions"] as? String {
                    completion(.success(suggestions))
                } else {
                    completion(.failure(NSError(domain: "XcodeGPTPilot", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from server"])))
                }
            } catch {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 8, userInfo: [NSLocalizedDescriptionKey: "Error parsing server response: \(error.localizedDescription)"])))
            }
        }.resume()
    }
}

class SettingsCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let settingsWindow = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 300, height: 200),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            settingsWindow.title = "Xcode GPT Pilot Settings"
            
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            settingsWindow.contentView = hostingController.view
            
            NSApp.runModal(for: settingsWindow)
            completionHandler(nil)
        }
    }
}

class CollaborationCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let collaborationWindow = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 400, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            collaborationWindow.title = "Xcode GPT Pilot Collaboration"
            
            let collaborationView = CollaborationView(invocation: invocation)
            let hostingController = NSHostingController(rootView: collaborationView)
            collaborationWindow.contentView = hostingController.view
            
            NSApp.runModal(for: collaborationWindow)
            completionHandler(nil)
        }
    }
}

class RecommendResourcesCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        guard let buffer = invocation.buffer else {
            showAlert(message: "Unable to access buffer")
            completionHandler(NSError(domain: "XcodeGPTPilot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to access buffer"]))
            return
        }
        
        let selectedText = buffer.selections.compactMap { $0 as? XCSourceTextRange }.first.flatMap { range in
            buffer.lines.compactMap { $0 as? String }[range.start.line...range.end.line].joined(separator: "\n")
        } ?? ""
        
        recommendResources(codeContext: selectedText) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let recommendations):
                    self.showRecommendationsWindow(recommendations: recommendations)
                    completionHandler(nil)
                case .failure(let error):
                    self.showAlert(message: error.localizedDescription)
                    completionHandler(error)
                }
            }
        }
    }
    
    private func showRecommendationsWindow(recommendations: String) {
        let recommendationsWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        recommendationsWindow.title = "Learning Resource Recommendations"
        
        let recommendationsView = RecommendationsView(recommendations: recommendations)
        let hostingController = NSHostingController(rootView: recommendationsView)
        recommendationsWindow.contentView = hostingController.view
        
        NSApp.runModal(for: recommendationsWindow)
    }
    
    private func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Xcode GPT Pilot"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func recommendResources(codeContext: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://localhost:5000/api/recommend_resources") else {
            completion(.failure(NSError(domain: "XcodeGPTPilot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
        let body: [String: Any] = [
            "topic": "Swift programming",
            "code_context": codeContext,
            "user_level": "intermediate",
            "model": selectedModel
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Network error: \(error.localizedDescription)"])))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])))
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 5, userInfo: [NSLocalizedDescriptionKey: "Server error: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 6, userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let recommendations = json["recommendations"] as? String {
                    completion(.success(recommendations))
                } else {
                    completion(.failure(NSError(domain: "XcodeGPTPilot", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from server"])))
                }
            } catch {
                completion(.failure(NSError(domain: "XcodeGPTPilot", code: 8, userInfo: [NSLocalizedDescriptionKey: "Error parsing server response: \(error.localizedDescription)"])))
            }
        }.resume()
    }
}

struct SettingsView: View {
    @State private var selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
    @State private var models: [AIModel] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Xcode GPT Pilot Settings")
                .font(.title)
            
            Picker("Select AI Model", selection: $selectedModel) {
                ForEach(models) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            
            Button("Save") {
                UserDefaults.standard.set(selectedModel, forKey: "SelectedModel")
                NSApp.stopModal()
            }
        }
        .padding()
        .frame(width: 300, height: 200)
        .onAppear {
            fetchAvailableModels()
        }
    }
    
    private func fetchAvailableModels() {
        guard let url = URL(string: "http://localhost:5000/api/models") else {
            print("Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching models: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                let decodedModels = try JSONDecoder().decode([AIModel].self, from: data)
                DispatchQueue.main.async {
                    self.models = decodedModels
                }
            } catch {
                print("Error decoding models: \(error.localizedDescription)")
            }
        }.resume()
    }
}

struct CollaborationView: View {
    @State private var connectedUsers: [String] = []
    @State private var chatMessages: [(user: String, message: String)] = []
    @State private var currentMessage: String = ""
    @State private var currentCode: String = ""
    
    let invocation: XCSourceEditorCommandInvocation
    
    init(invocation: XCSourceEditorCommandInvocation) {
        self.invocation = invocation
        _currentCode = State(initialValue: invocation.buffer.completeBuffer)
    }
    
    var body: some View {
        VStack {
            Text("Connected Users")
                .font(.headline)
            List(connectedUsers, id: \.self) { user in
                Text(user)
            }
            .frame(height: 100)
            
            Text("Collaborative Code Editing")
                .font(.headline)
            TextEditor(text: $currentCode)
                .font(.system(size: 14, design: .monospaced))
                .onChange(of: currentCode) { newValue in
                    SourceEditorExtension.shared.socket?.emit("code_update", ["code": newValue, "file_path": invocation.buffer.contentUTI])
                }
            
            Text("Chat")
                .font(.headline)
            List(chatMessages, id: \.message) { message in
                Text("\(message.user): \(message.message)")
            }
            .frame(height: 150)
            
            HStack {
                TextField("Type a message...", text: $currentMessage)
                Button("Send") {
                    sendChatMessage()
                }
            }
        }
        .padding()
        .onAppear {
            setupNotifications()
        }
        .onDisappear {
            removeNotifications()
        }
    }
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .connectedUsersUpdated, object: nil, queue: .main) { _ in
            self.connectedUsers = SourceEditorExtension.shared.connectedUsers
        }
        
        NotificationCenter.default.addObserver(forName: .codeUpdated, object: nil, queue: .main) { notification in
            if let userInfo = notification.userInfo,
               let code = userInfo["code"] as? String,
               let filePath = userInfo["file_path"] as? String,
               filePath == invocation.buffer.contentUTI {
                self.currentCode = code
                self.invocation.buffer.completeBuffer = code
            }
        }
        
        NotificationCenter.default.addObserver(forName: .chatMessageReceived, object: nil, queue: .main) { notification in
            if let userInfo = notification.userInfo,
               let user = userInfo["user"] as? String,
               let message = userInfo["message"] as? String {
                self.chatMessages.append((user: user, message: message))
            }
        }
    }
    
    func removeNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    func sendChatMessage() {
        guard !currentMessage.isEmpty else { return }
        SourceEditorExtension.shared.socket?.emit("chat_message", ["user": "Xcode User", "message": currentMessage])
        currentMessage = ""
    }
}

struct RecommendationsView: View {
    let recommendations: String
    
    var body: some View {
        ScrollView {
            Text(recommendations)
                .padding()
        }
    }
}

struct AIModel: Codable, Identifiable {
    let id: String
    let name: String
}

extension Notification.Name {
    static let connectedUsersUpdated = Notification.Name("connectedUsersUpdated")
    static let codeUpdated = Notification.Name("codeUpdated")
    static let chatMessageReceived = Notification.Name("chatMessageReceived")
}