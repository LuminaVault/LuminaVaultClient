// LuminaVaultClient/LuminaVaultClientTests/VisualSearchViewModelTests.swift
//
// HER-157 — state-machine + telemetry contract tests for
// `VisualSearchViewModel`.

import XCTest
@testable import LuminaVaultClient

@MainActor
final class VisualSearchViewModelTests: XCTestCase {
    var ocr: MockImageOCRService!
    var client: MockMemoryQueryClient!
    var telemetry: MockTelemetry!
    var sut: VisualSearchViewModel!

    private let samplePNG: Data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    override func setUp() async throws {
        try await super.setUp()
        ocr = MockImageOCRService()
        client = MockMemoryQueryClient()
        telemetry = MockTelemetry()
        sut = VisualSearchViewModel(ocr: ocr, client: client, telemetry: telemetry, resultLimit: 10)
    }

    // MARK: - Happy path

    func testRunSearchHappyPathAdvancesToResults() async {
        ocr.scriptedResult = .success("Hermes by Lewis Hyde")
        client.queryResult = .success(.stubTwoHits)

        await sut.runSearch(imageData: samplePNG)

        if case let .results(response, extractedText) = sut.state {
            XCTAssertEqual(response, QueryResponse.stubTwoHits)
            XCTAssertEqual(extractedText, "Hermes by Lewis Hyde")
        } else {
            XCTFail("expected results state, got \(sut.state)")
        }
        XCTAssertEqual(sut.lastExtractedText, "Hermes by Lewis Hyde")
        XCTAssertEqual(client.calls.count, 1)
        XCTAssertEqual(client.calls.first?.text, "Hermes by Lewis Hyde")
        XCTAssertEqual(client.calls.first?.limit, 10)
    }

    func testTelemetrySequenceOnHappyPath() async {
        ocr.scriptedResult = .success("ocr-text")
        client.queryResult = .success(.stubTwoHits)
        await sut.runSearch(imageData: samplePNG)
        XCTAssertEqual(
            telemetry.eventNames,
            [
                VisualSearchViewModel.Event.imagePicked,
                VisualSearchViewModel.Event.ocrSucceeded,
                VisualSearchViewModel.Event.querySucceeded,
            ],
        )
    }

    // MARK: - OCR failure stops the pipeline

    func testOCRFailureStopsBeforeQuery() async {
        ocr.scriptedResult = .failure(ImageOCRService.OCRError.noTextFound)
        await sut.runSearch(imageData: samplePNG)
        if case let .error(message) = sut.state {
            XCTAssertEqual(message, "No readable text in the image.")
        } else {
            XCTFail("expected error state")
        }
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertEqual(
            telemetry.eventNames,
            [VisualSearchViewModel.Event.imagePicked, VisualSearchViewModel.Event.ocrFailed],
        )
    }

    // MARK: - Query failure preserves OCR result for retry

    func testQueryFailureKeepsExtractedTextForRetry() async {
        ocr.scriptedResult = .success("ocr-text")
        client.queryResult = .failure(APIError.httpError(statusCode: 503, data: Data()))
        await sut.runSearch(imageData: samplePNG)
        if case .error = sut.state {} else { XCTFail("expected error state") }
        XCTAssertEqual(sut.lastExtractedText, "ocr-text")
        XCTAssertEqual(
            telemetry.eventNames,
            [
                VisualSearchViewModel.Event.imagePicked,
                VisualSearchViewModel.Event.ocrSucceeded,
                VisualSearchViewModel.Event.queryFailed,
            ],
        )
    }

    // MARK: - Empty data short-circuits

    func testEmptyImageDataShortCircuitsToError() async {
        await sut.runSearch(imageData: Data())
        if case let .error(message) = sut.state {
            XCTAssertEqual(message, "Couldn't read that image.")
        } else {
            XCTFail("expected error state")
        }
        XCTAssertEqual(ocr.calls, 0)
        XCTAssertTrue(client.calls.isEmpty)
        XCTAssertEqual(
            telemetry.eventNames,
            [VisualSearchViewModel.Event.imagePicked, VisualSearchViewModel.Event.ocrFailed],
        )
    }

    // MARK: - Retry path

    func testRetryQuerySucceedsWithoutReOCR() async {
        ocr.scriptedResult = .success("ocr-text")
        client.queryResult = .failure(APIError.httpError(statusCode: 503, data: Data()))
        await sut.runSearch(imageData: samplePNG)

        client.queryResult = .success(.stubTwoHits)
        await sut.retryQuery()

        XCTAssertEqual(ocr.calls, 1) // OCR not re-run
        XCTAssertEqual(client.calls.count, 2)
        if case let .results(_, extractedText) = sut.state {
            XCTAssertEqual(extractedText, "ocr-text")
        } else {
            XCTFail("expected results state")
        }
    }

    func testRetryQueryIsNoOpWhenNoExtractedText() async {
        await sut.retryQuery()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(client.calls.isEmpty)
    }

    // MARK: - Reset hygiene

    func testResetReturnsToIdleAndClearsExtractedText() async {
        ocr.scriptedResult = .success("ocr-text")
        client.queryResult = .success(.stubTwoHits)
        await sut.runSearch(imageData: samplePNG)
        sut.reset()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.lastExtractedText, "")
    }

    // MARK: - Telemetry event-name contract

    func testTelemetryEventNamesMatchSpec() {
        XCTAssertEqual(VisualSearchViewModel.Event.imagePicked, "visualsearch.image_picked")
        XCTAssertEqual(VisualSearchViewModel.Event.ocrSucceeded, "visualsearch.ocr_succeeded")
        XCTAssertEqual(VisualSearchViewModel.Event.ocrFailed, "visualsearch.ocr_failed")
        XCTAssertEqual(VisualSearchViewModel.Event.querySucceeded, "visualsearch.query_succeeded")
        XCTAssertEqual(VisualSearchViewModel.Event.queryFailed, "visualsearch.query_failed")
    }
}
