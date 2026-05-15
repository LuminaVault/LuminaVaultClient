// LuminaVaultClient/LuminaVaultClient/Features/VisualSearch/VisualSearchViewModel.swift
//
// HER-157 — image-pick → OCR → /v1/query state machine. State flows
// idle → extractingText → querying → results | error. Telemetry events
// emit on every transition (HER-219 TelemetryProtocol).

import Foundation

@Observable
@MainActor
final class VisualSearchViewModel {
    enum State: Equatable, Sendable {
        case idle
        case extractingText
        case querying(extractedText: String)
        case results(QueryResponse, extractedText: String)
        case error(String)
    }

    /// Telemetry event names. Surfaced as constants so tests + analytics
    /// dashboards reference the exact strings.
    enum Event {
        static let imagePicked = "visualsearch.image_picked"
        static let ocrSucceeded = "visualsearch.ocr_succeeded"
        static let ocrFailed = "visualsearch.ocr_failed"
        static let querySucceeded = "visualsearch.query_succeeded"
        static let queryFailed = "visualsearch.query_failed"
    }

    var state: State = .idle
    /// Retained across `state` transitions so the UI can show "We
    /// searched for …" copy and offer a retry without re-OCR.
    var lastExtractedText: String = ""

    private let ocr: any ImageOCRServiceProtocol
    private let client: any MemoryQueryClientProtocol
    private let telemetry: any TelemetryProtocol
    private let resultLimit: Int

    init(
        ocr: any ImageOCRServiceProtocol,
        client: any MemoryQueryClientProtocol,
        telemetry: any TelemetryProtocol,
        resultLimit: Int = 10,
    ) {
        self.ocr = ocr
        self.client = client
        self.telemetry = telemetry
        self.resultLimit = resultLimit
    }

    /// Drives the full pipeline. Empty `imageData` short-circuits to
    /// `.error(invalidImage)` without firing the OCR pipeline.
    func runSearch(imageData: Data, locale: String? = nil) async {
        guard !imageData.isEmpty else {
            telemetry.track(Event.imagePicked, properties: ["bytes": "0"])
            telemetry.track(Event.ocrFailed)
            state = .error(ImageOCRService.OCRError.invalidImage.localizedDescription)
            return
        }
        telemetry.track(Event.imagePicked, properties: ["bytes": String(imageData.count)])
        state = .extractingText

        let extracted: String
        do {
            extracted = try await ocr.extractText(from: imageData, locale: locale)
            telemetry.track(Event.ocrSucceeded, properties: ["chars": String(extracted.count)])
        } catch {
            telemetry.track(Event.ocrFailed)
            state = .error(errorMessage(error))
            return
        }
        lastExtractedText = extracted
        state = .querying(extractedText: extracted)

        do {
            let response = try await client.query(text: extracted, limit: resultLimit)
            telemetry.track(Event.querySucceeded, properties: ["hits": String(response.hits.count)])
            state = .results(response, extractedText: extracted)
        } catch {
            telemetry.track(Event.queryFailed)
            state = .error(errorMessage(error))
        }
    }

    /// Re-runs the query against the last OCR result without re-running
    /// OCR. Used by the error-state "Retry" button after a network
    /// blip. No-op when there is no previous text.
    func retryQuery() async {
        guard !lastExtractedText.isEmpty else { return }
        state = .querying(extractedText: lastExtractedText)
        do {
            let response = try await client.query(text: lastExtractedText, limit: resultLimit)
            telemetry.track(Event.querySucceeded, properties: ["hits": String(response.hits.count)])
            state = .results(response, extractedText: lastExtractedText)
        } catch {
            telemetry.track(Event.queryFailed)
            state = .error(errorMessage(error))
        }
    }

    func reset() {
        state = .idle
        lastExtractedText = ""
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
