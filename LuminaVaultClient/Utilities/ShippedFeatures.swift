// LuminaVaultClient/LuminaVaultClient/Utilities/ShippedFeatures.swift
//
// One switch for UI whose backend does not work in production, so App Review
// (guideline 2.1) and users never meet a control that does nothing. Mirrors
// the "Do not market" table in marketing/features.md. Flip an entry to true in
// the same change that makes the feature work end to end in production.

enum ShippedFeatures {
    /// Best of N, Debate, Consensus, Specialists: ensembles are off in prod.
    static let multiModelAnswers = false
    /// Discord, Slack, Telegram, … per-user gateways need Docker in the API pod.
    static let messagingGateways = false
    /// Hermes Jobs mirror reads a volume the real Hermes does not write.
    static let hermesJobs = false
    /// Bring-your-own Hermes / self-hosting has no supported production path.
    static let bringYourOwnHermes = false
}
