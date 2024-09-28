import XcodeKit

class CodeGenerationHelper {
    static func getSelectedText(from invocation: XCSourceEditorCommandInvocation) -> String {
        guard let buffer = invocation.buffer else { return "" }
        return buffer.selections.compactMap { $0 as? XCSourceTextRange }.first.flatMap { range in
            buffer.lines.compactMap { $0 as? String }[range.start.line...range.end.line].joined(separator: "\n")
        } ?? ""
    }
}