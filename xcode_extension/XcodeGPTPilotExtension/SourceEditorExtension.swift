import Foundation
import XcodeKit

class SourceEditorExtension: NSObject, XCSourceEditorExtension {
    
    func extensionDidFinishLaunching() {
        // If your extension needs to do any setup when it is loaded, implement this optional method.
    }
    
    var commandDefinitions: [[XCSourceEditorCommandDefinitionKey: Any]] {
        // If your extension needs to return a collection of command definitions that differs from those in its Info.plist, implement this optional property getter.
        return []
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
        
        let body: [String: Any] = ["context": context, "prompt": "Generate code based on this context"]
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
