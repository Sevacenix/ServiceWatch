import Foundation

enum MailBodyDecoder {
    static func decode(_ data: Data) throws -> String {
        guard data.count <= ImportInput.mailLimit else { throw ImportInputError.tooLarge }
        // Latin-1 maps MIME transport bytes one-to-one; decode each part's charset separately.
        let transport = String(decoding: data.map(UInt16.init), as: UTF16.self)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard let (headers, _) = split(transport),
              let body = body(transport, depth: 0)?.text, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ImportInputError.invalidEmail }
        let subject = decodeSubject(headers["subject"] ?? "")
        return String(([subject, body].filter { !$0.isEmpty }.joined(separator: "\n")).prefix(ImportInput.textLimit))
    }

    private static func split(_ message: String) -> ([String: String], String)? {
        guard let end = message.range(of: "\n\n"),
              message.distance(from: message.startIndex, to: end.lowerBound) <= 65_536 else { return nil }
        let header = message[..<end.lowerBound].replacingOccurrences(of: "\n[ \t]+", with: " ", options: .regularExpression)
        var headers: [String: String] = [:]
        for line in header.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard !headers.isEmpty else { return nil }
        return (headers, String(message[end.upperBound...]))
    }

    private static func parameter(_ key: String, in value: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "(?:^|;)\\s*" + key + "\\s*=\\s*(?:\"([^\"]+)\"|([^;\\s]+))", options: .caseInsensitive)
        guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return [1, 2].compactMap { Range(match.range(at: $0), in: value).map { String(value[$0]) } }.first
    }

    private static func body(_ message: String, depth: Int) -> (text: String, plain: Bool)? {
        guard depth < 8, let (headers, content) = split(message.trimmingCharacters(in: .newlines)) else { return nil }
        let type = headers["content-type"] ?? "text/plain"
        let mime = type.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let disposition = headers["content-disposition"]?.lowercased() ?? ""
        guard !disposition.hasPrefix("attachment"), parameter("filename", in: disposition) == nil,
              parameter("name", in: type) == nil else { return nil }
        if mime.hasPrefix("multipart/"), let boundary = parameter("boundary", in: type), boundary.count <= 200 {
            var parts: [(text: String, plain: Bool)] = []
            var current: [String]? = nil
            for line in content.components(separatedBy: "\n") {
                let marker = line.trimmingCharacters(in: .whitespaces)
                if marker == "--" + boundary || marker == "--" + boundary + "--" {
                    if let current, let decoded = body(current.joined(separator: "\n"), depth: depth + 1) { parts.append(decoded) }
                    current = []
                    if marker == "--" + boundary + "--" || parts.count >= 32 { break }
                } else { current?.append(line) }
            }
            if mime == "multipart/alternative" { return parts.first(where: \.plain) ?? parts.first }
            // Primary body only: attachments and forwarded messages cannot override it.
            return parts.first
        }
        guard mime == "text/plain" || mime == "text/html",
              let bytes = decodeBytes(content, encoding: headers["content-transfer-encoding"] ?? "8bit"),
              let text = decodeText(bytes, charset: parameter("charset", in: type)) else { return nil }
        let excerpt = String(text.prefix(2 * ImportInput.textLimit))
        return (mime == "text/html" ? htmlText(excerpt) : excerpt, mime == "text/plain")
    }

    private static func decodeSubject(_ subject: String) -> String {
        let value = subject.replacingOccurrences(of: "(\\?=)\\s+(=\\?)", with: "$1$2", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: "=\\?([^?]+)\\?([bBqQ])\\?([^?]*)\\?=")
        var output = decodeText(transportBytes(value), charset: nil) ?? value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            let parts = (0...3).compactMap { Range(match.range(at: $0), in: value).map { String(value[$0]) } }
            guard parts.count == 4 else { continue }
            let base64 = parts[2].lowercased() == "b"
            let content = base64 ? parts[3] : parts[3].replacingOccurrences(of: "_", with: " ")
            if let bytes = decodeBytes(content, encoding: base64 ? "base64" : "quoted-printable"),
               let decoded = decodeText(bytes, charset: parts[1]), let range = output.range(of: parts[0], options: .backwards) {
                output.replaceSubrange(range, with: decoded)
            }
        }
        return output
    }

    private static func transportBytes(_ value: String) -> Data {
        Data(value.utf16.map { UInt8(truncatingIfNeeded: $0) })
    }

    private static func decodeBytes(_ content: String, encoding: String) -> Data? {
        switch encoding.lowercased() {
        case "base64": return Data(base64Encoded: content.filter { !$0.isWhitespace })
        case "quoted-printable":
            let bytes = Array(transportBytes(content))
            var result = Data(), index = 0
            while index < bytes.count {
                if bytes[index] == 61, index + 1 < bytes.count {
                    if bytes[index + 1] == 10 { index += 2; continue }
                    if index + 2 < bytes.count,
                       let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                        result.append(byte); index += 3; continue
                    }
                }
                result.append(bytes[index]); index += 1
            }
            return result
        case "", "7bit", "8bit", "binary": return transportBytes(content)
        default: return nil
        }
    }

    private static func decodeText(_ bytes: Data, charset: String?) -> String? {
        if let charset {
            let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            guard encoding != kCFStringEncodingInvalidId else { return nil }
            return String(data: bytes, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
        }
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
    }

    private static func htmlText(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "(?is)<!--.*?-->|<(head|script|style|blockquote)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<\\s*/?\\s*(br|p|div|li|tr|h[1-6])\\b[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</t[dh]\\s*>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        let regex = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let full = Range(match.range, in: text), let inner = Range(match.range(at: 1), in: text) else { continue }
            let entity = String(text[inner])
            let numeric = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16) :
                entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
            if let decoded = entities[entity] ?? numeric.flatMap(UnicodeScalar.init).map(String.init) {
                text.replaceSubrange(full, with: decoded)
            }
        }
        return text
    }
}
