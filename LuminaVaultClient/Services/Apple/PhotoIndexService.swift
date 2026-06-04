// LuminaVaultClient/LuminaVaultClient/Services/Apple/PhotoIndexService.swift
//
// Apple Photos derived-text index — incremental on-device scan.
//
// Walks the user's Photos library (screenshots + recent images first), derives
// OCR text (`ImageOCRService` / `VNRecognizeTextRequest`) and scene tags
// (`VNClassifyImageRequest`) ON DEVICE, then pushes ONLY that derived text +
// metadata to `POST /v1/photos/index`. PRIVACY-CRITICAL: pixels never leave
// the device — `PhotoIndexInput` has no image field by construction.
//
// De-dup: each processed `PHAsset.localIdentifier` is remembered in
// UserDefaults so re-runs only touch new assets. An actor serialises scans so
// overlapping triggers (launch + foreground) can't double-process.

import Foundation
import OSLog
import Photos
import UIKit
import Vision

private let log = Logger(subsystem: "com.luminavault", category: "photos.index")

actor PhotoIndexService {
    private let client: BaseHTTPClient
    private let ocr: any ImageOCRServiceProtocol
    private let defaults: UserDefaults

    /// How many assets to OCR per scan invocation. Keeps each pass bounded so a
    /// large library is indexed across several launches instead of one stall.
    private let perScanBudget: Int
    /// How many items to send per network batch.
    private let batchSize: Int
    /// Scene-tag confidence floor + how many top labels to keep.
    private let sceneConfidence: Float = 0.25
    private let maxSceneTags = 4
    /// Max OCR characters retained per asset (defensive bound on payload size).
    private let maxOCRChars = 4000

    private var isScanning = false

    private static let syncedKey = "photoIndex.syncedAssetIDs.v1"

    init(
        client: BaseHTTPClient,
        ocr: any ImageOCRServiceProtocol = ImageOCRService(),
        defaults: UserDefaults = .standard,
        perScanBudget: Int = 60,
        batchSize: Int = 20,
    ) {
        self.client = client
        self.ocr = ocr
        self.defaults = defaults
        self.perScanBudget = perScanBudget
        self.batchSize = batchSize
    }

    // MARK: - Public entry

    /// Requests Photos read access then runs one bounded incremental scan.
    /// Safe to call repeatedly; overlapping calls after the first no-op until
    /// the in-flight scan finishes. Caller is responsible for the `.photos`
    /// consent gate (see `PhotoIndexCoordinator`).
    func scanIfAuthorized() async {
        guard !isScanning else { return }
        let status = await Self.requestReadAuthorization()
        guard status == .authorized || status == .limited else {
            log.info("photos index skipped — authorization=\(status.rawValue)")
            return
        }
        isScanning = true
        defer { isScanning = false }
        await runScan()
    }

    // MARK: - Scan

    private func runScan() async {
        var persisted = Set(defaults.stringArray(forKey: Self.syncedKey) ?? [])
        let assets = fetchCandidateAssets(excluding: persisted, budget: perScanBudget)
        guard !assets.isEmpty else {
            log.info("photos index up to date — no new assets")
            return
        }

        var batch: [PhotoIndexInput] = []
        var batchIDs: [String] = []
        var pushedTotal = 0

        for asset in assets {
            batch.append(await deriveInput(for: asset))
            batchIDs.append(asset.localIdentifier)

            if batch.count >= batchSize {
                pushedTotal += await flush(&batch, ids: &batchIDs, persisted: &persisted)
            }
        }
        if !batch.isEmpty {
            pushedTotal += await flush(&batch, ids: &batchIDs, persisted: &persisted)
        }
        log.info("photos index scan complete — pushed \(pushedTotal) items, \(persisted.count) total tracked")
    }

    /// POSTs a batch. Only the ids the server actually ACCEPTED are unioned into
    /// the persisted synced-set — a failed batch's ids stay out so the next scan
    /// retries them (the previous version persisted the whole set on any later
    /// success, silently dropping failed-batch assets forever).
    private func flush(_ batch: inout [PhotoIndexInput], ids: inout [String], persisted: inout Set<String>) async -> Int {
        let items = batch
        let acceptedIDs = ids
        batch.removeAll(keepingCapacity: true)
        ids.removeAll(keepingCapacity: true)
        guard !items.isEmpty else { return 0 }
        do {
            let resp = try await client.execute(PhotoIndexEndpoints.Index(items: items))
            persisted.formUnion(acceptedIDs)
            persist(persisted)
            log.info("photos index batch ok — inserted=\(resp.inserted) updated=\(resp.updated) skipped=\(resp.skipped)")
            return resp.inserted + resp.updated
        } catch {
            log.error("photos index batch failed: \(error.localizedDescription)")
            return 0
        }
    }

    private func persist(_ synced: Set<String>) {
        defaults.set(Array(synced), forKey: Self.syncedKey)
    }

    // MARK: - Asset selection

    /// Screenshots first (highest recall value), then recent images. Excludes
    /// already-synced ids and caps at `budget` so each pass is bounded.
    private func fetchCandidateAssets(excluding synced: Set<String>, budget: Int) -> [PHAsset] {
        var picked: [PHAsset] = []
        var seen = Set<String>()

        func collect(_ fetch: PHFetchResult<PHAsset>) {
            fetch.enumerateObjects { asset, _, stop in
                let id = asset.localIdentifier
                if synced.contains(id) || seen.contains(id) { return }
                seen.insert(id)
                picked.append(asset)
                if picked.count >= budget { stop.pointee = true }
            }
        }

        // 1) Screenshots.
        let shotOpts = PHFetchOptions()
        shotOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        shotOpts.predicate = NSPredicate(
            format: "(mediaSubtypes & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue,
        )
        collect(PHAsset.fetchAssets(with: .image, options: shotOpts))

        // 2) Recent images (fills the remaining budget).
        if picked.count < budget {
            let recentOpts = PHFetchOptions()
            recentOpts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            recentOpts.fetchLimit = budget * 3 // over-fetch; dedup trims to budget
            collect(PHAsset.fetchAssets(with: .image, options: recentOpts))
        }
        return picked
    }

    // MARK: - Derivation

    private func deriveInput(for asset: PHAsset) async -> PhotoIndexInput {
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        // `renderAsset` resolves the UIImage on the main actor and hands back
        // only Sendable bytes/CGImage so nothing MainActor-isolated crosses
        // into this actor.
        let rendered = await Self.renderAsset(asset)

        var ocrText: String?
        var sceneTags: [String]?
        if let data = rendered.jpegData {
            if let text = try? await ocr.extractText(from: data, locale: nil), !text.isEmpty {
                ocrText = String(text.prefix(maxOCRChars))
            }
        }
        if let cg = rendered.cgImage {
            // Async Vision API — runs off this actor naturally, no manual offload.
            sceneTags = await Self.classifyScene(cgImage: cg, confidence: sceneConfidence, maxTags: maxSceneTags)
        }

        return PhotoIndexInput(
            assetLocalID: asset.localIdentifier,
            takenAt: asset.creationDate,
            isScreenshot: isScreenshot,
            ocrText: ocrText,
            sceneTags: (sceneTags?.isEmpty == false) ? sceneTags : nil,
        )
    }

    /// On-device scene classification (iOS 18+ async Vision). Returns the top
    /// labels above the confidence floor (bare label names).
    nonisolated static func classifyScene(cgImage: CGImage, confidence: Float, maxTags: Int) async -> [String] {
        let request = ClassifyImageRequest()
        do {
            let observations = try await request.perform(on: cgImage)
            return observations
                .filter { $0.confidence >= confidence }
                .prefix(maxTags)
                .map { $0.identifier }
        } catch {
            return []
        }
    }

    // MARK: - Photos plumbing

    nonisolated static func requestReadAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Sendable derived representation of a fetched asset. `UIImage` is
    /// MainActor-isolated on the modern SDK, so we extract the bytes + CGImage
    /// on the main actor and only ever hand these Sendable values back to the
    /// (background) PhotoIndexService actor.
    struct RenderedAsset: Sendable {
        let jpegData: Data?
        let cgImage: CGImage?
    }

    /// Loads the asset's image on the main actor and returns Sendable JPEG
    /// bytes (for OCR) + CGImage (for scene classification).
    @MainActor
    static func renderAsset(_ asset: PHAsset) async -> RenderedAsset {
        let image: UIImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat // single callback
            // Index pass derives text from an on-device thumbnail only — don't
            // pull full-res originals down from iCloud (data + battery).
            opts.isNetworkAccessAllowed = false
            opts.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1280, height: 1280),
                contentMode: .aspectFit,
                options: opts,
            ) { img, _ in cont.resume(returning: img) }
        }
        guard let image else { return RenderedAsset(jpegData: nil, cgImage: nil) }
        // JPEG keeps the in-memory OCR payload small; OCR doesn't need lossless.
        let data = image.jpegData(compressionQuality: 0.85) ?? image.pngData()
        return RenderedAsset(jpegData: data, cgImage: image.cgImage)
    }
}
