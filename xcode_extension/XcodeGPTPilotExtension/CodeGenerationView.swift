import SwiftUI
import XcodeKit

struct CodeGenerationView: View {
    @State private var context: String = ""
    @State private var prompt: String = ""
    @State private var generatedCode: String = ""
    @State private var isGenerating: Bool = false
    
    let invocation: XCSourceEditorCommandInvocation
    
    init(invocation: XCSourceEditorCommandInvocation) {
        self.invocation = invocation
        _context = State(initialValue: getSelectedText(from: invocation))
    }
    
    var body: some View {
        VStack {
            Text("Generate Code")
                .font(.title)
                .padding()
            
            Form {
                Section(header: Text("Context")) {
                    TextEditor(text: $context)
                        .frame(height: 100)
                }
                
                Section(header: Text("Prompt")) {
                    TextField("Enter your code generation prompt", text: $prompt)
                }
                
                Button(action: generateCode) {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Generate")
                    }
                }
                .disabled(prompt.isEmpty || isGenerating)
                
                if !generatedCode.isEmpty {
                    Section(header: Text("Generated Code")) {
                        TextEditor(text: $generatedCode)
                            .font(.system(size: 14, design: .monospaced))
                            .frame(height: 200)
                    }
                    
                    Button("Insert Generated Code") {
                        insertGeneratedCode()
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
    
    private func generateCode() {
        isGenerating = true
        
        guard let url = URL(string: "http://localhost:5000/api/generate_code") else {
            print("Invalid URL")
            isGenerating = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
        let body: [String: Any] = ["context": context, "prompt": prompt, "model": selectedModel]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isGenerating = false
                
                if let error = error {
                    print("Error generating code: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let code = json["generated_code"] as? String {
                        generatedCode = code
                    }
                } catch {
                    print("Error parsing response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func insertGeneratedCode() {
        guard let buffer = invocation.buffer else { return }
        
        let insertionIndex = buffer.selections.last!.end.line + 1
        buffer.lines.insert("\n// Generated code:\n\(generatedCode)\n", at: insertionIndex)
        
        let newRange = XCSourceTextRange(start: XCSourceTextPosition(line: insertionIndex, column: 0),
                                         end: XCSourceTextPosition(line: insertionIndex + generatedCode.components(separatedBy: "\n").count + 2, column: 0))
        buffer.selections.removeAllObjects()
        buffer.selections.add(newRange)
        
        NSApp.stopModal()
    }
}
