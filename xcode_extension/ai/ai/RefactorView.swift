import SwiftUI
import XcodeKit

struct RefactorView: View {
    @State private var codeSnippet: String = ""
    @State private var refactoringSuggestions: String = ""
    @State private var isGeneratingSuggestions: Bool = false
    
    let invocation: XCSourceEditorCommandInvocation
    
    init(invocation: XCSourceEditorCommandInvocation) {
        self.invocation = invocation
        _codeSnippet = State(initialValue: getSelectedText(from: invocation))
    }
    
    var body: some View {
        VStack {
            Text("Suggest Refactoring")
                .font(.title)
                .padding()
            
            Form {
                Section(header: Text("Code Snippet")) {
                    TextEditor(text: $codeSnippet)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(height: 200)
                }
                
                Button(action: suggestRefactoring) {
                    if isGeneratingSuggestions {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Generate Suggestions")
                    }
                }
                .disabled(codeSnippet.isEmpty || isGeneratingSuggestions)
                
                if !refactoringSuggestions.isEmpty {
                    Section(header: Text("Refactoring Suggestions")) {
                        TextEditor(text: $refactoringSuggestions)
                            .font(.system(size: 14, design: .monospaced))
                            .frame(height: 200)
                    }
                    
                    Button("Insert Suggestions as Comments") {
                        insertSuggestionsAsComments()
                    }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 700)
    }
    
    private func getSelectedText(from invocation: XCSourceEditorCommandInvocation) -> String {
        guard let buffer = invocation.buffer else { return "" }
        
        return buffer.selections.compactMap { $0 as? XCSourceTextRange }.first.flatMap { range in
            buffer.lines.compactMap { $0 as? String }[range.start.line...range.end.line].joined(separator: "\n")
        } ?? ""
    }
    
    private func suggestRefactoring() {
        isGeneratingSuggestions = true
        
        guard let url = URL(string: "http://localhost:5000/api/refactor") else {
            print("Invalid URL")
            isGeneratingSuggestions = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
        let body: [String: Any] = ["code_snippet": codeSnippet, "model": selectedModel]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isGeneratingSuggestions = false
                
                if let error = error {
                    print("Error generating refactoring suggestions: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let suggestions = json["refactoring_suggestions"] as? String {
                        refactoringSuggestions = suggestions
                    }
                } catch {
                    print("Error parsing response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func insertSuggestionsAsComments() {
        guard let buffer = invocation.buffer else { return }
        
        let insertionIndex = buffer.selections.last!.end.line + 1
        let commentedSuggestions = refactoringSuggestions.split(separator: "\n").map { "// \($0)" }.joined(separator: "\n")
        buffer.lines.insert("\n// Refactoring suggestions:\n\(commentedSuggestions)\n", at: insertionIndex)
        
        let newRange = XCSourceTextRange(start: XCSourceTextPosition(line: insertionIndex, column: 0),
                                         end: XCSourceTextPosition(line: insertionIndex + commentedSuggestions.components(separatedBy: "\n").count + 2, column: 0))
        buffer.selections.removeAllObjects()
        buffer.selections.add(newRange)
        
        NSApp.stopModal()
    }
}
