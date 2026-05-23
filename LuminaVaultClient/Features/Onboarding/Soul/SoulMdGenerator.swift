// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/Soul/SoulMdGenerator.swift
//
// HER-100 — builds the initial SOUL.md draft from the quiz answers.
// The user can override the output verbatim on the confirm step; this
// generator is the "best effort" starting point Hermes will read on
// every chat.
//
// Pure function (no I/O, no actor) so it's trivially unit-testable.

import Foundation

enum SoulMdGenerator {
    /// Renders the answers as Markdown. Stable section order so the
    /// confirm-step preview doesn't reflow when the user changes a
    /// single field upstream.
    static func render(_ answers: SoulQuizAnswers) -> String {
        var lines: [String] = []
        lines.append("# About me")
        lines.append("")
        lines.append("This is the personality file Hermes reads before every reply. Edit it freely.")
        lines.append("")

        lines.append("## Tone")
        lines.append("")
        if let tone = answers.tone {
            lines.append("- Speak to me in a **\(tone.label.lowercased())** voice.")
        } else {
            lines.append("- _(no preference chosen — Hermes will default to a neutral, friendly tone)_")
        }
        lines.append("")

        lines.append("## What matters to me")
        lines.append("")
        let prioritized = SoulPriority.allCases.filter { answers.priorities.contains($0) && $0 != .other }
        if prioritized.isEmpty, !answers.priorities.contains(.other) {
            lines.append("- _(no priorities chosen yet)_")
        } else {
            for priority in prioritized {
                lines.append("- \(priority.label)")
            }
            if answers.priorities.contains(.other) {
                let trimmed = answers.otherPriority.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append("- \(trimmed)")
                }
            }
        }
        lines.append("")

        lines.append("## Style")
        lines.append("")
        lines.append("- Format: **\(answers.format.label.lowercased())**")
        lines.append("- Length: **\(answers.length.label.lowercased())**")
        lines.append("- Emojis: **\(answers.emojis ? "yes" : "no")**")
        lines.append("")

        let voiceSamples = answers.voiceSamples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !voiceSamples.isEmpty {
            lines.append("## How I talk")
            lines.append("")
            lines.append("Mirror these voice samples when replying to me:")
            lines.append("")
            for sample in voiceSamples {
                let quoted = sample
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "> \($0)" }
                    .joined(separator: "\n")
                lines.append(quoted)
                lines.append("")
            }
        }

        // Trim trailing blank line for a clean final newline.
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }
}
