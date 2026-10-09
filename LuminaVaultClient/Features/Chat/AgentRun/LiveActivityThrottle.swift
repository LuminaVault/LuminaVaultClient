// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/LiveActivityThrottle.swift
//
// Coalesces trail churn. A run can emit a progress row several times a
// second; the lock screen needs a fraction of that, and ActivityKit budgets
// updates.

import Foundation

/// Decides when a new content state goes out. Pure: the clock is passed in.
struct LiveActivityThrottle {
    enum Decision: Equatable {
        /// Send now.
        case send
        /// Hold it and send after this many seconds, unless a newer state
        /// replaces it first (the newest pending state always wins).
        case later(TimeInterval)
        /// Identical to what is already on screen (or already pending).
        case drop
    }

    let minimumInterval: TimeInterval
    private(set) var lastSent: AgentRunAttributes.ContentState?
    private(set) var lastSentAt: Date?
    private(set) var pending: AgentRunAttributes.ContentState?

    init(minimumInterval: TimeInterval = 1.5) {
        self.minimumInterval = minimumInterval
    }

    mutating func offer(_ state: AgentRunAttributes.ContentState, at now: Date) -> Decision {
        if state == lastSent {
            // A newer pending state was superseded by one equal to what is
            // showing: nothing needs to go out.
            pending = nil
            return .drop
        }
        if state == pending { return .drop }
        guard let lastSentAt else {
            markSent(state, at: now)
            return .send
        }
        let elapsed = now.timeIntervalSince(lastSentAt)
        if elapsed >= minimumInterval {
            markSent(state, at: now)
            return .send
        }
        pending = state
        return .later(minimumInterval - elapsed)
    }

    /// The deferred send fired. Returns the state to send, if still wanted.
    mutating func flush(at now: Date) -> AgentRunAttributes.ContentState? {
        guard let pending else { return nil }
        markSent(pending, at: now)
        return pending
    }

    mutating func markSent(_ state: AgentRunAttributes.ContentState, at now: Date) {
        lastSent = state
        lastSentAt = now
        pending = nil
    }
}
