import Foundation
import PDFKit
import Vision
import ImageIO
import CoreGraphics

enum DocumentImportError: LocalizedError {
    case unsupportedFormat
    case notAFile
    case tooLarge
    case tooManyPages
    case unreadableText
    case unreadablePDF
    case lockedPDF
    case unreadableImage
    case tooMuchText

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Choose a PDF, text, Markdown, PNG, JPEG, HEIC, TIFF, BMP, or GIF file."
        case .notAFile: return "This item is not a readable local file."
        case .tooLarge: return "This file is larger than the 50 MB import limit. Try splitting or compressing it first."
        case .tooManyPages: return "This PDF has more than 200 pages. Import a smaller section to keep studying responsive."
        case .unreadableText: return "The text file could not be decoded. Save it as UTF-8 or UTF-16 text and try again."
        case .unreadablePDF: return "This PDF could not be opened. Export it as a new PDF and try again."
        case .lockedPDF: return "This PDF requires a password. Unlock it in Preview and save an unlocked copy first."
        case .unreadableImage: return "This image could not be decoded. Export it as a PNG or JPEG and try again."
        case .tooMuchText: return "This document contains more than two million characters. Import a smaller section."
        }
    }
}

/// All decoding and recognition happens off the main actor. Only a successful import
/// leaves a managed file behind, including when the calling task is cancelled.
enum DocumentImporter {
    static let maximumFileBytes = 50 * 1024 * 1024
    static let maximumPDFPages = 200
    static let maximumTextCharacters = 2_000_000
    private static let textExtensions: Set<String> = ["txt", "text", "md", "markdown"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif"]
    private static let recognitionWarning = "Recognized on this Mac. OCR can misread words, equations, symbols, and layout; inspect and correct the extracted text before relying on it."

    private final class RecognitionCancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var request: VNRequest?
        private var cancelled = false

        func set(_ newRequest: VNRequest?) {
            lock.lock()
            request = newRequest
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel { newRequest?.cancel() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let activeRequest = request
            lock.unlock()
            activeRequest?.cancel()
        }
    }

    static func importFile(at source: URL, subjectID: UUID, into directory: URL) async throws -> Material {
        try Task.checkCancellation()
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let recognitionCancellation = RecognitionCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try performImport(at: source, subjectID: subjectID, into: directory, cancellation: recognitionCancellation)
        }
        return try await withTaskCancellationHandler(operation: {
            let material = try await worker.value
            do {
                try Task.checkCancellation()
                return material
            } catch {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(material.storedFilename))
                throw error
            }
        }, onCancel: {
            worker.cancel()
            recognitionCancellation.cancel()
        })
    }

    private static func performImport(at source: URL, subjectID: UUID, into directory: URL, cancellation: RecognitionCancellation) throws -> Material {
        try Task.checkCancellation()
        guard source.isFileURL else { throw DocumentImportError.notAFile }
        let ext = source.pathExtension.lowercased()
        guard textExtensions.contains(ext) || imageExtensions.contains(ext) || ext == "pdf" else {
            throw DocumentImportError.unsupportedFormat
        }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw DocumentImportError.notAFile }
        guard let size = values.fileSize, size <= maximumFileBytes else { throw DocumentImportError.tooLarge }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let filename = id.uuidString + "." + ext
        let destination = directory.appendingPathComponent(filename)
        var succeeded = false
        defer { if !succeeded { try? manager.removeItem(at: destination) } }
        try manager.copyItem(at: source, to: destination)
        try Task.checkCancellation()
        // Verify the copy as well in case the original changed while being imported.
        let copiedSize = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard copiedSize <= maximumFileBytes else { throw DocumentImportError.tooLarge }

        let pages: [MaterialPage]
        let kind: String
        if ext == "pdf" {
            kind = "pdf"
            pages = try extractPDF(at: destination, cancellation: cancellation)
        } else if imageExtensions.contains(ext) {
            kind = "image"
            pages = [try extractImage(at: destination, cancellation: cancellation)]
        } else {
            kind = (ext == "md" || ext == "markdown") ? "markdown" : "text"
            let data = try Data(contentsOf: destination, options: .mappedIfSafe)
            guard let text = decodeText(data) else { throw DocumentImportError.unreadableText }
            guard text.count <= maximumTextCharacters else { throw DocumentImportError.tooMuchText }
            let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            pages = [MaterialPage(number: 1, text: text, warning: empty ? "This file contains no readable text. Add or correct its extracted text before using it as a source." : nil)]
        }
        try Task.checkCancellation()
        let unreadable = pages.filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        let ocrCount = pages.filter(\.usedOCR).count
        var warnings: [String] = []
        if unreadable > 0 { warnings.append("\(unreadable) of \(pages.count) pages contain no readable text and cannot support tutor answers.") }
        if ocrCount > 0 { warnings.append("\(ocrCount) page\(ocrCount == 1 ? "" : "s") used on-device OCR. Check mathematical notation and extraction accuracy.") }
        let material = Material(id: id, subjectID: subjectID, name: source.lastPathComponent,
                                storedFilename: filename, pages: pages, kind: kind,
                                warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
        succeeded = true
        return material
    }

    private static func decodeText(_ data: Data) -> String? {
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard var result = text, !result.contains("\0") else { return nil }
        if result.first == "\u{FEFF}" { result.removeFirst() }
        return result.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func extractPDF(at url: URL, cancellation: RecognitionCancellation) throws -> [MaterialPage] {
        guard let document = PDFDocument(url: url) else { throw DocumentImportError.unreadablePDF }
        guard !document.isLocked else { throw DocumentImportError.lockedPDF }
        guard document.pageCount > 0 else { throw DocumentImportError.unreadablePDF }
        guard document.pageCount <= maximumPDFPages else { throw DocumentImportError.tooManyPages }
        var pages: [MaterialPage] = []
        var totalCharacters = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let extracted: MaterialPage = try autoreleasepool {
                guard let page = document.page(at: index) else {
                    return MaterialPage(number: index + 1, text: "", warning: "This page could not be opened. It is unavailable as a source.")
                }
                let embedded = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !embedded.isEmpty { return MaterialPage(number: index + 1, text: embedded) }
                guard let image = renderedPage(page) else {
                    return MaterialPage(number: index + 1, text: "", warning: "This page could not be rendered for text recognition. It is unavailable as a source.")
                }
                return try recognize(image, pageNumber: index + 1, cancellation: cancellation)
            }
            totalCharacters += extracted.text.count
            guard totalCharacters <= maximumTextCharacters else { throw DocumentImportError.tooMuchText }
            pages.append(extracted)
        }
        return pages
    }

    private static func renderedPage(_ page: PDFPage) -> CGImage? {
        guard let reference = page.pageRef else { return nil }
        let bounds = reference.getBoxRect(.cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { return nil }
        let rotation = abs(reference.rotationAngle) % 180
        let displayWidth = rotation == 90 ? bounds.height : bounds.width
        let displayHeight = rotation == 90 ? bounds.width : bounds.height
        let scale = min(2.5, 2500 / max(displayWidth, displayHeight))
        let width = max(1, Int(displayWidth * scale))
        let height = max(1, Int(displayHeight * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.concatenate(reference.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(reference)
        return context.makeImage()
    }

    private static func extractImage(at url: URL, cancellation: RecognitionCancellation) throws -> MaterialPage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3000,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw DocumentImportError.unreadableImage }
        var page = try recognize(image, pageNumber: 1, cancellation: cancellation)
        if CGImageSourceGetCount(source) > 1 {
            page.warning = (page.warning ?? "") + " Only the first image/frame was recognized; split multi-image files to include the others."
        }
        return page
    }

    private static func recognize(_ image: CGImage, pageNumber: Int, cancellation: RecognitionCancellation) throws -> MaterialPage {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        cancellation.set(request)
        defer { cancellation.set(nil) }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            try Task.checkCancellation()
            let observations = request.results ?? []
            let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let warning = text.isEmpty
                ? "No readable text was recognized on this page. Inspect the original and enter corrected text before using it as a source. " + recognitionWarning
                : recognitionWarning
            return MaterialPage(number: pageNumber, text: text, usedOCR: true, warning: warning)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return MaterialPage(number: pageNumber, text: "", usedOCR: true,
                                warning: "On-device text recognition failed for this page. It is unavailable as a source until you enter corrected text.")
        }
    }
}
