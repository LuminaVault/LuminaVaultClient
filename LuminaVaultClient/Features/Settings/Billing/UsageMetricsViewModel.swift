// LuminaVaultClient/LuminaVaultClient/Features/Settings/Billing/UsageMetricsViewModel.swift

import Foundation

@MainActor
@Observable
final class UsageMetricsViewModel {
    private let client: BillingClientProtocol

    private(set) var usage: MeUsageResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(client: BillingClientProtocol) {
        self.client = client
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            usage = try await client.fetchMeUsage()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to refresh usage: \(error.localizedDescription)"
        }
    }

    var storageLabel: String {
        guard let usage else { return "0 KB" }
        return Self.formatBytes(usage.storageBytes)
    }

    var tokensLabel: String {
        Self.formatCount(usage?.tokensTotal ?? 0)
    }

    var compilesLabel: String {
        Self.formatCount(usage?.compileRuns ?? 0)
    }

    var compileFilesLabel: String {
        let count = usage?.compileFiles ?? 0
        return "\(Self.formatCount(count)) \(count == 1 ? "file" : "files")"
    }

    var ttsCharactersLabel: String {
        Self.formatCount(usage?.ttsCharacters ?? 0)
    }

    var shouldShowTTS: Bool {
        (usage?.ttsCharacters ?? 0) > 0
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let clampedBytes = max(0, bytes)
        let units: [(label: String, value: Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("KB", 1_000)
        ]

        let bytesAsDouble = Double(clampedBytes)
        guard let unit = units.first(where: { bytesAsDouble >= $0.value }) else {
            return "0 KB"
        }

        if unit.label == "KB" {
            return "\(Int((bytesAsDouble / unit.value).rounded())) KB"
        }

        return "\(Self.formatDecimal(bytesAsDouble / unit.value)) \(unit.label)"
    }

    private static func formatCount(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formatDecimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
