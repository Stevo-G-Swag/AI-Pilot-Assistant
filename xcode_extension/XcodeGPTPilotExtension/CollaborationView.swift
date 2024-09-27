import SwiftUI
import XcodeKit

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
        HSplitView {
            VStack {
                List(connectedUsers, id: \.self) { user in
                    Label(user, systemImage: "person.fill")
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 150, maxWidth: 200)
            }
            
            VSplitView {
                VStack {
                    Text("Collaborative Code Editing")
                        .font(.headline)
                    TextEditor(text: $currentCode)
                        .font(.system(size: 14, design: .monospaced))
                        .onChange(of: currentCode) { newValue in
                            SourceEditorExtension.shared.socket?.emit("code_update", ["code": newValue, "file_path": invocation.buffer.contentUTI])
                        }
                }
                
                VStack {
                    Text("Chat")
                        .font(.headline)
                    List(chatMessages, id: \.message) { message in
                        HStack {
                            Text(message.user).bold()
                            Text(": \(message.message)")
                        }
                    }
                    .frame(height: 150)
                    
                    HStack {
                        TextField("Type a message...", text: $currentMessage)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button("Send") {
                            sendChatMessage()
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 800, height: 600)
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
