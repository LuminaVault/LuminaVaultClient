// LuminaVaultClient/LuminaVaultClient/Services/Apple/DeviceCommandExecutor.swift
//
// Apple Integration P0b (client) — the always-on device-RPC executor. Holds a
// persistent WebSocket to the tenant broadcast channel (/v1/ws), decodes
// `device_command` envelopes the server sends (via DeviceCommandBroker),
// executes them against the device, and POSTs the result to
// /v1/devices/command/{id}/result (resolving the server's pending request).
//
// Reconnects with a fixed backoff while running. Started by AppState once the
// user is authenticated; cancelled on sign-out. First handler is `ping`
// (round-trip proof); Apple handlers (reminder_create, …) plug into `handle`.

import EventKit
import Foundation
import LuminaVaultShared
import OSLog
import PDFKit
import Photos
import UIKit
import UniformTypeIdentifiers
import Vision

private let log = Logger(subsystem: "com.luminavault", category: "apple.device-rpc")

enum DeviceCommandEndpoints {
    struct PostResult: Endpoint {
        typealias Response = EmptyResponse
        let result: DeviceCommandResult
        var path: String { "/v1/devices/command/\(result.id.uuidString)/result" }
        var method: HTTPMethod { .post }
        var body: (any Encodable)? { result }
    }
}

actor DeviceCommandExecutor {
    private let baseURL: URL
    private let tokenProvider: @Sendable () async -> String?
    private let httpClient: BaseHTTPClient
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    private let decoder = JSONDecoder()

    init(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async -> String?,
        httpClient: BaseHTTPClient,
        session: URLSession = .shared,
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
        self.session = session
    }

    func start() {
        guard runTask == nil else { return }
        runTask = Task { await self.runLoop() }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await connectAndPump()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(5)) // reconnect backoff
        }
    }

    private func connectAndPump() async {
        guard let url = wsURL() else { return }
        let token = await tokenProvider()
        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let ws = session.webSocketTask(with: req)
        task = ws
        ws.resume()
        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                let text: String? = switch message {
                case .string(let t): t
                case .data(let d): String(data: d, encoding: .utf8)
                @unknown default: nil
                }
                if let text,
                   let data = text.data(using: .utf8),
                   let envelope = try? decoder.decode(DeviceCommandEnvelope.self, from: data),
                   envelope.type == "device_command"
                {
                    await handle(envelope.command)
                }
                // Non-matching frames (other features on /v1/ws) are ignored.
            } catch {
                log.warning("device-rpc ws receive failed: \(String(describing: error))")
                break
            }
        }
        task = nil
    }

    private func handle(_ command: DeviceCommand) async {
        let result: DeviceCommandResult
        switch command.kind {
        case .ping:
            result = DeviceCommandResult(id: command.id, ok: true, payload: ["pong": "1"])
        case .reminderCreate:
            result = await createReminder(command)
        case .calendarCreate:
            result = await createEvent(command)
        case .deviceFetch:
            result = await fetchDeviceData(command)
        case .photoAnalyze:
            // Photo handler lands in P3. Report unsupported so the server's
            // pending request resolves instead of timing out.
            result = DeviceCommandResult(id: command.id, ok: false, error: "command photo_analyze not yet supported on this device")
        }
        do {
            _ = try await httpClient.execute(DeviceCommandEndpoints.PostResult(result: result))
        } catch {
            log.warning("device-rpc result post failed id=\(command.id.uuidString): \(String(describing: error))")
        }
    }

    // MARK: - EventKit handlers (P2)

    private func createReminder(_ command: DeviceCommand) async -> DeviceCommandResult {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else {
            return DeviceCommandResult(id: command.id, ok: false, error: "Reminders permission not granted")
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            return DeviceCommandResult(id: command.id, ok: false, error: "no default Reminders list")
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = command.payload["title"] ?? "Reminder"
        reminder.calendar = calendar
        if let notes = command.payload["notes"], !notes.isEmpty { reminder.notes = notes }
        if let dueStr = command.payload["due"], !dueStr.isEmpty,
           let due = ISO8601DateFormatter().date(from: dueStr) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        }
        do {
            try store.save(reminder, commit: true)
            return DeviceCommandResult(id: command.id, ok: true, payload: ["id": reminder.calendarItemIdentifier, "title": reminder.title])
        } catch {
            return DeviceCommandResult(id: command.id, ok: false, error: "save failed: \(error.localizedDescription)")
        }
    }

    private func createEvent(_ command: DeviceCommand) async -> DeviceCommandResult {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else {
            return DeviceCommandResult(id: command.id, ok: false, error: "Calendar permission not granted")
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            return DeviceCommandResult(id: command.id, ok: false, error: "no default calendar")
        }
        let iso = ISO8601DateFormatter()
        guard let startStr = command.payload["start"], let start = iso.date(from: startStr) else {
            return DeviceCommandResult(id: command.id, ok: false, error: "invalid start date")
        }
        let event = EKEvent(eventStore: store)
        event.title = command.payload["title"] ?? "Event"
        event.calendar = calendar
        event.startDate = start
        event.endDate = (command.payload["end"].flatMap { iso.date(from: $0) }) ?? start.addingTimeInterval(3600)
        if let location = command.payload["location"], !location.isEmpty { event.location = location }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return DeviceCommandResult(id: command.id, ok: true, payload: ["id": event.eventIdentifier ?? "", "title": event.title])
        } catch {
            return DeviceCommandResult(id: command.id, ok: false, error: "save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - EventKit fresh reads (P2b)

    private func fetchDeviceData(_ command: DeviceCommand) async -> DeviceCommandResult {
        switch command.domain {
        case .calendar: return await fetchEvents(command)
        case .reminders: return await fetchReminders(command)
        case .photos: return await fetchPhotos(command)
        case .location: return await fetchLocation(command)
        case .files: return await fetchFiles(command)
        default:
            return DeviceCommandResult(id: command.id, ok: false, error: "device_fetch not supported for \(command.domain?.rawValue ?? "unknown")")
        }
    }

    // MARK: - Files (P5) — user-picked documents; only derived text leaves the
    // device. Requires the app foregrounded (the picker is interactive); if the
    // app is asleep the broker request times out and Hermes reports the device
    // as unavailable, which is the intended behaviour.

    private func fetchFiles(_ command: DeviceCommand) async -> DeviceCommandResult {
        let urls = await DocumentPickerPresenter().present()
        guard !urls.isEmpty else {
            return DeviceCommandResult(id: command.id, ok: false, error: "no files were selected")
        }
        var items: [[String: String]] = []
        for url in urls.prefix(10) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = Self.extractText(from: url)
            items.append([
                "name": url.lastPathComponent,
                "type": url.pathExtension.lowercased(),
                "chars": String(text.count),
                "text": String(text.prefix(8000)),
            ])
        }
        return Self.encodeItems(command.id, items)
    }

    /// On-device text extraction. PDFs via PDFKit, anything UTF-8-decodable as
    /// plain text. Binary/unsupported files yield empty text (metadata only).
    private static func extractText(from url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(url: url)?.string ?? ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Location (P4)

    private func fetchLocation(_ command: DeviceCommand) async -> DeviceCommandResult {
        guard let fix = await LocationService().requestFix() else {
            return DeviceCommandResult(id: command.id, ok: false, error: "location unavailable or permission not granted")
        }
        let item: [String: String] = [
            "lat": String(fix.lat),
            "lng": String(fix.lng),
            "place": fix.placeName ?? "",
            "at": ISO8601DateFormatter().string(from: Date()),
        ]
        return Self.encodeItems(command.id, [item])
    }

    // MARK: - Photos (P3) — on-device OCR; only derived text leaves the device.

    private func fetchPhotos(_ command: DeviceCommand) async -> DeviceCommandResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            return DeviceCommandResult(id: command.id, ok: false, error: "Photos permission not granted")
        }
        let limit = Int(command.payload["limit"] ?? "10") ?? 10
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in assets.append(asset) }

        let iso = ISO8601DateFormatter()
        var items: [[String: String]] = []
        for asset in assets {
            let text = await ocrText(for: asset)
            items.append([
                "takenAt": asset.creationDate.map { iso.string(from: $0) } ?? "",
                "text": String(text.prefix(2000)),
                "screenshot": asset.mediaSubtypes.contains(.photoScreenshot) ? "true" : "false",
            ])
        }
        return Self.encodeItems(command.id, items)
    }

    private func ocrText(for asset: PHAsset) async -> String {
        let image: UIImage? = await withCheckedContinuation { cont in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat // single callback
            opts.isNetworkAccessAllowed = true
            opts.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1280, height: 1280),
                contentMode: .aspectFit,
                options: opts,
            ) { img, _ in cont.resume(returning: img) }
        }
        guard let cg = image?.cgImage else { return "" }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                cont.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            do { try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request]) }
            catch { cont.resume(returning: "") }
        }
    }

    private func fetchEvents(_ command: DeviceCommand) async -> DeviceCommandResult {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else {
            return DeviceCommandResult(id: command.id, ok: false, error: "Calendar permission not granted")
        }
        let days = Int(command.payload["days"] ?? "7") ?? 7
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let iso = ISO8601DateFormatter()
        let items = store.events(matching: predicate).prefix(100).map { event in
            [
                "title": event.title ?? "",
                "start": iso.string(from: event.startDate),
                "end": iso.string(from: event.endDate),
                "location": event.location ?? "",
            ]
        }
        return Self.encodeItems(command.id, Array(items))
    }

    private func fetchReminders(_ command: DeviceCommand) async -> DeviceCommandResult {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToReminders()) == true else {
            return DeviceCommandResult(id: command.id, ok: false, error: "Reminders permission not granted")
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        let iso = ISO8601DateFormatter()
        let items = reminders.prefix(100).map { reminder -> [String: String] in
            var due = ""
            if let comps = reminder.dueDateComponents, let date = Calendar.current.date(from: comps) {
                due = iso.string(from: date)
            }
            return ["title": reminder.title ?? "", "due": due, "notes": reminder.notes ?? ""]
        }
        return Self.encodeItems(command.id, items)
    }

    private static func encodeItems(_ id: UUID, _ items: [[String: String]]) -> DeviceCommandResult {
        guard let data = try? JSONEncoder().encode(items), let json = String(data: data, encoding: .utf8) else {
            return DeviceCommandResult(id: id, ok: false, error: "encode failed")
        }
        return DeviceCommandResult(id: id, ok: true, payload: ["items": json])
    }

    // MARK: - Files document picker (P5)

    /// Presents `UIDocumentPickerViewController` from the top view controller and
    /// resolves with the picked URLs (empty if cancelled or no window). Retains
    /// itself for the lifetime of the presentation so the delegate survives.
    @MainActor
    private final class DocumentPickerPresenter: NSObject, UIDocumentPickerDelegate {
        private var continuation: CheckedContinuation<[URL], Never>?
        private var selfRef: DocumentPickerPresenter?

        func present() async -> [URL] {
            await withCheckedContinuation { cont in
                self.continuation = cont
                self.selfRef = self // keep alive until the delegate fires
                // `asCopy: true` hands us temporary local copies we can read
                // immediately, sidestepping long-lived security-scoped bookmarks.
                let picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [.pdf, .plainText, .text, .rtf, .json, .commaSeparatedText, .data],
                    asCopy: true,
                )
                picker.allowsMultipleSelection = true
                picker.delegate = self
                guard let top = Self.topViewController() else {
                    finish([])
                    return
                }
                top.present(picker, animated: true)
            }
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls)
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            finish([])
        }

        private func finish(_ urls: [URL]) {
            continuation?.resume(returning: urls)
            continuation = nil
            selfRef = nil
        }

        private static func topViewController() -> UIViewController? {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
            var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
            while let presented = top?.presentedViewController { top = presented }
            return top
        }
    }

    private func wsURL() -> URL? {
        guard var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        switch c.scheme {
        case "https": c.scheme = "wss"
        case "http": c.scheme = "ws"
        default: break
        }
        c.path += "/v1/ws"
        return c.url
    }
}
