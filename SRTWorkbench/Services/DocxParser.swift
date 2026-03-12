import Foundation
import ZIPFoundation

enum DocxParserError: LocalizedError {
    case cannotOpenFile
    case noDocumentXML
    case xmlParsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile: return "Cannot open .docx file"
        case .noDocumentXML: return "No word/document.xml found in .docx"
        case .xmlParsingFailed(let msg): return "XML parsing failed: \(msg)"
        }
    }
}

enum DocxParser {
    /// Extract spoken lines from a .docx script file.
    /// Filters out empty paragraphs and stage directions in [square brackets].
    static func extractSpokenLines(from url: URL) throws -> [String] {
        guard let archive = try? Archive(url: url, accessMode: .read) else {
            throw DocxParserError.cannotOpenFile
        }

        guard let entry = archive["word/document.xml"] else {
            throw DocxParserError.noDocumentXML
        }

        var xmlData = Data()
        _ = try archive.extract(entry) { data in
            xmlData.append(data)
        }

        let xmlDoc = try XMLDocument(data: xmlData, options: [])

        // Use local-name() to handle namespaced elements without needing namespaceMap
        let paragraphs = try xmlDoc.nodes(forXPath: "//*[local-name()='p']")

        var lines: [String] = []

        for para in paragraphs {
            guard let element = para as? XMLElement else { continue }

            // Collect all text runs in this paragraph
            let textNodes = try element.nodes(forXPath: ".//*[local-name()='t']")
            let fullText = textNodes.compactMap { $0.stringValue }.joined()
            let trimmed = fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            if trimmed.isEmpty { continue }

            // Skip stage directions like [Cut to dramatic music...]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { continue }

            lines.append(trimmed)
        }

        return lines
    }
}
