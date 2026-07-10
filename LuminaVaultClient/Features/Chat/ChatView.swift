// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatView.swift
//
// HER-269 — multi-turn SSE chat surface. Drops into any NavigationStack
// host (AI tab, dev menu, etc.). Composer pinned via
// `.safeAreaInset(edge: .bottom)`. Auto-scrolls to the live pending
// bubble as tokens arrive.
//
// The empty state is an "Input Hub": a shared cosmic background, a
// Hermie status badge, and a horizontal carousel of quick-action cards
// above the composer. Both empty and active states share the same
// background + composer so switching between them is seamless, and the
// quick actions sit well above the composer so they can never overlap
// or intercept its taps (the cause of the old "typed send does nothing"
// bug — full-width suggestion buttons stole the send tap).
import PhotosUI
import SwiftUI

struct ChatView: View {
    @Environment(\.lvPalette) private var palette
    @Environment(AppState.self) private var appState
    @State var viewModel: ChatViewModel
    /// HER-107 — empty-state quick actions (the AI tab passes the
    /// server's `/v1/me/suggestions` payload). Tapping a card seeds the
    /// composer and sends.
    var emptyStateSuggestions: [String] = []
    /// Optional empty-state copy. Defaults to a generic prompt.
    var emptyHeadline: String = "What would you like to explore today?"
    var emptySupporting: String = "Ask anything. Lumina pulls from your vault and recent learnings."
    /// HER-155 follow-up — assistant bubbles render their markdown body
    /// through `WikilinkMarkdownView` so `[[note]]` and
    /// `[[memory:<uuid>]]` citations are tappable. Both clients are
    /// optional so previews / dev menus that don't need wikilink
    /// resolution can omit them; bubbles fall back to plain text.
    var vaultClient: (any VaultClientProtocol)?
    var memoryClient: (any MemoryClientProtocol)?
    /// Reused `/v1/vault/files` upload seam. An attached file is both
    /// extracted into the turn and uploaded to the vault (persisted +
    /// indexed for grounding). Optional so previews / dev menus can omit.
    var vaultUploadClient: (any VaultUploadClientProtocol)?
    var bottomPadding: CGFloat = 0

    @FocusState private var composerFocused: Bool
    /// Transient banner for a failed file extraction (unsupported type,
    /// unreadable, empty). Auto-clears after a few seconds.
    @State private var attachmentError: String?
    /// Presents the vault-note `@`-reference picker.
    @State private var showNotePicker = false
    /// Photo picker + add-link prompt state.
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showLinkPrompt = false
    @State private var linkText = ""
    @State private var comparisonPresentation: ParallelComparisonPresentation?
    @State private var showWorkflowPicker = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ChatCosmicBackground()

                ScrollView {
                    VStack(spacing: LVSpacing.lg) {
                        if viewModel.messages.isEmpty && !viewModel.isStreaming {
                            emptyState
                        } else {
                            conversation
                        }
                    }
                    .padding(.top, LVSpacing.base)
                    // Clearance so content never hides under the composer.
                    .padding(.bottom, LVSpacing.hero)
                }
                .onChange(of: viewModel.displayedAssistant) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(Self.pendingAnchor, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let last = viewModel.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            // HER-255 — header hoisted to MainTabView (app-wide base header).
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        // BYOK v2 — when the user changes their LLM provider/model/mode in
        // Settings, start a fresh conversation so a thread never mixes turns
        // from two different models.
        .onChange(of: appState.llmConfigVersion) { _, _ in
            guard !viewModel.isStreaming, !viewModel.messages.isEmpty else { return }
            viewModel.reset()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.sendHapticTrigger)
        .sensoryFeedback(.success, trigger: viewModel.completionHapticTrigger)
        .sheet(item: $comparisonPresentation) { _ in
            ParallelComparisonView(viewModel: viewModel)
        }
    }

    // MARK: - Empty state ("Input Hub")

    private var emptyState: some View {
        VStack(spacing: LVSpacing.xl) {
            HermieStatusBadge(mascotState: viewModel.mascotState, label: statusLabel)
                .padding(.top, LVSpacing.lg)

            if !emptyStateSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: LVSpacing.sm) {
                    Text("Quick actions")
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, LVSpacing.lg)

                    QuickActionsCarousel(
                        suggestions: emptyStateSuggestions,
                        onTap: { viewModel.sendSuggestion($0) }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !emptySupporting.isEmpty {
                Text(emptySupporting)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LVSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Short label under the mascot badge, derived from voice + phase.
    private var statusLabel: String {
        if viewModel.voice.isRecording { return "Listening…" }
        switch viewModel.phase {
        case .starting, .streaming: return "Thinking…"
        case .failed: return "Let's try that again"
        case .idle: return "Ready when you are"
        }
    }

    // MARK: - Active conversation

    private var conversation: some View {
        LazyVStack(alignment: .leading, spacing: LVSpacing.base) {
            HStack {
                Spacer()
                Button {
                    viewModel.reset()
                } label: {
                    LVIconView(.trash, size: 14, tint: palette.textSecondary)
                }
                .lvGlowPress()
            }
            .padding(.bottom, LVSpacing.sm)

            ForEach(viewModel.messages) { message in
                MessageRow(
                    message: message,
                    mascotState: .idle,
                    vaultClient: vaultClient,
                    memoryClient: memoryClient,
                )
                .id(message.id)
                .contextMenu {
                    if message.role == .assistant {
                        Button {
                            viewModel.saveAsMemory(message)
                        } label: {
                            Label("Save as memory", systemImage: "brain.head.profile")
                        }
                    }
                    Button(role: .destructive) {
                        viewModel.rewind(to: message)
                    } label: {
                        Label("Rewind to here", systemImage: "arrow.uturn.backward")
                    }
                }
            }

            if viewModel.isStreaming || !viewModel.pendingAssistant.isEmpty {
                PendingAssistantRow(
                    text: viewModel.displayedAssistant,
                    sources: viewModel.pendingSources,
                    isStreaming: viewModel.isStreaming,
                    autoExpandThinking: viewModel.autoExpandThinking,
                    mascotState: viewModel.mascotState,
                )
                .id(Self.pendingAnchor)
            }

            if case let .failed(message) = viewModel.phase {
                ErrorRow(message: message, onRetry: { viewModel.retryLast() })
            }
        }
        .padding(.horizontal, LVSpacing.lg)
    }

    // MARK: - Bottom bar (toasts + composer)

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let toast = viewModel.savedMemoryToast {
                SavedToast(text: toast)
            }
            if let toast = viewModel.jobToast {
                SavedToast(text: toast)
            }
            if let toast = viewModel.reminderToast {
                SavedToast(text: toast)
            }
            // Jobs P3 — recurring-job proposal surfaced from the last turn.
            if let proposal = viewModel.jobProposal {
                JobProposalCard(
                    proposal: proposal,
                    onCreate: viewModel.confirmJob,
                    onDismiss: viewModel.dismissJob,
                )
                .padding(.horizontal, LVSpacing.base)
                .padding(.bottom, LVSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            // HER-55 — reminder proposal surfaced from the last turn.
            if let proposal = viewModel.reminderProposal {
                ReminderProposalCard(
                    proposal: proposal,
                    onCreate: viewModel.confirmReminder,
                    onDismiss: viewModel.dismissReminder,
                )
                .padding(.horizontal, LVSpacing.base)
                .padding(.bottom, LVSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let notice = viewModel.fallbackNotice {
                FallbackBanner(notice: notice)
            }
            MultiModelModeControl(
                isEnabled: $viewModel.multiModelEnabled,
                strategy: $viewModel.multiModelStrategy,
                isStreaming: viewModel.isStreaming
            )
            .padding(.horizontal, LVSpacing.base)
            .padding(.bottom, LVSpacing.xs)
            if let execution = viewModel.parallelExecution {
                ParallelProgressButton(execution: execution) {
                    comparisonPresentation = .init(id: execution.id)
                }
                .padding(.horizontal, LVSpacing.base)
                .padding(.bottom, LVSpacing.xs)
            }
            if let routing = viewModel.routingEvent {
                CerberusUsageIndicator(routing: routing, usage: viewModel.routeUsage)
                    .padding(.horizontal, LVSpacing.base)
                    .padding(.bottom, LVSpacing.xs)
            }
            if let voiceError = viewModel.voice.errorMessage {
                VoiceErrorToast(text: voiceError)
            }
            if let attachmentError {
                VoiceErrorToast(text: attachmentError)
            }

            ComposerBar(
                text: $viewModel.composer,
                canSend: viewModel.canSend,
                isStreaming: viewModel.isStreaming,
                sendOnReturn: viewModel.sendOnReturn,
                referenceNames: viewModel.stagedReferences.map(\.name),
                voice: viewModel.voice,
                onSend: {
                    composerFocused = false
                    viewModel.send()
                },
                onCancel: viewModel.cancel,
                onAttach: handleAttach,
                onRemoveReference: { index in
                    guard viewModel.stagedReferences.indices.contains(index) else { return }
                    viewModel.removeReference(viewModel.stagedReferences[index])
                },
                onPickNote: { showNotePicker = true },
                onPickPhoto: { showPhotoPicker = true },
                onAddLink: { linkText = ""; showLinkPrompt = true },
                onRunWorkflow: { showWorkflowPicker = true },
            )
            .focused($composerFocused)
            .sheet(isPresented: $showNotePicker) {
                if let vaultClient {
                    NavigationStack {
                        VaultNotePickerView(vaultClient: vaultClient, onPick: handleNotePick)
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                handlePhoto(item)
            }
            .alert("Add a link", isPresented: $showLinkPrompt) {
                TextField("https://…", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Button("Add") { handleLink(linkText) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The link is added as context for your next message.")
            }
            .sheet(isPresented: $showWorkflowPicker) {
                NavigationStack {
                    ChatWorkflowPicker(
                        client: WorkflowsHTTPClient(client: appState.makeHTTPClient()),
                        conversationID: viewModel.conversationID
                    )
                }
            }
        }
        .padding(.bottom, bottomPadding)
        .background(.clear)
    }

    /// "Do both": extract the file's text into the turn (immediate use)
    /// AND upload the raw bytes to the vault (persisted + indexed for
    /// grounding). The upload is best-effort — the staged text works even
    /// if the vault rejects the type.
    private func handleAttach(_ url: URL) {
        do {
            let extracted = try AttachmentTextExtractor.extract(from: url)
            viewModel.attach(name: extracted.name, text: extracted.text)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            showAttachmentError(message)
            return
        }
        uploadToVault(url)
    }

    /// `@`-reference an existing vault note: read its text and stage it as a
    /// context reference. The file is already in the vault, so no re-upload.
    private func handleNotePick(_ file: VaultFileDTO) {
        guard let vaultClient else { return }
        let title = file.metadata?.title
        let name = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? (file.path as NSString).lastPathComponent
        Task {
            do {
                let (data, _) = try await vaultClient.readFile(relativePath: file.path)
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                    showAttachmentError("That note is empty or unreadable.")
                    return
                }
                viewModel.attach(name: name, text: text)
            } catch {
                showAttachmentError("Couldn't read that note.")
            }
        }
    }

    /// Add a photo: upload the image to the vault (best-effort, like file
    /// attachments) and stage a marker reference. There's no client OCR, so
    /// the turn carries a marker; the image lives in the vault for search.
    private func handlePhoto(_ item: PhotosPickerItem) {
        Task {
            defer { photoItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else {
                showAttachmentError("Couldn't load that photo.")
                return
            }
            let name = "photo-\(Int(Date().timeIntervalSince1970)).jpg"
            if let vaultUploadClient {
                _ = try? await vaultUploadClient.uploadAsset(
                    data: data,
                    contentType: "image/jpeg",
                    relativePath: "uploads/\(name)",
                    spaceID: nil,
                )
            }
            viewModel.attach(name: name, text: "[Photo added to your vault: \(name)]")
        }
    }

    /// Add a link as a context reference for the next turn.
    private func handleLink(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            showAttachmentError("That doesn't look like a valid link.")
            return
        }
        viewModel.attach(name: trimmed, text: "[Link reference: \(trimmed)]")
    }

    private func uploadToVault(_ url: URL) {
        guard let vaultUploadClient else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        guard let data else { return }

        let name = url.lastPathComponent
        let contentType = Self.uploadContentType(for: url.pathExtension.lowercased())
        Task {
            // Best-effort: a vault allowlist rejection (e.g. .txt) leaves
            // the staged text intact, so the turn still carries the file.
            _ = try? await vaultUploadClient.uploadAsset(
                data: data,
                contentType: contentType,
                relativePath: "uploads/\(name)",
                spaceID: nil,
            )
        }
    }

    private static func uploadContentType(for ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "md", "markdown": return "text/markdown"
        default: return "text/plain"
        }
    }

    private func showAttachmentError(_ message: String) {
        attachmentError = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            attachmentError = nil
        }
    }

    private static let pendingAnchor = "lv.chat.pending"
}

private struct CerberusUsageIndicator: View {
    @Environment(\.lvPalette) private var palette
    let routing: RouterRoutingEventDTO
    let usage: RouterUsageDTO?

    private var routeLabel: String {
        if routing.strategy == .ensemble {
            return "\(routing.activeRoutes.count) models"
        }
        guard let route = routing.activeRoutes.first else { return "Selecting model" }
        return "\(route.provider.rawValue) · \(route.model)"
    }

    var body: some View {
        HStack(spacing: LVSpacing.sm) {
            Image(systemName: routing.strategy == .ensemble ? "point.3.connected.trianglepath.dotted" : "arrow.triangle.branch")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("CERBERUS · \(routing.profileName) · \(routing.taskType.rawValue.capitalized)")
                    .lvFont(.microTag)
                    .foregroundStyle(palette.textSecondary)
                Text(routeLabel)
                    .lvFont(.footnote)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let usage {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(usage.tokensIn + usage.tokensOut) tokens")
                    Text((Double(usage.estimatedCostUsdMicros) / 1_000_000).formatted(.currency(code: "USD")))
                }
                .lvFont(.microTag)
                .foregroundStyle(palette.textSecondary)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Cerberus is routing")
            }
        }
        .padding(LVSpacing.sm)
        .background(palette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: LVRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: LVRadius.md)
                .stroke(palette.accent.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var value = "Cerberus profile \(routing.profileName), task \(routing.taskType.rawValue), route \(routeLabel)."
        if let usage {
            value += " \(usage.tokensIn + usage.tokensOut) tokens, \(usage.latencyMs) milliseconds."
        }
        return value
    }
}

// MARK: - Bubbles

private struct MessageRow: View {
    @Environment(\.lvPalette) private var palette
    let message: ChatViewModel.Message
    let mascotState: HermieMascotState
    /// HER-155 follow-up — passed through from `ChatView`. Assistant
    /// bubbles render their body via `WikilinkMarkdownView` only when
    /// both clients are present; otherwise we fall back to plain text.
    let vaultClient: (any VaultClientProtocol)?
    let memoryClient: (any MemoryClientProtocol)?

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            if message.role == .user {
                Spacer(minLength: LVSpacing.hero)
                bubble
            } else {
                AssistantAvatar(state: mascotState)
                    .padding(.top, LVSpacing.xs)
                bubble
                Spacer(minLength: LVSpacing.hero)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let content = VStack(alignment: .leading, spacing: LVSpacing.xs) {
            bubbleBody
            // Render any images the assistant returned (e.g. Hermes Tool
            // Gateway image generation) — AttributedString markdown drops
            // image syntax, so surface them explicitly.
            ForEach(imageURLs, id: \.self) { url in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous))
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: 280)
            }
            if !message.sources.isEmpty {
                SourceChipRow(sources: message.sources)
            }
        }
        .padding(.horizontal, LVSpacing.base)
        .padding(.vertical, LVSpacing.md)

        if message.role == .user {
            content
                .background {
                    RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                        .fill(palette.glowPrimary.opacity(0.18))
                        .overlay {
                            RoundedRectangle(cornerRadius: LVRadius.card, style: .continuous)
                                .stroke(palette.glowPrimary.opacity(0.5), lineWidth: 1)
                        }
                }
                .shadow(color: palette.glowPrimary.opacity(0.25), radius: 10)
        } else {
            content
                .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
                .lvInnerGlow(cornerRadius: LVRadius.card, intensity: LVGlow.subtle)
        }
    }

    /// Image URLs an assistant turn carries (markdown `![](url)` or bare
    /// image links). Empty for user turns.
    private var imageURLs: [URL] {
        guard message.role == .assistant else { return [] }
        return Self.extractImageURLs(from: message.content)
    }

    static func extractImageURLs(from text: String) -> [URL] {
        let ns = text as NSString
        var urls: [URL] = []
        func scan(_ pattern: String, group: Int) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return }
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > group {
                if let url = URL(string: ns.substring(with: m.range(at: group))) { urls.append(url) }
            }
        }
        // Markdown image: ![alt](url)
        scan(#"!\[[^\]]*\]\((https?://[^\s)]+)\)"#, group: 1)
        // Bare image URL (not already part of a markdown link)
        scan(#"(?<!\()(https?://[^\s)]+\.(?:png|jpe?g|gif|webp))"#, group: 1)
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        // HER-155 follow-up — only assistant messages can carry
        // `[[memory:uuid]]` citations from Hermes; user messages stay
        // plain so user-entered brackets aren't rewritten.
        if message.role == .assistant,
           let vaultClient,
           let memoryClient
        {
            WikilinkMarkdownView(
                markdown: message.content,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
            )
            .foregroundStyle(palette.textPrimary)
        } else {
            Text(message.content)
                .lvFont(.body)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
        }
    }
}

private struct PendingAssistantRow: View {
    @Environment(\.lvPalette) private var palette
    let text: String
    let sources: [QueryHitDTO]
    let isStreaming: Bool
    let autoExpandThinking: Bool
    let mascotState: HermieMascotState

    var body: some View {
        HStack(alignment: .top, spacing: LVSpacing.sm) {
            AssistantAvatar(state: mascotState)
                .padding(.top, LVSpacing.xs)
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                if text.isEmpty && isStreaming {
                    HStack(spacing: LVSpacing.sm) {
                        TypingIndicator()
                        if autoExpandThinking {
                            Text("Preparing a response…")
                                .lvFont(.callout)
                                .foregroundStyle(palette.textSecondary)
                                .transition(.opacity)
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: LVSpacing.xs) {
                        Text(text)
                            .lvFont(.body)
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        if isStreaming { StreamingCaret() }
                    }
                }
                if !sources.isEmpty {
                    SourceChipRow(sources: sources)
                }
            }
            .padding(.horizontal, LVSpacing.base)
            .padding(.vertical, LVSpacing.md)
            .lvGlassCard(cornerRadius: LVRadius.card, intensity: LVGlow.card)
            .lvInnerGlow(cornerRadius: LVRadius.card,
                         intensity: isStreaming ? LVGlow.focused : LVGlow.subtle)
            .lvPulse(active: isStreaming)
            Spacer(minLength: LVSpacing.hero)
        }
    }
}

/// Inline assistant-turn mascot avatar. Reuses `HermieMascotView` at a
/// chat-bubble-friendly 32pt. Pending bubbles animate (`.thinking` →
/// `.happy`); finalized turns pin to `.idle` so the chat history doesn't
/// jitter as new turns arrive.
private struct AssistantAvatar: View {
    let state: HermieMascotState
    var body: some View {
        HermieMascotView(state: state, size: 32, fallbackImageName: "Mascot")
            .frame(width: 32, height: 32)
    }
}

/// Animated "thinking" placeholder shown while the assistant turn is open but
/// no tokens have arrived yet. Hermes time-to-first-token runs several seconds,
/// so a lone caret feels dead — three staggered bouncing dots read as active
/// composition. Falls back to static dimmed dots under Reduce Motion.
private struct TypingIndicator: View {
    @Environment(\.lvPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeDot = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(palette.glowPrimary)
                    .frame(width: 6, height: 6)
                    .shadow(color: palette.glowPrimary.opacity(0.7), radius: 3)
                    .opacity(reduceMotion ? 0.6 : (activeDot == index ? 1 : 0.3))
                    .offset(y: reduceMotion ? 0 : (activeDot == index ? -3 : 0))
            }
        }
        .frame(height: 14)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.3)) { activeDot = (activeDot + 1) % 3 }
                try? await Task.sleep(for: .milliseconds(240))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Thinking")
    }
}

private struct StreamingCaret: View {
    @Environment(\.lvPalette) private var palette
    @State private var visible = true
    var body: some View {
        Rectangle()
            .fill(palette.glowPrimary)
            .frame(width: 2, height: 14)
            .shadow(color: palette.glowPrimary.opacity(0.8), radius: 4)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

private struct SourceChipRow: View {
    @Environment(\.lvPalette) private var palette
    let sources: [QueryHitDTO]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LVSpacing.sm) {
                ForEach(sources) { hit in
                    Text(hit.content.prefix(40))
                        .lvFont(.microTag)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, LVSpacing.sm)
                        .padding(.vertical, LVSpacing.xs)
                        .background(
                            Capsule().fill(palette.surface)
                        )
                        .overlay {
                            Capsule()
                                .stroke(palette.glowPrimary.opacity(0.25), lineWidth: 1)
                        }
                }
            }
        }
    }
}

// MARK: - Banners + errors

private struct SavedToast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            LVIconView(.checkmarkCircleFill, size: 17, tint: .green)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct FallbackBanner: View {
    let notice: ProviderFallbackNoticeDTO
    var body: some View {
        Text(notice.userMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
    }
}

/// HER-153 — transient banner above the composer surfacing voice mode
/// failures (mic denied, no speech detected, recognizer unavailable) and
/// file-attachment failures. Auto-decays via its source state.
private struct VoiceErrorToast: View {
    @Environment(\.lvPalette) private var palette
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            LVIconView(.exclamationmarkTriangleFill, size: 14, tint: .orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ErrorRow: View {
    @Environment(\.lvPalette) private var palette
    let message: String
    /// Re-sends the last user turn. Surfaced as a tappable "Retry" pill so
    /// a timed-out / failed reply is recoverable without retyping.
    var onRetry: (() -> Void)?
    var body: some View {
        HStack(spacing: 8) {
            LVIconView(.exclamationmarkTriangleFill, size: 14, tint: .orange)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        LVIconView(.arrowUpCircleFill, size: 13, tint: palette.glowPrimary)
                        Text("Retry")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(palette.glowPrimary)
                    }
                }
                .lvGlowPress()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 10))
    }
}
