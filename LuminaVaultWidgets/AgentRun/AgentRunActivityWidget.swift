//
//  AgentRunActivityWidget.swift
//  LuminaVaultWidgets
//
//  Muse Stage D — the Live Activity for a chat turn Hermie is still working
//  on. Lock screen banner plus the Dynamic Island's compact, expanded and
//  minimal presentations, in the Muse chat style
//  (`_reviews/muse-chat-contract.md`): near-black canvas, the Hermie avatar
//  with its working ring, name + status line, the prompt in a pill, and
//  the running tool as the stage glyph.
//
//  The app starts, updates and ends the activity locally
//  (`AgentRunLiveActivity` in the app target); this only renders
//  `AgentRunAttributes`, which both targets compile from one file. Tapping
//  anywhere opens the thread through `luminavault://chat/<id>`.
//
//  The views in this folder take plain values rather than an ActivityKit
//  context so they can be rendered outside a widget host (review renders).
//

import ActivityKit
import SwiftUI
import WidgetKit

struct AgentRunActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentRunAttributes.self) { context in
            AgentRunLockScreenView(
                agentName: context.attributes.agentName,
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(MuseActivityPalette.canvas)
            .activitySystemActionForegroundColor(MuseActivityPalette.text)
            .widgetURL(context.attributes.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            let status = AgentRunActivityCopy.status(state, isStale: context.isStale)
            // The compact and minimal presentations have no text, so their
            // one visible piece carries the status line for VoiceOver.
            let spokenStatus = "\(context.attributes.agentName) \(status)"
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MuseActivityAvatar(stage: state.stage, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    AgentRunStageGlyph(state: state)
                        .font(.title3)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    AgentRunNameStatus(agentName: context.attributes.agentName, status: status)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    AgentRunIslandBottom(state: state)
                }
            } compactLeading: {
                MuseActivityAvatar(stage: state.stage, size: 24)
            } compactTrailing: {
                AgentRunStageGlyph(state: state, spokenStatus: spokenStatus)
            } minimal: {
                MuseActivityAvatar(stage: state.stage, size: 24, spokenStatus: spokenStatus)
            }
            .widgetURL(context.attributes.deepLink)
            .keylineTint(MuseActivityPalette.accent)
        }
    }
}
