// LuminaVaultClient/LuminaVaultClient/Features/Chat/Components/AgentTerminalView.swift
//
// The agent's terminal under an escalated turn: what it ran and what it
// printed. Read-only by construction — there is no input, and nothing here
// can reach a shell. It renders what the run feed already carries.
//
// Opens in place the first time a command appears, unless the reader has
// already chosen. That is not navigation or focus: it is this block showing
// what the agent is already doing on the page.

import SwiftUI

struct AgentTerminalView: View {
    @Environment(\.lvPalette) private var palette

    let entries: [AgentTerminalEntry]
    let isRunning: Bool

    @State private var isExpanded = false
    @State private var userToggled = false

    private var commandCount: Int {
        entries.filter { if case .command = $0 { true } else { false } }.count
    }

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isExpanded {
                    transcript
                }
            }
            .background(RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous).fill(palette.surface))
            .clipShape(.rect(cornerRadius: LVRadius.md, style: .continuous))
            .onAppear { openIfUntouched() }
            .onChange(of: entries.count) { _, _ in openIfUntouched() }
        }
    }

    private func openIfUntouched() {
        if !userToggled, !entries.isEmpty { isExpanded = true }
    }

    private var header: some View {
        HStack(spacing: LVSpacing.sm) {
            Button {
                isExpanded.toggle()
                userToggled = true
            } label: {
                HStack(spacing: LVSpacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Image(systemName: "apple.terminal")
                        .font(.caption)
                    Text("Terminal").font(.caption.weight(.semibold))
                    Text("· \(commandCount) \(commandCount == 1 ? "command" : "commands")")
                        .font(.caption)
                        .monospacedDigit()
                }
                .foregroundStyle(palette.textSecondary)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Terminal, \(commandCount) commands\(isRunning ? ", still running" : "")")
            .accessibilityHint(isExpanded ? "Collapses the terminal" : "Expands the terminal")

            Spacer(minLength: 0)

            Button {
                UIPasteboard.general.string = Self.plainText(entries)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy terminal output")
        }
        .padding(.leading, LVSpacing.md)
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LVSpacing.sm) {
                ForEach(entries) { entry in
                    row(entry)
                }
                Color.clear.frame(height: 1).id("terminal-bottom")
            }
            .padding(LVSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Follows new output while the reader is at the bottom, and leaves
        // them alone once they have scrolled up to read.
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: 320)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ entry: AgentTerminalEntry) -> some View {
        switch entry {
        case let .command(command):
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Text("$ ").foregroundStyle(.green))\(command.command)\(command.background ? " &" : "")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white)
                if let output = command.output {
                    if command.outputTruncated {
                        Text("… earlier output trimmed").font(.caption2.italic()).foregroundStyle(.gray)
                    }
                    if !output.isEmpty {
                        Text(output).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white)
                    }
                    if let code = command.exitCode, code != 0 {
                        Text("exit \(code)").font(.caption2).foregroundStyle(.red)
                    } else if command.failed {
                        Text("failed").font(.caption2).foregroundStyle(.red)
                    }
                } else {
                    Text("…").font(.caption2).foregroundStyle(.gray)
                        .accessibilityLabel("Running")
                }
            }
        case let .process(process):
            VStack(alignment: .leading, spacing: 2) {
                Text("background · \(process.processID)").font(.caption2).foregroundStyle(.gray)
                Text(process.output).font(.system(.caption2, design: .monospaced)).foregroundStyle(.white)
                if process.truncated {
                    Text("… output stopped at the run's limit").font(.caption2.italic()).foregroundStyle(.gray)
                }
            }
            .padding(.leading, LVSpacing.sm)
            .overlay(alignment: .leading) { Rectangle().fill(.gray).frame(width: 1) }
        }
    }

    static func plainText(_ entries: [AgentTerminalEntry]) -> String {
        entries.map { entry in
            switch entry {
            case let .command(command): "$ \(command.command)\n\(command.output ?? "")"
            case let .process(process): "[\(process.processID)]\n\(process.output)"
            }
        }
        .joined(separator: "\n")
    }
}
