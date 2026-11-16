import Foundation
import ImageIO
import Vision

enum ImportOrigin: String, Codable, Sendable {
    case email = "邮件导入"
    case screenshot = "截图导入"
}

enum ImportInputError: LocalizedError {
    case tooLarge, unsupportedFile, invalidEmail, invalidImage, noText
    case duplicate, duplicateService, chooseTarget, staleTarget, invalidFields, preserveExpiry

    var errorDescription: String? {
        switch self {
        case .tooLarge: tr("文件过大。邮件最多 8 MB，图片最多 20 MB。")
        case .unsupportedFile: tr("请选择 .eml 邮件或 PNG、JPEG、HEIC、TIFF 图片。")
        case .invalidEmail: tr("没有读到可用的邮件正文。可在邮件中复制正文后粘贴。")
        case .invalidImage: tr("无法读取这张图片。请另存为 PNG 或 JPEG 后重试。")
        case .noText: tr("没有识别到文字。请使用更清晰的会员或授权截图。")
        case .duplicate: tr("该服务已有同名等级。请选择更新现有授权，或修改新等级名称。")
        case .duplicateService: tr("已有同名服务。请在保存目标中选择现有服务。")
        case .chooseTarget: tr("请选择要更新的授权，或明确选择新增等级。")
        case .staleTarget: tr("保存目标已变化，请重新选择并核对。")
        case .invalidFields: tr("请填写服务、等级和有效的到期日。")
        case .preserveExpiry: tr("已有明确有效期。请核实新日期或保留原记录。")
        }
    }
}

struct ImportLine: Sendable {
    var text: String
    var box: CGRect? = nil
}

struct ImportDocument: Sendable {
    let origin: ImportOrigin
    let lines: [ImportLine]
    init(origin: ImportOrigin, lines: [ImportLine]) {
        self.origin = origin
        self.lines = lines
    }
    init(text: String) {
        origin = .email
        lines = text.components(separatedBy: .newlines).map { ImportLine(text: $0) }
    }
}

enum ImportInput {
    static let mailLimit = 8_000_000
    static let imageLimit = 20_000_000
    static let textLimit = 100_000

    static func read(_ url: URL) throws -> ImportDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        let email = ext == "eml"
        guard email || ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(ext) else {
            throw ImportInputError.unsupportedFile
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw ImportInputError.unsupportedFile }
        let limit = email ? mailLimit : imageLimit
        guard let size = values.fileSize, size <= limit else { throw ImportInputError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ImportInputError.tooLarge }
        return try email ? ImportDocument(text: MailBodyDecoder.decode(data)) : recognize(data)
    }

    static func recognize(_ data: Data) throws -> ImportDocument {
        guard data.count <= imageLimit else { throw ImportInputError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16_000, height <= 16_000,
              width * height <= 50_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096
              ] as CFDictionary) else { throw ImportInputError.invalidImage }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        let languages = ["zh-Hans", "zh-Hant", "en-US"].filter { supported.contains($0) }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try VNImageRequestHandler(cgImage: image).perform([request])
        let fragments = (request.results ?? []).compactMap { item -> ImportLine? in
            guard let best = item.topCandidates(1).first else { return nil }
            return .init(text: best.string, box: item.boundingBox)
        }
        guard !fragments.isEmpty else { throw ImportInputError.noText }
        return .init(origin: .screenshot, lines: layout(fragments))
    }

    // Join labels and values on one baseline, but retain gaps between columns.
    static func layout(_ fragments: [ImportLine]) -> [ImportLine] {
        let ordered = fragments.sorted { ($0.box?.midY ?? 0) > ($1.box?.midY ?? 0) }
        var rows: [[ImportLine]] = []
        for fragment in ordered {
            guard let rect = fragment.box else { continue }
            if let first = rows.last?.first?.box, abs(first.midY - rect.midY) < max(first.height, rect.height) * 0.45 {
                rows[rows.count - 1].append(fragment)
            } else { rows.append([fragment]) }
        }
        return rows.flatMap { row -> [ImportLine] in
            var runs: [ImportLine] = []
            for fragment in row.sorted(by: { $0.box!.minX < $1.box!.minX }) {
                if var previous = runs.last, let a = previous.box, let b = fragment.box,
                   b.minX - a.maxX < 0.16 {
                    previous.text += " " + fragment.text
                    previous.box = a.union(b)
                    runs[runs.count - 1] = previous
                } else { runs.append(fragment) }
            }
            return runs
        }
    }
}
