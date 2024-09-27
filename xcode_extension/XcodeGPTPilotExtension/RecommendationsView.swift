import SwiftUI
import XcodeKit

struct RecommendationsView: View {
    @State private var topic: String = ""
    @State private var codeContext: String = ""
    @State private var userLevel: String = "intermediate"
    @State private var recommendations: String = ""
    @State private var isGeneratingRecommendations: Bool = false
    
    let invocation: XCSourceEditorCommandInvocation
    
    init(invocation: XCSourceEditorCommandInvocation) {
        self.invocation = invocation
        _codeContext = State(initialValue: getSelectedText(from: invocation))
    }
    
    var body: some View {
        VStack {
            Text("Learning Resource Recommendations")
                .font(.title)
                .padding()
            
            Form {
                Section(header: Text("Topic")) {
                    TextField("Enter the topic you want to learn about", text: $topic)
                }
                
                Section(header: Text("Code Context")) {
                    TextEditor(text: $codeContext)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(height: 100)
                }
                
                Section(header: Text("User Level")) {
                    Picker("Select your skill level", selection: $userLevel) {
                        Text("Beginner").tag("beginner")
                        Text("Intermediate").tag("intermediate")
                        Text("Advanced").tag("advanced")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                Button(action: generateRecommendations) {
                    if isGeneratingRecommendations {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Get Recommendations")
                    }
                }
                .disabled(topic.isEmpty || isGeneratingRecommendations)
                
                if !recommendations.isEmpty {
                    Section(header: Text("Recommended Resources")) {
                        TextEditor(text: $recommendations)
                            .font(.system(size: 14))
                            .frame(height: 200)
                    }
                    
                    Button("Insert Recommendations as Comments") {
                        insertRecommendationsAsComments()
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
    
    private func generateRecommendations() {
        isGeneratingRecommendations = true
        
        guard let url = URL(string: "http://localhost:5000/api/recommend_resources") else {
            print("Invalid URL")
            isGeneratingRecommendations = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let selectedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? "openai/gpt-4o"
        let body: [String: Any] = [
            "topic": topic,
            "code_context": codeContext,
            "user_level": userLevel,
            "model": selectedModel
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isGeneratingRecommendations = false
                
                if let error = error {
                    print("Error generating recommendations: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("No data received")
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let recommendations = json["recommendations"] as? String {
                        self.recommendations = recommendations
                    }
                } catch {
                    print("Error parsing response: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    private func insertRecommendationsAsComments() {
        guard let buffer = invocation.buffer else { return }
        
        let insertionIndex = buffer.selections.last!.end.line + 1
        let commentedRecommendations = recommendations.split(separator: "\n").map { "// \($0)" }.joined(separator: "\n")
        buffer.lines.insert("\n// Learning Resource Recommendations:\n\(commentedRecommendations)\n", at: insertionIndex)
        
        let newRange = XCSourceTextRange(start: XCSourceTextPosition(line: insertionIndex, column: 0),
                                         end: XCSourceTextPosition(line: insertionIndex + commentedRecommendations.components(separatedBy: "\n").count + 2, column: 0))
        buffer.selections.removeAllObjects()
        buffer.selections.add(newRange)
        
        NSApp.stopModal()
    }
}
