// LuminaVaultClient/LuminaVaultClient/Features/Chat/Preview/ChatPreviewContentModel.swift
//
// Loads whatever a preview target points at, and nothing else.
//
// Every source already exists on the server: artifacts are harvested rows,
// vault files are vault reads, and tool output is a persisted run event read
// back through the run feed. The pane stores nothing new.
//
// Responses are checked against the target they were asked for. Tap one
// artifact, then another before the first loads, and the first must not land
// on top of the second.

import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class ChatPreviewContentModel {
    enum Content: Equatable {
        case loading
        /// Text to read: a file, an artifact's value, a tool's payload.
        case text(title: String, body: String, link: URL?)
        case image(title: String, url: URL)
        /// An external page. Never loaded in-app; the user opens it.
        case link(URL)
        case failed(String)
        /// This build has no client for the target's source.
        case unavailable
    }

    private(set) var content: Content = .loading
    private(set) var loadedTarget: ChatPreviewTarget?

    private let artifacts: (any HermesArtifactsClientProtocol)?
    private let vault: (any VaultClientProtocol)?
    private let runs: (any HermesRunsClientProtocol)?

    /// Past this a text preview is cut. The pane is a glance, not an editor,
    /// and SwiftUI `Text` lays out the whole string on every render.
    static let maxCharacters = 20_000

    init(
        artifacts: (any HermesArtifactsClientProtocol)?,
        vault: (any VaultClientProtocol)?,
        runs: (any HermesRunsClientProtocol)?
    ) {
        self.artifacts = artifacts
        self.vault = vault
        self.runs = runs
    }

    func load(_ target: ChatPreviewTarget) async {
        loadedTarget = target
        content = .loading
        let result = await fetch(target)
        // A newer tap has moved the pane on; this answer is for nobody.
        guard loadedTarget == target, !Task.isCancelled else { return }
        content = result
    }

    private func fetch(_ target: ChatPreviewTarget) async -> Content {
        switch target {
        case let .url(url):
            return .link(url)

        case let .artifact(id):
            guard let artifacts else { return .unavailable }
            do {
                let artifact = try await artifacts.get(id: id)
                let href = URL(string: artifact.href)
                if artifact.kind == .image, let href {
                    return .image(title: artifact.label, url: href)
                }
                return .text(title: artifact.label, body: artifact.value, link: href)
            } catch {
                return .failed("Couldn't load this artifact.")
            }

        case let .vaultFile(path):
            guard let vault else { return .unavailable }
            do {
                let (data, _) = try await vault.readFile(relativePath: path)
                guard let text = String(data: data, encoding: .utf8) else {
                    return .failed("This file isn't text, so it can't be previewed here.")
                }
                return .text(title: target.label, body: Self.clip(text), link: nil)
            } catch {
                return .failed("Couldn't read this file.")
            }

        case let .toolOutput(runID, seq):
            guard let runs, let uuid = UUID(uuidString: runID) else { return .unavailable }
            do {
                // Replay from just before the row and stop at it. The feed
                // replays persisted rows first, so this is one short read.
                for try await event in runs.events(uuid, after: max(0, seq - 1)) {
                    if event.seq == seq {
                        return .text(title: event.event, body: Self.clip(Self.pretty(event.payload)), link: nil)
                    }
                    if event.seq > seq { break }
                }
                return .failed("That step is no longer in the run's history.")
            } catch {
                return .failed("Couldn't load this step.")
            }
        }
    }

    static func clip(_ text: String) -> String {
        text.count > maxCharacters ? String(text.prefix(maxCharacters)) + "\n…[truncated]" : text
    }

    static func pretty(_ value: AnyJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}
