import Foundation
import OSLog

private let backgroundUploadLog = Logger(subsystem: "com.luminavault", category: "ingestion.background")

@MainActor
final class BackgroundIngestionUploader: NSObject, URLSessionTaskDelegate, URLSessionDelegate {
    static let shared = BackgroundIngestionUploader()
    static let sessionIdentifier = "com.luminavault.ingestion.uploads"

    struct Job: Codable, Sendable, Identifiable {
        enum Phase: String, Codable, Sendable { case chunks, completing }

        let id: UUID
        let batchID: UUID
        let itemID: UUID
        let stagedPath: String
        let bookmark: Data?
        let size: Int64
        let chunkSize: Int
        var offset: Int64
        var phase: Phase
        var attempts: Int
    }

    private var jobs: [UUID: Job] = [:]
    private var tokenProvider: (@Sendable () async -> String?)?
    private var backgroundCompletionHandler: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    override private init() {
        super.init()
        jobs = Self.loadJobs()
    }

    func configure(tokenProvider: @escaping @Sendable () async -> String?) {
        self.tokenProvider = tokenProvider
        _ = session
        Task { await resumePendingJobs() }
    }

    func enqueue(fileURL: URL, itemID: UUID, batch: IngestionBatchDTO) async throws {
        guard let item = batch.items.first(where: { $0.id == itemID }), let size = item.sizeBytes else { return }
        let directory = try Self.stagingDirectory()
        let staged = directory.appendingPathComponent("\(itemID.uuidString)-\(fileURL.lastPathComponent)")
        let granted = fileURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        try FileManager.default.copyItem(at: fileURL, to: staged)
        let bookmark = try? fileURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let aligned = item.uploadedBytes - (item.uploadedBytes % Int64(batch.chunkSizeBytes))
        let job = Job(
            id: UUID(), batchID: batch.id, itemID: itemID, stagedPath: staged.path,
            bookmark: bookmark, size: size, chunkSize: batch.chunkSizeBytes,
            offset: aligned, phase: .chunks, attempts: 0
        )
        jobs[job.id] = job
        try persist()
        try await schedule(jobID: job.id)
    }

    func handleEventsCompletion(_ completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    private func resumePendingJobs() async {
        let tasks = await session.allTasks
        let active = Set(tasks.compactMap(\.taskDescription).compactMap(UUID.init(uuidString:)))
        for id in jobs.keys where !active.contains(id) {
            do { try await schedule(jobID: id) }
            catch { backgroundUploadLog.error("resume failed job=\(id): \(error.localizedDescription)") }
        }
    }

    private func schedule(jobID: UUID) async throws {
        guard var job = jobs[jobID], let token = await tokenProvider?() else { return }
        var request: URLRequest
        let uploadFile: URL
        switch job.phase {
        case .chunks:
            if job.offset >= job.size {
                job.phase = .completing
                jobs[jobID] = job
                try persist()
                try await schedule(jobID: jobID)
                return
            }
            let length = min(Int64(job.chunkSize), job.size - job.offset)
            uploadFile = try Self.makeChunk(job: job, length: Int(length))
            let index = job.offset / Int64(job.chunkSize)
            request = URLRequest(url: Config.apiBaseURL.appendingPathComponent("v1/ingestions/\(job.batchID)/items/\(job.itemID)/chunks/\(index)"))
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(String(length), forHTTPHeaderField: "X-Lumina-Chunk-Length")
        case .completing:
            uploadFile = try Self.emptyUploadFile(jobID: jobID)
            request = URLRequest(url: Config.apiBaseURL.appendingPathComponent("v1/ingestions/\(job.batchID)/items/\(job.itemID)/complete"))
            request.httpMethod = "POST"
            request.setValue("0", forHTTPHeaderField: "Content-Length")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.uploadTask(with: request, fromFile: uploadFile)
        task.taskDescription = jobID.uuidString
        task.resume()
    }

    nonisolated func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let description = task.taskDescription
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let length = task.originalRequest?.value(forHTTPHeaderField: "X-Lumina-Chunk-Length").flatMap(Int64.init)
        Task { @MainActor in
            guard let description, let jobID = UUID(uuidString: description), var job = self.jobs[jobID] else { return }
            Self.removeTransientFiles(jobID: jobID)
            if error == nil, let status, 200 ..< 300 ~= status {
                if job.phase == .chunks {
                    job.offset += length ?? 0
                } else {
                    self.finish(jobID: jobID)
                    return
                }
                job.attempts = 0
            } else {
                job.attempts += 1
                backgroundUploadLog.warning("upload deferred job=\(jobID) status=\(status ?? 0) attempt=\(job.attempts)")
            }
            self.jobs[jobID] = job
            try? self.persist()
            if let status, 400 ..< 500 ~= status, status != 401, status != 429 {
                backgroundUploadLog.error("upload paused after permanent response job=\(jobID) status=\(status)")
                return
            }
            if error != nil || status == 401 || status == 429 || (status ?? 500) >= 500 {
                try? await Task.sleep(for: .seconds(min(60, 1 << min(job.attempts, 6))))
            }
            try? await self.schedule(jobID: jobID)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        Task { @MainActor in
            let completion = self.backgroundCompletionHandler
            self.backgroundCompletionHandler = nil
            completion?()
        }
    }

    private func finish(jobID: UUID) {
        guard let job = jobs.removeValue(forKey: jobID) else { return }
        try? FileManager.default.removeItem(atPath: job.stagedPath)
        try? persist()
        NotificationCenter.default.post(name: .ingestionBackgroundUploadCompleted, object: job.batchID)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(Array(jobs.values))
        try data.write(to: Self.jobsURL(), options: .atomic)
    }

    private static func loadJobs() -> [UUID: Job] {
        guard let url = try? jobsURL(), let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([Job].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    private static func stagingDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IngestionUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func jobsURL() throws -> URL {
        try stagingDirectory().appendingPathComponent("jobs.json")
    }

    private static func makeChunk(job: Job, length: Int) throws -> URL {
        let url = try stagingDirectory().appendingPathComponent("\(job.id)-\(job.offset).chunk")
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: job.stagedPath))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(job.offset))
        let data = try handle.read(upToCount: length) ?? Data()
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func emptyUploadFile(jobID: UUID) throws -> URL {
        let url = try stagingDirectory().appendingPathComponent("\(jobID)-complete")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return url
    }

    private static func removeTransientFiles(jobID: UUID) {
        guard let directory = try? stagingDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.lastPathComponent.hasPrefix(jobID.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension Notification.Name {
    static let ingestionBackgroundUploadCompleted = Notification.Name("ingestionBackgroundUploadCompleted")
}
