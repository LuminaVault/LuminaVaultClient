// LuminaVaultClient/LuminaVaultClient/Services/ImageOCRService.swift
//
// HER-157 — VisionKit `VNRecognizeTextRequest` wrapper. Pure data in,
// joined text out. No UIKit beyond the UIImage decode (cheaper than
// rewriting the data→CGImage path with ImageIO). The protocol seam
// keeps the ViewModel testable without spinning up a real Vision
// pipeline.

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
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { !$0.isEmpty }
                let joined = lines.joined(separator: "\n")
                if joined.isEmpty {
                    continuation.resume(throwing: OCRError.noTextFound)
                } else {
                    continuation.resume(returning: joined)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            if let locale {
                request.recognitionLanguages = [locale]
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
