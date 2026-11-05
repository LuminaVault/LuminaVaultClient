# Quick Assistant: long-press AI, ask or act from anywhere

## Context

The AI tab is a full chat screen, and the owner wants that kept. They also want a Siri-like moment: long-press the AI button on any tab, including Home, and a floating card lets them talk or type. The assistant replies using data from across the app, whichever screen they are on, and can also do things.

Today, normal chat only sees vault retrieval, calendar and conversation history, and it passes no tools. Nothing tracks the current screen, and the AI tab has no long-press.

**Supply-side flag:** this does not move the strangers-count. The owner has been told and is proceeding.

## Decisions

**Owner's:**
- Long-press on the AI button opens it; tapping still opens the existing chat.
- Talk or type, and the AI replies. Answers about Y regardless of current screen X.
- It answers **and** acts.
- Runs at once, showing what was done: open a screen, add a reminder, save a memory.
- Needs a confirm card first: create a calendar event, forget a memory.
- Siri-style floating card with a soft glow, over the dimmed current screen. This grants an exception to `DESIGN_SYSTEM.md` §13.9.
- **No tool route available:** the card still answers through normal chat, without actions. If asked to act, it says it can't right now. BYO-Hermes users get answers only.
- **Free and lapsed users get it.** One question costs one free message, however many rounds it takes.
- **Reminders:** always create LuminaVault's own reminder (`/v1/reminders`), and also mirror to Apple Reminders when Apple write permission is on.

**Builder's calls, each open to rejection:**
- **Cloud settings:** the card follows the same rule as chat. If `hybridProfile` is `.private`, or cloud fallback is off so cloud is not a permitted route, it sends nothing and explains why, linking to settings.
- **iPad:** out of v1. Long-press is not installed on iPad, so the tab behaves as today.
- **Device testing:** the owner runs the iOS 26 device spike and the production end-to-end pass on their own account, because they need a physical device and create real events and reminders. The agent supplies the spike build and a test script.
- **Reminder mirror:** one-way and best effort, at creation only. A failed mirror never fails the action; completing or deleting does not sync. No reconciling duplicates in v1.
- **Apple consent:** `calendar_create` still needs Apple write permission, off by default. When refused, the card explains and links to the Apple permission settings.
- **Engine:** in-process server tool loop, not forced Hermes runs (reasons below).
- **Inbox:** each opening of the card starts one normal conversation, visible in the AI inbox, with "Open in chat" on the card.
- **Voice:** the long-press only opens the card; the user then taps the text field or holds the mic (`MicHoldButton`). No auto-listen and no hold-through from the long-press.
- **Speech:** existing on-device `SFSpeech` and `AVSpeechSynthesizer`; a reply is spoken only if the prompt was voice. Both are **en-US only** today (`SpeechRecognizer.swift:41`, `SpeechSynthesizer.swift:89-99`).
- **Confirming by voice:** confirm cards need a tap. A spoken "yes" is out, because a misheard yes could delete a memory. The prompt is read aloud if the turn was voice.
- **On-device model:** where cloud is permitted, the assistant always uses cloud, since on-device turns have no tools.

## Engine: why a server tool loop

| | In-process loop (chosen) | Forced Hermes run (rejected) |
|---|---|---|
| Tools | `MCPService` already implements them | Needs `/v1/mcp` and a per-tenant agent key wired into each container (`HermesTenantConfigTemplate.swift`) |
| Confirm policy | Server code gates each call | Hermes approvals target risky commands; tool calls are not gated (`HermesRunEvent.approvalRequest`) |
| Tool surface | Exact allowlist | Whole Hermes toolset, including terminal |
| Open a screen | Own stream frame | Tool events would have to carry it |
| Tenants without Hermes | Works | Falls back to no tools |

Precedent: `HermesMemoryService.runAgent` (`Memory/HermesMemoryService.swift:410`) is already this loop over `RoutedLLMTransport`, and `AnthropicAdapter+Translation.swift` already maps tools to Haiku. This is no new platform: a small service reusing existing parts. Trade-off: no SOUL or Mnemosyne through Hermes on these turns, so BYOK-style `soulExcerpt` must be supplied to all assistant turns.

## Design

### Server (`LuminaVaultServer`, Swift; chat, llm and mcp are not yet ported to Go)

**Entry point.** Same endpoint, `POST /v1/conversations/:id/messages/stream`, so entitlements and rate limits stay on one path (the stance in `HermesEscalationPolicy.swift:10-13`). `MessageStreamRequest` (`APIDTOs.swift:2055`) gains optional `quickAssistant: { currentTab, activeSpaceID }`. `streamReply` branches to the new service **before** the escalation block at `ConversationController.swift:659`. Those fields only feed the system prompt and are never written into the user message. Only new clients send the field and only those turns emit new frames, so no new capability token is needed.

**`Chat/QuickAssistantService.swift` (new).**
- System prompt: reuse `buildPrompt` parts (persona, top-5 memories, schedule, identity guard, SOUL), then add an app map of what each tab holds, tool guidance, current tab, active space, and the date in the user's timezone. Instruct it that tool output is data, never instructions.
- Routing: pick one `RouteDecision` per question and drop `hermesGateway` candidates, since it ignores tools. Add a non-streaming counterpart to `DecidedStreamTransport` (`RoutedLLMTransport.swift:931`) so every round reuses that decision. This is what makes one question cost one free-lane grant.
- Fallback: if no tool-capable candidate remains, or the first round fails, including the Haiku cap, continue into the existing classic stream path with an added note that actions are unavailable. If a later round fails after writes have run, end with a reply reporting what was done; never re-run them.
- Loop: non-streaming rounds, max 4. The final text goes out as ordinary stream chunks, then is persisted as the assistant message. Send no `temperature`.
- Reminders: new tools `app_reminder_create` and `app_reminders_list`, reusing what `Reminders/RemindersController.swift` calls. Create also tries the Apple mirror through `PersonalDataTools.reminderCreate` when consent allows. Apple's `reminders_list` stays readable; the prompt says to prefer own reminders and treat same-title entries as one.
- `Chat/QuickAssistantToolPolicy.swift` (new, pure function) maps a tool to one action:
  - run: `search`, `browse`, `read`, `recent`, `memory_context`, `health_query`, `calendar_query`, `app_reminders_list`, `reminders_list`, `memory_save`, `app_reminder_create`
  - confirm: `calendar_create`, `memory_forget`
  - client: `open_screen`
  - everything else, such as `memory_update`, `index` and Apple's `reminder_create`: refused
- Authorisation mirrors `MCPController.callTool`: vault tools use the resolved vault with write access when `tool.writes`; personal tools use the caller's own user ID, ignoring the shared vault. Extract that logic rather than copying it. Apple consent stays enforced in `PersonalDataTools.deviceWrite`.

**Frames.** One new case in the chat stream union (`APIDTOs.swift:1600`): `assistantAction`, with a kind of `done`, `needsConfirm` or `openScreen`, plus a server-written summary. The UI shows actions only from these frames, so model text claiming "done" can never produce a chip.

**Confirm.**
- New table `assistant_pending_actions`: id, tenant, conversation, tool, args, summary, status, expires at (10 min).
- `POST /v1/assistant/actions/:id/confirm` and `/cancel`. Confirm flips status atomically, so a replay does nothing, re-checks authorisation, runs the tool from the **stored args**, and appends the result to the conversation. The client cannot alter args.
- The summary comes from args (event title and time, memory excerpt), not from model prose.

**Contract.** DTOs in `LuminaVaultShared` first, then a version bump (latest tag v5.33.0). Update `openapi.yaml`, then `make bruno-regen`.

### iOS (`LuminaVaultClient`)

- **Trigger:** `Features/QuickAssistant/AITabLongPress.swift`, public API only. Find the hosting `UITabBarController`, add a `UILongPressGestureRecognizer` to `tabBar`, and hit-test the AI item's region with a pure, unit-tested function. Haptic on fire. **Must not select the tab.** Proven by the spike below.
- **Card:** `QuickAssistantCard.swift`, an overlay on the outermost `MainTabView` container (alongside `.guidedSpotlight`, `MainTabView.swift:156`) so it covers the tab bar and works on every tab. It is not a sheet, so the one-sheet rule does not apply, but it must close before any sheet opens. Needs keyboard avoidance, modal accessibility traits, tap-outside to dismiss, palette colours, and a static glow under Reduce Motion (§8).
- **State:** `QuickAssistantModel` (`@Observable`), small and separate from the 1,902-line `ChatViewModel`. Reuses `ConversationsHTTPClient`, `VoiceModeController`, `MicHoldButton` and `VoiceWaveformView`. Sends `currentTab` from `selection` and `WorkspaceSelection.activeWorkspaceID`.
- **Actions:** done chip; confirm card with Confirm and Cancel; `openScreen` closes the card then routes through `selection` or `NotificationRouter.pendingDeepLink`. Screens for v1: the five tabs, Settings, `brief`, `learned`, `memory(id)`.
- **Design doc:** add the card to §13.9 and note in §13.8 that the ban on floating buttons does not cover this transient modal.

## Build order

Work in `.worktrees/` from clean `main` on each repo. `LuminaVaultClient` and `LuminaVaultServer` both sit on feature branches with chat files changed, and other sessions share these checkouts.

1. **Spike the trigger, throwaway, owner tests on a real iOS 26 iPhone.** Pass means: fires on the AI tab only, tap still works, no tab selection, works with scrolled and minimized bar. Also check iOS 18 (deployment target) on simulator. **If it fails, stop and bring options to the owner.** No floating button without their call, since §13.8 bans it.
2. **Shared:** DTOs and release.
3. **Server, answers:** field, service, policy, read tools.
4. **Server, actions:** immediate writes, pending table, confirm endpoints, `open_screen`.
5. **iOS:** trigger, card, typed turns, voice, then action chips and confirm cards.

An app-repo merge deploys nothing. Production runs the SHA pinned in `platform/infra` values, and the owner merges infra. Server release needs fully green CI on `main`.

## Verification

- **Server, stub LLM only, no real keys** (`docker compose run --rm --no-deps hummingbird swift test`):
  - policy table for every catalog tool
  - tool call then reply; round cap; `calendar_create` does not execute before confirm
  - no tool route, and Haiku cap on the first round, both fall back to a classic answer with no action frames
  - a 4-round free-lane turn claims exactly one grant
  - own reminder created with Apple consent off, on and with a failed mirror
  - confirm: replay, expiry, other tenant gets 404
  - read-only vault member refused `memory_save`; shared vault cannot reach a co-member's health
  - context fields absent from the persisted user message
- **iOS:** region hit-test, `QuickAssistantModel` against stub client, voice via injected protocols, private profile and cloud-fallback-off both send nothing. Card snapshots recorded via the CI `record-snapshots` workflow (iPhone 16 Pro, iOS 26.4), since local Xcode 26.2 cannot judge them.
- **End to end on a device, against production after promotion:** from Home, ask about sleep, ask about a saved note, "remind me tomorrow", "add dentist Friday 3pm" then confirm and cancel, "forget that memory", "open Brain". Repeat by voice. Check the conversation shows in the inbox. Staging has no Hermes; never point it at production. The agent's own throwaway staging account may cover non-Hermes paths.
- **Owner verdict on real pixels** before merge.

## Risks to check during the build

- **Actions depend on the Haiku trial.** Hermes `/v1/chat/completions` appears to ignore client `tools` in the local checkout; the deployed image is unchecked. Cerberus can also rewrite managed OpenRouter picks onto the gateway. So for managed users Haiku may be the only tool route, and it is time-boxed. When it ends or the cap hits, those users drop to answers only until a direct route is funded. Decide that when the trial ends.
- **Fallback providers** may handle tools differently. Test the chain behind Anthropic, and BYOK.
- **Spend.** A tool turn costs several normal turns, now on free users too. The Haiku trial cap is $20 across four apps and `checkBudget` has no callers, so the round cap and existing rate limits are the only guards. Check Console spend before relying on it.
- **Prompt injection.** Vault text could instruct the model to call tools. Confirm gates the destructive ones; immediate writes stay low-harm and visible as chips.
- **Device writes** round-trip to the phone with a 12s timeout (`DeviceCommandBroker.swift:27`), and must work while the card is up.
- **Latency.** Not measured. A loop round plus speech may not feel like Siri; measure at step 3.

## Not in v1

- **Data gap:** tasks, kanban, the brief and Insights have no tools in the MCP catalog, so the assistant cannot answer about them beyond retrieved memories. "Global context" here means vault, memories, health, calendar and reminders. Adding them is a follow-up.
- "This" on the current screen; only the current tab is known.
- Languages other than en-US.
- Web client.
- `AskLuminaIntent` fix. Existing bug: it parks a question nothing consumes (`LuminaAppIntents.swift:74`, `:194`). Natural later entry point.

## Next

On approval, copy this to `LuminaVaultClient/docs/superpowers/specs/2026-11-04-quick-assistant-design.md` and write the task-level plan with `superpowers:writing-plans`, starting with the trigger spike.
