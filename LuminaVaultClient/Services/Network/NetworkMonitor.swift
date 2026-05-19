// LuminaVaultClient/LuminaVaultClient/Services/Network/NetworkMonitor.swift
import Foundation
import Network
import Observation

/// HER-39 — reachability + link-type signal for the sync engine and UI.
/// Started once on app launch from `AppState` and observed via `@Observable`.
///
/// `isConnected` is the single source of truth for "is the app online".
/// `VaultRepository` reads it to decide between server write-through and
/// queue-and-defer; `SyncStatusBanner` reads it to colour the chip.
@Observable
@MainActor
final class NetworkMonitor {
    /// Most recent reachability snapshot. Defaults to `true` so first
    /// app launch optimistically attempts a server fetch before the
    /// monitor has produced a real reading.
    private(set) var isConnected: Bool = true
    /// True on cellular / personal hotspot / interface marked expensive.
    /// The sync engine throttles non-urgent background sync (Phase D) when
    /// this is set, leaving cellular budget for foreground operations.
    private(set) var isExpensive: Bool = false
    /// True when Low Data Mode is enabled. Future work may cap byte caching
    /// behaviour off this flag.
    private(set) var isConstrained: Bool = false

    /// Latest observed link type. Useful for surfacing "Wi-Fi" vs "Cellular"
    /// in the Settings → Sync & Backup panel.
    private(set) var linkType: NWInterface.InterfaceType?

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    init(monitor: NWPathMonitor = NWPathMonitor(), startImmediately: Bool = true) {
        self.monitor = monitor
        self.queue = DispatchQueue(label: "com.lumina.network-monitor", qos: .utility)
        if startImmediately { start() }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let type = path.availableInterfaces.first?.type
            Task { @MainActor in
                self.isConnected = connected
                self.isExpensive = expensive
                self.isConstrained = constrained
                self.linkType = type
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    deinit {
        // Cancel without bouncing through MainActor — NWPathMonitor.cancel()
        // is thread-safe.
        monitor.cancel()
    }
}
