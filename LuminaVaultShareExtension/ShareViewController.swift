// LuminaVaultShareExtension/ShareViewController.swift
//
// HER-258 — entry point for the iOS share-sheet flow. Bridges from
// `UIViewController` (required by the share-extension principal class
// contract) into SwiftUI. The actual UI lives in `ShareRootView`; this
// controller loads supported URL/text/image payloads and owns the
// `completeRequest` / `cancelRequest` callbacks that close the sheet.

import Foundation
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { [weak self] in
            guard let self else { return }
            let payloads = await ShareItemLoader.load(from: self.extensionContext)
            await MainActor.run {
                self.present(payloads: payloads)
            }
        }
    }

    @MainActor
    private func present(payloads: [SharePayload]) {
        let viewModel = ShareViewModel(payloads: payloads)
        let root = ShareRootView(
            viewModel: viewModel,
            onCancel: { [weak self] in self?.cancelRequest() },
            onSave: { [weak self] in self?.completeRequest() },
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .systemBackground

        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Lifecycle callbacks

    private func cancelRequest() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "com.lumina.fernando.share",
            code: NSUserCancelledError,
        ))
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
