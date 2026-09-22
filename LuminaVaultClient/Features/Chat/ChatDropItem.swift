// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatDropItem.swift
//
// Something dragged onto the chat composer — from Files, from another app in
// Split View, or a text selection.
//
// Everything is received as a file and handed to `AttachmentTextExtractor`,
// the same path the file picker uses, so a dropped file and a picked file
// behave identically and fail with the same message. A dropped text selection
// arrives as a plain-text file for the same reason: one extraction path, not
// two that drift.
//
// The catch-all `.item` representation is deliberate. Without it a dropped
// image is silently refused by the drop target and the user gets no feedback;
// with it, the image reaches the extractor, which says what is supported.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ChatDropItem: Transferable {
    /// A private copy. The file SwiftUI hands over is only valid inside the
    /// import closure, so it is copied out before the closure returns.
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        // Most specific first: the first representation the drag can satisfy
        // wins, and `.item` would otherwise swallow everything.
        FileRepresentation(importedContentType: .pdf) { received in
            try ChatDropItem(copying: received.file)
        }
        FileRepresentation(importedContentType: .plainText) { received in
            try ChatDropItem(copying: received.file)
        }
        FileRepresentation(importedContentType: .item) { received in
            try ChatDropItem(copying: received.file)
        }
    }

    init(url: URL) {
        self.url = url
    }

    init(copying source: URL) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "chat-drops", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Keep the original name: it becomes the attachment's label, and its
        // extension is how the extractor decides what it is reading.
        let destination = directory.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        self.url = destination
    }
}

/// Turns dropped files into staged references.
///
/// Separate from the view so the batch rule is testable: one bad file in a
/// multi-file drop is reported and skipped, and does not cost the good ones.
nonisolated enum ChatDropStaging {
    struct Outcome: Sendable {
        var staged: [AttachmentTextExtractor.Extracted] = []
        var failures: [String] = []
    }

    static func stage(_ urls: [URL]) async -> Outcome {
        var outcome = Outcome()
        for url in urls {
            do {
                outcome.staged.append(try await AttachmentTextExtractor.extractAsync(from: url))
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                outcome.failures.append("\(url.lastPathComponent): \(reason)")
            }
        }
        return outcome
    }
}
