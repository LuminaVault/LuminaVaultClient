// The rules between the 2D canvas and its `GraphLayout2D` actor, kept pure so
// they can be tested without a view or an actor.
//
// Runs. The canvas talks to the actor only while a run is live: one `.task`
// that holds the `updates()` stream and a command channel. Runs get tokens; a
// run's teardown clears the channel only if it is still the live run, so the
// tail of an old run (a quick disappear and appear) cannot cut off a newer one.
//
// Delivery. A command queued on a run that is then cancelled may never reach
// the actor (a cancelled stream iteration does not drain its buffer). So
// nothing here trusts a queued command: every run resends the current graph,
// and a held point stays held until the actor has taken its release, which a
// new run redoes otherwise.
//
// Snapshots. The filter and the framing decisions come from what the actor
// reports, not from what was queued: a snapshot older than one already seen
// is dropped; the first snapshot of a new generation says whether the graph
// is fresh (no id seen before: back to the automatic view and frame it on
// every step) or changed which points show (frame it once it settles, while
// the view is automatic). Never framed under a point being dragged.

nonisolated struct BrainCanvasSync: Equatable, Sendable {
    /// What a new run must send before anything else, in order.
    enum Send: Equatable, Sendable {
        case release(String)
        case graph
    }

    enum Fit: Equatable, Sendable {
        case none
        /// Jump to the fitted view.
        case now
        /// Glide to it (web `CENTRE_MS`).
        case eased
    }

    /// What the view is doing when a snapshot arrives.
    struct ViewFacts: Equatable, Sendable {
        var automatic: Bool
        var dragging: Bool
        var reduceMotion: Bool
    }

    struct Received: Equatable, Sendable {
        var accept: Bool
        /// A fresh graph: the view goes back to the automatic fit.
        var resetAutomatic: Bool
        var fit: Fit

        static let dropped = Received(accept: false, resetAutomatic: false, fit: .none)
    }

    struct RunStart: Equatable, Sendable {
        var token: Int
        var sends: [Send]
    }

    /// The token of the run that may use the channel, if any.
    private(set) var liveRun: Int?
    private var runs = 0
    /// The graph key queued on the live run; nil outside a run.
    private var queuedKey: Int?
    /// A point the user pinned whose release the actor has not taken yet.
    private(set) var held: String?
    private var generation = 0
    private var known: Set<String> = []
    private var shown: Set<String> = []
    private var fitEachStep = false
    private var refitOnSettle = false

    // MARK: Runs

    /// Starts a run for the graph with `key`. It always sends the graph:
    /// whatever an earlier run queued may have been lost.
    mutating func startRun(key: Int) -> RunStart {
        runs += 1
        liveRun = runs
        queuedKey = key
        var sends: [Send] = []
        if let held { sends.append(.release(held)) }
        sends.append(.graph)
        return RunStart(token: runs, sends: sends)
    }

    /// Ends the run `token`. Returns whether it was still the live run, so
    /// its channel is the one to clear; a late teardown of an older run
    /// changes nothing.
    mutating func endRun(_ token: Int) -> Bool {
        guard liveRun == token else { return false }
        liveRun = nil
        queuedKey = nil
        return true
    }

    /// The visible graph changed to `key`: whether to queue it now (a run is
    /// live and it is not already the graph queued on it).
    mutating func graphChanged(key: Int) -> Bool {
        guard liveRun != nil, queuedKey != key else { return false }
        queuedKey = key
        return true
    }

    /// The user is holding `id` (a pin was queued).
    mutating func pinned(_ id: String) {
        held = id
    }

    /// The actor has taken the release of `id`.
    mutating func releaseDelivered(_ id: String) {
        if held == id { held = nil }
    }

    // MARK: Snapshots

    mutating func receive(_ snapshot: LayoutSnapshot, view: ViewFacts) -> Received {
        guard snapshot.generation >= generation else { return .dropped }
        var reset = false
        if snapshot.generation > generation {
            generation = snapshot.generation
            let ids = Set(snapshot.ids)
            if BrainGraphCanvasLogic.isFreshGraph(snapshot.ids, known: known) {
                known = []
                fitEachStep = true
                refitOnSettle = false
                reset = BrainGraphCanvasLogic.nextAutoView(view.automatic, .freshGraph)
            } else if ids != shown, view.automatic {
                refitOnSettle = true
            }
            known.formUnion(ids)
            shown = ids
        }
        let automatic = view.automatic || reset
        var fit = Fit.none
        if fitEachStep, automatic, !view.dragging, !snapshot.settled { fit = .now }
        if snapshot.settled {
            if fitEachStep || refitOnSettle, automatic, !view.dragging {
                // Framed every step already: finish exactly. A reheat moved
                // points under a still view: glide to the new fit.
                fit = fitEachStep || view.reduceMotion ? .now : .eased
            }
            fitEachStep = false
            refitOnSettle = false
        }
        return Received(accept: true, resetAutomatic: reset, fit: fit)
    }
}
