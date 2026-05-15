// LuminaVaultClient/LuminaVaultClient/Features/Onboarding/OnboardingStep.swift
//
// HER-219 — minimal onboarding-step enumeration. The full step ladder
// lands with HER-100 (SOUL.md onboarding flow); HER-219 only contributes
// the `byoHermesPrompt` case so the coordinator that ships with HER-100
// can insert it after `signupCompleted` and before `firstCaptureCompleted`.
//
// Per HER-219 acceptance: this step has NO `OnboardingState` latch on
// the server side — purely optional, idempotent, no progress tracking.
// The coordinator should advance past it unconditionally on both
// "Skip" and "Set up now" return.

import Foundation

enum OnboardingStep: String, Sendable, CaseIterable {
    /// Pre-account splash + provider picker (lands with HER-140).
    case authLanding
    /// SOUL.md personality quiz (lands with HER-100).
    case soulQuiz
    /// HER-219 — optional BYO Hermes gateway prompt.
    case byoHermesPrompt
    /// First capture (lands with HER-110).
    case firstCapture
    /// Done — tab bar shell takes over.
    case done
}
