// LuminaVaultClient/LuminaVaultClient/Features/Home/Components/HomeComposer.swift
//
// The first thing on the first screen: one field that takes whatever you have.
//
// One field rather than a mode picker. Paste a link and it is saved as a link;
// type a thought and it is saved as a note. The controls underneath are only
// for the inputs a text field genuinely cannot take.

import SwiftUI
import LuminaVaultShared

struct HomeComposer: View {
    @Environment(\.lvPalette) private var palette

    @Binding var text: String
    @FocusState.Binding var focused: Bool

    let isSaving: Bool
    /// Non-nil when the field holds nothing but a URL.
    let detectedLink: URL?
    let canSave: Bool
    let isRecording: Bool
    let recordingElapsed: TimeInterval
    /// Empty when the user has no Spaces, in which case no picker is shown —
    /// an "Unfiled" menu with nothing to choose is just clutter.
    let spaces: [SpaceDTO]
    @Binding var selectedSpaceID: UUID?
    let onSubmit: () -> Void
    let onVoice: () -> Void
    let onCancelRecording: () -> Void
    let onPhotos: () -> Void
    let onFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            TextField("What do you want to remember?", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lvFont(.body)
                .lineLimit(1...6)
                .focused($focused)
                .disabled(isSaving)
                .accessibilityLabel("What do you want to remember?")

            if isRecording {
                recordingChip
            } else if let link = detectedLink {
                linkChip(link)
            }

            HStack(spacing: LVSpacing.xs) {
                Button(action: onVoice) {
                    LVIconView(
                        isRecording ? .stopCircleFill : .micFill,
                        size: 18,
                        tint: isRecording ? palette.glowPrimary : palette.textSecondary,
                        label: isRecording ? "Stop recording" : "Record a voice note"
                    )
                    .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                    .contentShape(.rect)
                }
                .disabled(isSaving)

                affordance(.photoOnRectangleAngled, label: "Add a photo", action: onPhotos)
                affordance(.paperclip, label: "Add a file", action: onFiles)

                if !spaces.isEmpty {
                    spacePicker
                }

                Spacer(minLength: LVSpacing.sm)

                Button(action: onSubmit) {
                    LVIconView(
                        .arrowUpCircleFill,
                        size: 28,
                        tint: canSave ? palette.primary : palette.textSecondary.opacity(0.4),
                        label: "Save"
                    )
                }
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, LVSpacing.base - 2)
        .padding(.vertical, LVSpacing.md)
        .lvGlassCard(cornerRadius: LVRadius.card, intensity: 0.55)
    }

    /// Files the capture into a Space in the same request, the way the capture
    /// sheet already does. Without it the fast path could only ever write to
    /// the vault root, which made Spaces something you had to go and fix later.
    private var spacePicker: some View {
        Menu {
            Picker(selection: $selectedSpaceID) {
                Text("Unfiled").tag(UUID?.none)
                ForEach(spaces, id: \.id) { space in
                    Text(space.name).tag(UUID?.some(space.id))
                }
            } label: {
                Text("Space")
            }
        } label: {
            HStack(spacing: LVSpacing.xs) {
                LVIconView(.folder, size: 14, tint: palette.textSecondary)
                Text(selectedSpaceName)
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(minHeight: LVSize.tapTarget)
            .contentShape(.rect)
        }
        .disabled(isSaving)
        .accessibilityLabel("File into a Space. Currently \(selectedSpaceName)")
    }

    private var selectedSpaceName: String {
        guard let selectedSpaceID,
              let space = spaces.first(where: { $0.id == selectedSpaceID })
        else { return "Unfiled" }
        return space.name
    }

    /// While recording, the field is not the thing to look at — how long you
    /// have been talking is, along with a way out that is not "save it anyway".
    private var recordingChip: some View {
        HStack(spacing: LVSpacing.sm) {
            LVIconView(.micFill, size: 16, tint: palette.glowPrimary)
            Text(Self.durationLabel(recordingElapsed))
                .lvFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text("Recording")
                .lvFont(.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Button("Cancel", action: onCancelRecording)
                .lvFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording, \(Int(recordingElapsed)) seconds")
    }

    static func durationLabel(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// The page has not been fetched yet, so the host is the only honest thing
    /// to show. The real title arrives when the server finishes enriching.
    private func linkChip(_ link: URL) -> some View {
        HStack(spacing: LVSpacing.sm) {
            LVIconView(.linkCircle, size: 16, tint: palette.glowPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(link.host ?? link.absoluteString)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Saved as a link")
                    .lvFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LVSpacing.md)
        .padding(.vertical, LVSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: LVRadius.md, style: .continuous)
                .fill(palette.surface.opacity(0.5))
        )
    }

    private func affordance(_ icon: LVIcon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LVIconView(icon, size: 18, tint: palette.textSecondary, label: label)
                .frame(minWidth: LVSize.tapTarget, minHeight: LVSize.tapTarget)
                .contentShape(.rect)
        }
        .disabled(isSaving)
    }
}
