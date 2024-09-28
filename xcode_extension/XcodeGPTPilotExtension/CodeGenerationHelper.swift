import XcodeKit

class CodeGenerationHelper {
    static func getSelectedText(from invocation: XCSourceEditorCommandInvocation) -> String {
        let buffer = invocation.buffer
        return buffer.selections.compactMap { $0 as? XCSourceTextRange }.first.flatMap { range in
            buffer.lines.compactMap { $0 as? String }[range.start.line...range.end.line].joined(separator: "\n")
        } ?? ""
    }
}