// LuminaVaultClient/LuminaVaultClient/Services/ImageOCRService.swift
//
// HER-157 — on-device OCR. Uses the iOS 18+ async Vision API
// (`RecognizeTextRequest`), so there's no completion-handler/continuation
// dance and the call naturally runs off the caller's executor. Pure data in,
// joined text out. The protocol seam keeps callers testable without a real
// Vision pipeline.

import Foundation
import UIKit
import Vision

protocol ImageOCRServiceProtocol: Sendable {
    func extractText(from imageData: Data, locale: String?) async throws -> String
}

struct ImageOCRService: ImageOCRServiceProtocol {
    enum OCRError: Error, LocalizedError {
        case invalidImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImage: "Couldn't read that image."
            case .noTextFound: "No readable text in the image."
            }
        }
    }

    func extractText(from imageData: Data, locale: String? = nil) async throws -> String {
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            throw OCRError.invalidImage
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if let locale {
            request.recognitionLanguages = [Locale.Language(identifier: locale)]
        }

        let observations = try await request.perform(on: cgImage)
        let joined = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !joined.isEmpty else { throw OCRError.noTextFound }
        return joined
    }
}
