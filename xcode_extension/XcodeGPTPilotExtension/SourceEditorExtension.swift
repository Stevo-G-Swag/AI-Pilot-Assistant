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
                .classNameKey: "GenerateCodeCommand",
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

class GenerateCodeCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        DispatchQueue.main.async {
            let codeGenerationView = CodeGenerationView(invocation: invocation)
            let hostingController = NSHostingController(rootView: codeGenerationView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Generate Code"
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            completionHandler(nil)
        }
    }
}

class RefactorCodeCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        DispatchQueue.main.async {
            let refactorView = RefactorView(invocation: invocation)
            let hostingController = NSHostingController(rootView: refactorView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Suggest Refactoring"
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            completionHandler(nil)
        }
    }
}

class SettingsCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Xcode GPT Pilot Settings"
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            completionHandler(nil)
        }
    }
}

class CollaborationCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let collaborationView = CollaborationView(invocation: invocation)
            let hostingController = NSHostingController(rootView: collaborationView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Xcode GPT Pilot Collaboration"
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            completionHandler(nil)
        }
    }
}

class RecommendResourcesCommand: NSObject, XCSourceEditorCommand {
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void) {
        DispatchQueue.main.async {
            let recommendationsView = RecommendationsView(invocation: invocation)
            let hostingController = NSHostingController(rootView: recommendationsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Learning Resource Recommendations"
            window.makeKeyAndOrderFront(nil)
            NSApp.runModal(for: window)
            completionHandler(nil)
        }
    }
}

struct AIModel: Codable, Identifiable {
    let id: String
    let name: String
}

struct Preference: Codable {
    let key: String
    let value: String
}

extension Notification.Name {
    static let connectedUsersUpdated = Notification.Name("connectedUsersUpdated")
    static let codeUpdated = Notification.Name("codeUpdated")
    static let chatMessageReceived = Notification.Name("chatMessageReceived")
}
