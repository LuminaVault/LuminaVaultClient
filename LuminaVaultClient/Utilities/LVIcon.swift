// LuminaVaultClient/LuminaVaultClient/Utilities/LVIcon.swift
//
// HER-291 — LVIcon token system. The fourth tier in LuminaVault's
// design tokens (LVPalette + LVTypography + LVSpacing/LVSize/LVRadius
// are the other three). Centralizes every icon used in the app so:
//
//   * SF Symbol names live in one place — feature code references
//     semantic cases (.lockShield) instead of raw strings.
//   * Cases that have a branded glyph under
//     `Assets.xcassets/Lumina/Tab/` or `Lumina/Icons/` automatically
//     prefer the custom asset; designers can drop in PNGs without any
//     call-site change.
//   * `LVIconView` renders any case with theme tint + a size token,
//     composing cleanly with existing `lvPulse` / `lvGlowStroke` /
//     `lvGlowPress` modifiers.
//
// `LVTabBar` consumes `LVIcon` to resolve names but renders custom
// assets with `.original` mode + saturation damping (tab-specific
// styling). Everywhere else, prefer `LVIconView`.

import SwiftUI

// MARK: - LVIcon

/// Every icon used in LuminaVault. Cases that ship with a custom
/// branded asset override the SF Symbol fallback transparently.
///
/// Adding a new icon:
///   1. Append a semantic case below (alphabetical inside its group).
///   2. Return its SF Symbol from `sfSymbol`.
///   3. (Optional) Map a custom asset path in `customAssetName`.
///   4. Add a row to `DESIGN_SYSTEM.md` §12.
enum LVIcon: CaseIterable, Hashable, Sendable {
    // MARK: Tab chrome (paired with Lumina/Tab/* custom assets)
    case tabHome
    case tabSpaces
    case tabThink
    case tabSettings
    case tabVisualSearch

    // MARK: Identity / auth
    case apple
    case envelope
    case envelopeFill
    case keyFill
    case lockFill
    case lockShield
    case phoneFill

    // MARK: Navigation & disclosure
    case chevronDown
    case chevronLeft
    case chevronRight
    case chevronUpChevronDown
    case ellipsis
    case xmark
    case xmarkCircleFill

    // MARK: Status / feedback
    case checkmark
    case checkmarkCircleFill
    case checkmarkSealFill
    case clock
    case clockBadgeCheckmark
    case clockBadgeExclamationmark
    case clockFill
    case exclamationmarkTriangle
    case exclamationmarkTriangleFill
    case flameFill
    case xCircle

    // MARK: Action
    case arrowClockwise
    case arrowClockwiseCircle
    case arrowTriangle2Circlepath
    case arrowUpCircleFill
    case arrowUpRightSquare
    case plus
    case plusCircleFill
    case squareAndArrowUp
    case stopCircleFill
    case trash
    case trayAndArrowDown

    // MARK: Communication
    case bubbleLeftAndBubbleRight
    case bubbleLeftAndBubbleRightFill
    case bubbleLeftAndTextBubbleRight
    case micFill

    // MARK: Content
    case bookmarkFill
    case docOnClipboard
    case docOnDoc
    case docText
    case eye
    case folder
    case folderFill
    case quoteOpening

    // MARK: Cognition / product
    case bellBadge
    case brain
    case brainHeadProfile
    case brainPremium                       // HER-301 — premium variant for paywall / hero
    case infoCircle
    case lightbulbFill
    case sparkles
    case sparklesRectangleStack
    case wandSparkle                        // HER-301

    // MARK: Identity premium (HER-301 — paywall / hero / onboarding)
    case skeletonKeyPremium
    case wingedLockPremium
    case wingedScrollPremium

    // MARK: System / infrastructure
    case boltHorizontal
    case briefcase                          // HER-301 — work / capture sources
    case cameraAperture
    case chartUp                            // HER-301 — growth / metrics
    case cloudWinged                        // HER-301 — sync / cloud
    case creditcard
    case creditcardAnd123
    case door                               // HER-301 — sign-in / exit moments
    case gear
    case globe
    case handRaised
    case heartWinged                        // HER-301 — health / favorite
    case homeGlow                           // HER-301 — non-tab home glyph
    case layers                             // HER-301 — spaces / stacks
    case linkCircle
    case location
    case magnifyingglass
    case musicNote
    case network
    case personCircleFill
    case photoOnRectangleAngled
    case questionmarkAppDashed
    case scrollWinged                       // HER-301 — vault / notes
    case serverRack
    case shieldBrain                        // HER-301 — secure intelligence
    case sliderHorizontal3
    case speakerWave2
    case star

    /// The SF Symbol shown when no custom branded asset exists for this
    /// icon (or when the asset is missing from the catalog).
    var sfSymbol: String {
        switch self {
        // Tab chrome — fall back to SF Symbols matching the original
        // MainTabView wiring so layout stays identical if a Lumina/Tab
        // imageset is removed.
        case .tabHome:                          return "sparkles"
        case .tabSpaces:                        return "folder.fill"
        case .tabThink:                         return "bubble.left.and.text.bubble.right"
        case .tabSettings:                      return "gear"
        case .tabVisualSearch:                  return "photo.on.rectangle.angled"

        case .apple:                            return "apple.logo"
        case .envelope:                         return "envelope"
        case .envelopeFill:                     return "envelope.fill"
        case .keyFill:                          return "key.fill"
        case .lockFill:                         return "lock.fill"
        case .lockShield:                       return "lock.shield"
        case .phoneFill:                        return "phone.fill"

        case .chevronDown:                      return "chevron.down"
        case .chevronLeft:                      return "chevron.left"
        case .chevronRight:                     return "chevron.right"
        case .chevronUpChevronDown:             return "chevron.up.chevron.down"
        case .ellipsis:                         return "ellipsis"
        case .xmark:                            return "xmark"
        case .xmarkCircleFill:                  return "xmark.circle.fill"

        case .checkmark:                        return "checkmark"
        case .checkmarkCircleFill:              return "checkmark.circle.fill"
        case .checkmarkSealFill:                return "checkmark.seal.fill"
        case .clock:                            return "clock"
        case .clockBadgeCheckmark:              return "clock.badge.checkmark"
        case .clockBadgeExclamationmark:        return "clock.badge.exclamationmark"
        case .clockFill:                        return "clock.fill"
        case .exclamationmarkTriangle:          return "exclamationmark.triangle"
        case .exclamationmarkTriangleFill:      return "exclamationmark.triangle.fill"
        case .flameFill:                        return "flame.fill"
        case .xCircle:                          return "x.circle"

        case .arrowClockwise:                   return "arrow.clockwise"
        case .arrowClockwiseCircle:             return "arrow.clockwise.circle"
        case .arrowTriangle2Circlepath:         return "arrow.triangle.2.circlepath"
        case .arrowUpCircleFill:                return "arrow.up.circle.fill"
        case .arrowUpRightSquare:               return "arrow.up.right.square"
        case .plus:                             return "plus"
        case .plusCircleFill:                   return "plus.circle.fill"
        case .squareAndArrowUp:                 return "square.and.arrow.up"
        case .stopCircleFill:                   return "stop.circle.fill"
        case .trash:                            return "trash"
        case .trayAndArrowDown:                 return "tray.and.arrow.down"

        case .bubbleLeftAndBubbleRight:         return "bubble.left.and.bubble.right"
        case .bubbleLeftAndBubbleRightFill:     return "bubble.left.and.bubble.right.fill"
        case .bubbleLeftAndTextBubbleRight:     return "bubble.left.and.text.bubble.right"
        case .micFill:                          return "mic.fill"

        case .bookmarkFill:                     return "bookmark.fill"
        case .docOnClipboard:                   return "doc.on.clipboard"
        case .docOnDoc:                         return "doc.on.doc"
        case .docText:                          return "doc.text"
        case .eye:                              return "eye"
        case .folder:                           return "folder"
        case .folderFill:                       return "folder.fill"
        case .quoteOpening:                     return "quote.opening"

        case .bellBadge:                        return "bell.badge"
        case .brain:                            return "brain"
        case .brainHeadProfile:                 return "brain.head.profile"
        case .brainPremium:                     return "brain.head.profile"
        case .infoCircle:                       return "info.circle"
        case .lightbulbFill:                    return "lightbulb.fill"
        case .sparkles:                         return "sparkles"
        case .sparklesRectangleStack:           return "sparkles.rectangle.stack"
        case .wandSparkle:                      return "wand.and.stars"

        case .skeletonKeyPremium:               return "key.fill"
        case .wingedLockPremium:                return "lock.shield"
        case .wingedScrollPremium:              return "scroll.fill"

        case .boltHorizontal:                   return "bolt.horizontal"
        case .briefcase:                        return "briefcase.fill"
        case .cameraAperture:                   return "camera.aperture"
        case .chartUp:                          return "chart.line.uptrend.xyaxis"
        case .cloudWinged:                      return "cloud.fill"
        case .creditcard:                       return "creditcard"
        case .creditcardAnd123:                 return "creditcard.and.123"
        case .door:                             return "door.left.hand.open"
        case .gear:                             return "gear"
        case .globe:                            return "globe"
        case .handRaised:                       return "hand.raised"
        case .heartWinged:                      return "heart.fill"
        case .homeGlow:                         return "house.fill"
        case .layers:                           return "square.3.layers.3d"
        case .linkCircle:                       return "link.circle"
        case .location:                         return "location"
        case .magnifyingglass:                  return "magnifyingglass"
        case .musicNote:                        return "music.note"
        case .network:                          return "network"
        case .personCircleFill:                 return "person.circle.fill"
        case .photoOnRectangleAngled:           return "photo.on.rectangle.angled"
        case .questionmarkAppDashed:            return "questionmark.app.dashed"
        case .scrollWinged:                     return "scroll.fill"
        case .serverRack:                       return "server.rack"
        case .shieldBrain:                      return "lock.shield.fill"
        case .sliderHorizontal3:                return "slider.horizontal.3"
        case .speakerWave2:                     return "speaker.wave.2"
        case .star:                             return "star"
        }
    }

    /// Asset catalog path (e.g. "Lumina/Tab/home") when a custom
    /// branded glyph exists. `nil` falls through to `sfSymbol`.
    ///
    /// The Tab/* assets are full-colour brand glyphs and are loaded by
    /// `LVTabBar` with `renderingMode(.original)`. `LVIconView` loads
    /// them as templates and applies the requested tint instead — that
    /// gives the same name a consistent look outside the tab bar.
    var customAssetName: String? {
        switch self {
        // Tab chrome — full-colour brand glyphs, rendered .original by LVTabBar.
        case .tabHome:                 return "Lumina/Tab/home"
        case .tabSpaces:               return "Lumina/Tab/spaces"
        case .tabThink:                return "Lumina/Tab/think"
        case .tabSettings:             return "Lumina/Tab/settings"
        case .tabVisualSearch:         return "Lumina/Tab/visualsearch"

        // HER-301 — existing semantic cases that now ship a Lumina/Icons/* PNG.
        // LVIconView renders these .template + palette tint; LVTabBar is the
        // only call site that uses .original mode.
        case .brain:                   return "Lumina/Icons/brain"
        case .brainHeadProfile:        return "Lumina/Icons/brain-neural"
        case .cameraAperture:          return "Lumina/Icons/camera"
        case .gear:                    return "Lumina/Icons/gear"
        case .lightbulbFill:           return "Lumina/Icons/lightbulb"
        case .linkCircle:              return "Lumina/Icons/link"
        case .magnifyingglass:         return "Lumina/Icons/magnify"
        case .micFill:                 return "Lumina/Icons/mic"
        case .photoOnRectangleAngled:  return "Lumina/Icons/gallery"
        case .plusCircleFill:          return "Lumina/Icons/plus-circle"

        // HER-301 — new cinematic-only cases (no clean SF Symbol equivalent).
        case .brainPremium:            return "Lumina/Icons/brain_premium"
        case .briefcase:               return "Lumina/Icons/briefcase"
        case .chartUp:                 return "Lumina/Icons/chart-up"
        case .cloudWinged:             return "Lumina/Icons/cloud-winged"
        case .door:                    return "Lumina/Icons/door"
        case .heartWinged:             return "Lumina/Icons/heart-winged"
        case .homeGlow:                return "Lumina/Icons/home"
        case .layers:                  return "Lumina/Icons/layers"
        case .scrollWinged:            return "Lumina/Icons/scroll-winged"
        case .shieldBrain:             return "Lumina/Icons/shield-brain"
        case .skeletonKeyPremium:      return "Lumina/Icons/skeleton_key_premium"
        case .wandSparkle:             return "Lumina/Icons/wand-sparkle"
        case .wingedLockPremium:       return "Lumina/Icons/winged_lock_premium"
        case .wingedScrollPremium:     return "Lumina/Icons/winged_scroll_premium"

        default:                       return nil
        }
    }
}

// MARK: - LVIconView

/// Renders an `LVIcon` with theme tint and a size token. Prefer
/// `LVSize.tabBarGlyph` (22pt) inside tab bars and `LVSize.rowGlyph`
/// (28pt — default) for list-row leading glyphs. Pass an explicit pt
/// value for inline body glyphs.
///
/// Composes with `.lvPulse()`, `.lvGlowStroke()`, `.lvGlowPress()`.
/// Glow / shadow effects stay on the wrapper view — `LVIconView`
/// itself only resolves the name + tint, so the existing modifier
/// stack keeps working.
///
/// `LVTabBar` renders custom assets with `.original` mode for full
/// brand colour; `LVIconView` renders them as `.template` so a single
/// case looks consistent regardless of where it's used.
struct LVIconView: View {
    let icon: LVIcon
    let size: CGFloat
    let tint: Color?
    let weight: Font.Weight

    init(
        _ icon: LVIcon,
        size: CGFloat = LVSize.rowGlyph,
        tint: Color? = nil,
        weight: Font.Weight = .regular
    ) {
        self.icon = icon
        self.size = size
        self.tint = tint
        self.weight = weight
    }

    var body: some View {
        if let assetName = icon.customAssetName,
           UIImage(named: assetName) != nil {
            Image(assetName)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(tint ?? Color.primary)
        } else {
            Image(systemName: icon.sfSymbol)
                .font(.system(size: size, weight: weight))
                .foregroundStyle(tint ?? Color.primary)
        }
    }
}
