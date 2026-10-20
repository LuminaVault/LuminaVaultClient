// LuminaVaultClient/LuminaVaultClient/Features/Brief/BriefViewModel.swift
//
// The daily brief as cards with an end: a short list in the server's order,
// each with a why line and 👍 / 👎 / dismiss, then "That's it for today."
//
// Reactions are optimistic. 👍 / 👎 light up at once and go back to what
// they were if the server says no; dismiss takes the card away at once and
// puts it back where it was, with an inline error, on failure.
//
// The Open loops card names its commitments by ref. Their Done / Drop needs
// the commitments themselves, so the open ones are read alongside the brief
// and matched to the card's refs; answering one takes it off the card
// straight away and puts it back on failure, like a dismiss.
//
// One instance backs both Home's "Your brief" row and the sheet it opens, so
// a dismiss in the sheet takes one off the row's count too.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class BriefViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// A card reaction that did not land: which card, and why.
    struct CardFailure: Equatable {
        let cardID: String
        let message: String
    }

    /// A Done / Drop that did not land: which commitment, and why.
    struct CommitmentFailure: Equatable {
        let commitmentID: UUID
        let message: String
    }

    private(set) var phase: Phase = .loading
    /// Nil once loaded means there is no brief for the day yet.
    private(set) var brief: BriefDTO?
    /// The cards still on screen, in the server's order.
    private(set) var cards: [BriefCardDTO] = []
    /// 👍 / 👎 per card id, as last confirmed or optimistically set.
    private(set) var reactions: [String: BriefCardFeedbackAction] = [:]
    /// Cards whose reaction is in flight.
    private(set) var pendingCardIDs: Set<String> = []
    var cardFailure: CardFailure?

    /// The open commitments the brief's cards point at, keyed by id. Nil
    /// until they have been read — a card then falls back to its body text.
    private(set) var commitmentsByID: [UUID: CommitmentDTO]?
    /// Commitments answered (or being answered) from the brief.
    private(set) var closedCommitmentIDs: Set<UUID> = []
    private(set) var pendingCommitmentIDs: Set<UUID> = []
    var commitmentFailure: CommitmentFailure?

    /// What Home's row counts.
    var count: Int {
        cards.count
    }

    /// Loaded, and the server had no brief for the day.
    var isEmpty: Bool {
        phase == .loaded && brief == nil
    }

    /// "Tuesday, October 20" — the brief's own day, or today before one exists.
    var dateText: String {
        Self.dateText(for: brief?.date, now: now(), locale: locale)
    }

    let commitmentsClient: any CommitmentsClientProtocol
    private let client: any BriefClientProtocol
    /// `yyyy-MM-dd`, or nil for today in the user's timezone.
    private let date: String?
    private let now: () -> Date
    private let locale: Locale

    init(
        client: any BriefClientProtocol,
        commitmentsClient: any CommitmentsClientProtocol,
        date: String? = nil,
        now: @escaping () -> Date = Date.init,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.client = client
        self.commitmentsClient = commitmentsClient
        self.date = date
        self.now = now
        self.locale = locale
    }

    // MARK: - Load

    /// First load, pull-to-refresh, and Home's passive read (which leaves
    /// the commitments for the sheet to read). A failed refresh keeps what
    /// is on screen.
    func load(includeCommitments: Bool = true) async {
        do {
            let response = try await client.brief(date: date)
            if brief?.id != response.brief?.id {
                reactions = [:]
                closedCommitmentIDs = []
            }
            brief = response.brief
            cards = response.brief?.cards ?? []
            phase = .loaded
        } catch {
            if case .loaded = phase { return }
            phase = .failed("Couldn't load your brief.")
            return
        }
        if includeCommitments { await loadCommitments() }
    }

    /// Reads the open commitments behind the cards' refs. Also run when the
    /// full list closes, since it can close or reopen any of them.
    func loadCommitments() async {
        guard !commitmentRefs.isEmpty else {
            commitmentsByID = [:]
            return
        }
        do {
            let open = try await commitmentsClient.commitments(state: .open).items
            commitmentsByID = Dictionary(open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // Anything reopened from the list is open again here too.
            closedCommitmentIDs.subtract(open.map(\.id))
        } catch {
            // Keep what is on screen; with nothing, the card shows its body.
        }
    }

    private var commitmentRefs: [UUID] {
        cards.flatMap(\.refs).filter { $0.kind == .commitment }.compactMap { UUID(uuidString: $0.id) }
    }

    /// The card's commitments still open, in the card's order. Nil when
    /// they could not be read, so the card shows its body text instead.
    func commitments(for card: BriefCardDTO) -> [CommitmentDTO]? {
        guard let commitmentsByID else { return nil }
        return card.refs
            .filter { $0.kind == .commitment }
            .compactMap { UUID(uuidString: $0.id) }
            .filter { !closedCommitmentIDs.contains($0) }
            .compactMap { commitmentsByID[$0] }
    }

    /// Whether a card points at commitments at all.
    func hasCommitments(_ card: BriefCardDTO) -> Bool {
        card.refs.contains { $0.kind == .commitment }
    }

    /// The memories a card can open.
    func memoryIDs(for card: BriefCardDTO) -> [UUID] {
        card.refs.filter { $0.kind == .memory }.compactMap { UUID(uuidString: $0.id) }
    }

    // MARK: - Feedback

    /// 👍 or 👎. Tapping the one already chosen does nothing: the server
    /// keeps one reaction per card and has no "clear".
    func react(_ action: BriefCardFeedbackAction, to card: BriefCardDTO) async {
        guard action != .dismiss else { return await dismiss(card) }
        guard let brief, reactions[card.id] != action, !pendingCardIDs.contains(card.id) else { return }
        let previous = reactions[card.id]
        begin(card.id)
        reactions[card.id] = action
        defer { pendingCardIDs.remove(card.id) }
        do {
            try await client.feedback(briefID: brief.id, cardID: card.id, action: action)
        } catch {
            reactions[card.id] = previous
            cardFailure = CardFailure(cardID: card.id, message: Self.failureMessage)
        }
    }

    func dismiss(_ card: BriefCardDTO) async {
        guard let brief,
              let index = cards.firstIndex(where: { $0.id == card.id }),
              !pendingCardIDs.contains(card.id)
        else { return }
        begin(card.id)
        cards.remove(at: index)
        defer { pendingCardIDs.remove(card.id) }
        do {
            try await client.feedback(briefID: brief.id, cardID: card.id, action: .dismiss)
        } catch {
            cards.insert(card, at: min(index, cards.count))
            cardFailure = CardFailure(cardID: card.id, message: Self.failureMessage)
        }
    }

    private func begin(_ cardID: String) {
        pendingCardIDs.insert(cardID)
        if cardFailure?.cardID == cardID { cardFailure = nil }
    }

    func errorMessage(forCard id: String) -> String? {
        cardFailure?.cardID == id ? cardFailure?.message : nil
    }

    // MARK: - Open loops

    func markDone(_ commitment: CommitmentDTO) async {
        await close(commitment, as: .done)
    }

    func drop(_ commitment: CommitmentDTO) async {
        await close(commitment, as: .dropped)
    }

    private func close(_ commitment: CommitmentDTO, as state: CommitmentState) async {
        guard !closedCommitmentIDs.contains(commitment.id),
              !pendingCommitmentIDs.contains(commitment.id)
        else { return }
        pendingCommitmentIDs.insert(commitment.id)
        if commitmentFailure?.commitmentID == commitment.id { commitmentFailure = nil }
        closedCommitmentIDs.insert(commitment.id)
        defer { pendingCommitmentIDs.remove(commitment.id) }
        do {
            _ = try await commitmentsClient.update(id: commitment.id, state: state)
        } catch {
            closedCommitmentIDs.remove(commitment.id)
            commitmentFailure = CommitmentFailure(
                commitmentID: commitment.id,
                message: CommitmentCopy.failureMessage(for: error)
            )
        }
    }

    func errorMessage(forCommitment id: UUID) -> String? {
        commitmentFailure?.commitmentID == id ? commitmentFailure?.message : nil
    }

    // MARK: - Copy

    nonisolated static let failureMessage = "Couldn't send that. Try again."
    nonisolated static let defaultEndNote = "That's it for today."

    /// "Tuesday, October 20". `yyyy-MM-dd` is a calendar day, not an
    /// instant, so it is parsed and formatted in one fixed zone — reading it
    /// as midnight UTC and printing it in Pacific time would show yesterday.
    nonisolated static func dateText(for day: String?, now: Date, locale: Locale) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        var style = Date.FormatStyle(locale: locale, timeZone: utc).weekday(.wide).month(.wide).day()
        if let day, let parsed = parseDay(day) {
            return parsed.formatted(style)
        }
        style.timeZone = .autoupdatingCurrent
        return now.formatted(style)
    }

    nonisolated static func parseDay(_ raw: String) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
