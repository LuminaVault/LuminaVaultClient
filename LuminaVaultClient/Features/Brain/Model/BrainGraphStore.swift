// Loads the one graph across all of the user's vaults and decides WHEN to ask.
// A port of the web app's `brain-graph-view-model.svelte.ts`: the server allows
// about 10 graph requests a minute on the free tier, so the store debounces,
// cancels superseded requests, keeps the graph on screen when a refresh fails
// and says when what is shown is stale.
//
// `sync` is the one entry point. The Task that loads is owned by the store and
// cancelled when superseded (cancellation reaches URLSession through the
// client); it is never spawned from a view body.

import Foundation
import LuminaVaultShared
import Observation

nonisolated enum BrainGraphLoadState: Sendable {
    case loading
    case loaded(BrainGraphResponse)
    /// 404 with a focus set.
    case missingFocus
    case failed(String)
}

/// Small, testable error predicates and copy. Same sentences as the web's
/// `friendlyLoadError`; everything else uses the app's `userFacingMessage`.
nonisolated enum BrainGraphErrors {
    /// `BaseHTTPClient` throws `.rateLimited` for a bare 429 and
    /// `.httpError(429)` when the body is a structured envelope.
    static func isRateLimited(_ error: Error) -> Bool {
        guard let api = error as? APIError else { return false }
        if case .rateLimited = api { return true }
        return api.httpStatusCode == 429
    }

    static func isNotFound(_ error: Error) -> Bool {
        (error as? APIError)?.httpStatusCode == 404
    }

    static func httpStatus(_ error: Error) -> Int? {
        (error as? APIError)?.httpStatusCode
    }

    static let rateLimitedMessage = "Too many requests. Try again in a minute."
    static let didNotLoadMessage = "The graph did not load. Try again."

    static func friendlyMessage(_ error: Error) -> String {
        // The graph limit is per minute; the app-wide 429 text talks about "today".
        if isRateLimited(error) { return rateLimitedMessage }
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return api.userFacingMessage
            }
        }
        let text = error.localizedDescription
        return text.isEmpty ? "Couldn't load." : text
    }
}

@MainActor
@Observable
final class BrainGraphStore {
    /// The free tier allows about 10 graph requests a minute; refetches wait this long.
    static let debounce: Duration = .milliseconds(400)
    /// A graph on screen is fetched again when the screen comes back to it at
    /// least this long after the last request was sent.
    static let refreshAge: TimeInterval = 60

    private(set) var state: BrainGraphLoadState = .loading
    /// True while a refetch runs with a graph already on screen.
    private(set) var refreshing = false
    /// Set on a 429, cleared by the next request that completes without one.
    private(set) var rateLimited = false
    /// A refetch over a shown graph failed with something other than a 429 or a
    /// focus 404. The graph stays; this holds the friendly message until the
    /// next completed request that is not such a failure.
    private(set) var refreshError: String?
    /// The HTTP status behind `.failed`, when there was one.
    private(set) var failureStatus: Int?
    /// The last request sent (or handed back to `sync` as what is on screen).
    private(set) var request = BrainGraphRequest()
    /// The request behind the graph on screen; nil until one loads.
    private(set) var loaded: BrainGraphRequest?
    /// True while a scheduled load waits out its debounce.
    private(set) var pending = false
    /// Counts the responses that have landed. A new response is new even when
    /// its counts and `generatedAt` match the one before, so the screen keys
    /// its derivation on this rather than on the response's contents.
    private(set) var loadSerial = 0
    /// Every vault of the first unfiltered response; until then, every vault seen.
    private(set) var knownVaults: [BrainGraphVaultDTO] = []

    @ObservationIgnored private let client: any BrainGraphClientProtocol
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let refreshAge: TimeInterval
    @ObservationIgnored private var sawAllVaults = false
    @ObservationIgnored private var started = false
    /// The newest request asked for; what `retry` loads.
    @ObservationIgnored private var wanted = BrainGraphRequest()
    @ObservationIgnored private var seq = 0
    @ObservationIgnored private var debounceToken = 0
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The request whose load is running right now; nil once it has landed,
    /// failed, or been abandoned. `loadTask` itself is not cleared on completion.
    @ObservationIgnored private var inFlight: BrainGraphRequest?
    /// When the last request was sent.
    @ObservationIgnored private var lastSentAt: Date?

    init(
        client: any BrainGraphClientProtocol,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await ContinuousClock().sleep(for: $0) },
        now: @escaping () -> Date = { Date() },
        refreshAge: TimeInterval = BrainGraphStore.refreshAge
    ) {
        self.client = client
        self.sleep = sleep
        self.now = now
        self.refreshAge = refreshAge
    }

    /// A graph is on screen but the request asked for since was refused or
    /// failed, so the controls describe something else.
    var stale: Bool {
        guard !refreshing, !pending, case .loaded = state else { return false }
        return !Self.same(loaded, request)
    }

    /// When the shown response was cut at the 800-item window: how many notes
    /// and memories it holds. Nil otherwise.
    var truncatedCount: Int? {
        guard case .loaded(let graph) = state, graph.truncated else { return nil }
        return graph.nodes.filter { $0.kind == .note || $0.kind == .memory }.count
    }

    /// The page's one entry point. The first call loads at once; later ones
    /// wait out the debounce. Back to the graph on screen asks nothing and drops
    /// whatever was on its way. A missing focus or a failure is not a graph on
    /// screen, so after either any request fetches.
    func sync(_ req: BrainGraphRequest) {
        wanted = req
        if !started {
            started = true
            startLoad(req)
            return
        }
        if case .loaded = state, Self.same(loaded, req) {
            cancelTimer()
            if refreshing { abandon() }
            refreshing = false
            request = req
            return
        }
        // This very request is already on its way: asking again would only
        // cancel it and spend another of the ~10 requests a minute.
        if let inFlight, Self.same(inFlight, req) {
            cancelTimer()
            return
        }
        schedule(req)
    }

    /// Loads the newest request now, unless that request is already in flight
    /// (then its Task is returned and nothing is sent).
    @discardableResult
    func retry() -> Task<Void, Never> {
        if let inFlight, Self.same(inFlight, wanted), let loadTask {
            cancelTimer()
            return loadTask
        }
        return startLoad(wanted)
    }

    /// Fetches the graph on screen again when the last request was sent at
    /// least `refreshAge` ago: the screen calls this when it comes back (tab
    /// selected, app in the foreground). Age counts from the last request
    /// sent, not the last that landed, so a refused or failed refresh waits
    /// another `refreshAge` too and the ~10 a minute are never spent on this.
    /// Nothing while a request is in flight or scheduled, and nothing without
    /// a graph on screen (a failure has its own Retry). Returns whether it asked.
    @discardableResult
    func refreshIfStale() -> Bool {
        guard case .loaded = state, inFlight == nil, !pending, let sent = lastSentAt,
              now().timeIntervalSince(sent) >= refreshAge else { return false }
        startLoad(wanted)
        return true
    }

    /// Fetches now and returns when this load is over (or superseded).
    /// Cancelling the caller does not cancel the load: it runs in the store's
    /// own Task and is cancelled only by a newer request, `sync` or `dispose`.
    func load(_ req: BrainGraphRequest) async {
        await startLoad(req).value
    }

    /// Fetches now in a Task the store owns. A response that lands after a newer
    /// request started is dropped.
    @discardableResult
    func startLoad(_ req: BrainGraphRequest) -> Task<Void, Never> {
        cancelTimer()
        started = true
        wanted = req
        request = req
        let mine = abandon()
        let previous = state
        if case .loaded = state {
            refreshing = true
        } else {
            state = .loading
        }
        inFlight = req
        lastSentAt = now()
        let task = Task { await self.perform(req, token: mine, previous: previous) }
        loadTask = task
        return task
    }

    /// Debounced load: calls inside the window coalesce into one with the last arguments.
    func schedule(_ req: BrainGraphRequest) {
        cancelTimer()
        wanted = req
        pending = true
        let token = debounceToken
        let sleep = self.sleep
        debounceTask = Task {
            do { try await sleep(Self.debounce) } catch { return }
            guard !Task.isCancelled, token == self.debounceToken else { return }
            self.pending = false
            self.debounceTask = nil
            if case .loaded = self.state, Self.same(self.loaded, req) {
                self.request = req
                return
            }
            self.startLoad(req)
        }
    }

    /// Drops a scheduled load that has not started; one already in flight still lands.
    func cancel() {
        cancelTimer()
    }

    /// Nothing in flight or scheduled writes anything afterwards.
    func dispose() {
        cancelTimer()
        abandon()
    }

    /// Returns when no debounce is waiting and no load is running. For tests.
    func waitUntilIdle() async {
        while true {
            if let task = debounceTask {
                await task.value
                if debounceTask == task { debounceTask = nil }
            } else if let task = loadTask {
                await task.value
                if loadTask == task { loadTask = nil }
            } else {
                return
            }
        }
    }

    // MARK: private

    private func perform(_ req: BrainGraphRequest, token: Int, previous: BrainGraphLoadState) async {
        do {
            let graph = try await client.fetchGraph(req)
            guard token == seq else { return }
            inFlight = nil
            state = .loaded(graph)
            loadSerial += 1
            loaded = req
            rateLimited = false
            refreshError = nil
            failureStatus = nil
            refreshing = false
            learnVaults(graph.vaults, unfiltered: req.vaults?.isEmpty ?? true)
        } catch {
            guard token == seq else { return }
            inFlight = nil
            refreshing = false
            // A cancel that is neither a supersession nor a dispose can only come
            // from the transport (session invalidation, URLError.cancelled).
            // Put back what was there; but `.loading` would spin forever with
            // nothing running, so a first load becomes a retryable failure.
            if error.isBenignCancellation {
                if case .loading = previous {
                    state = .failed(BrainGraphErrors.didNotLoadMessage)
                    failureStatus = nil
                } else {
                    state = previous
                }
                return
            }
            refreshError = nil
            rateLimited = BrainGraphErrors.isRateLimited(error)
            if rateLimited {
                // Keep whatever is on screen; only an empty screen turns into an error.
                if case .loaded = state { return }
            } else if BrainGraphErrors.isNotFound(error), !(req.focus ?? "").isEmpty {
                state = .missingFocus
                failureStatus = nil
                return
            } else if case .loaded = state {
                refreshError = BrainGraphErrors.friendlyMessage(error)
                return
            }
            state = .failed(BrainGraphErrors.friendlyMessage(error))
            failureStatus = BrainGraphErrors.httpStatus(error)
        }
    }

    /// Two requests are the same when they would ask the server the same thing.
    private static func same(_ a: BrainGraphRequest?, _ b: BrainGraphRequest) -> Bool {
        guard let a else { return false }
        return a.query == b.query
    }

    /// Sorted by name (case- and accent-insensitive, like the web's localeCompare) then id, so chips and vault colours do
    /// not depend on what loaded first.
    private static func sorted(_ vaults: [BrainGraphVaultDTO]) -> [BrainGraphVaultDTO] {
        vaults.sorted { a, b in
            switch a.name.localizedStandardCompare(b.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.id.uuidString < b.id.uuidString
            }
        }
    }

    private func learnVaults(_ vaults: [BrainGraphVaultDTO], unfiltered: Bool) {
        if sawAllVaults { return }
        if unfiltered {
            sawAllVaults = true
            knownVaults = Self.sorted(vaults)
            return
        }
        let fresh = vaults.filter { v in !knownVaults.contains { $0.id == v.id } }
        if !fresh.isEmpty { knownVaults = Self.sorted(knownVaults + fresh) }
    }

    /// Drops the request in flight, if any; returns the new sequence number.
    @discardableResult
    private func abandon() -> Int {
        loadTask?.cancel()
        loadTask = nil
        inFlight = nil
        seq += 1
        return seq
    }

    private func cancelTimer() {
        debounceTask?.cancel()
        debounceTask = nil
        debounceToken += 1
        pending = false
    }
}
