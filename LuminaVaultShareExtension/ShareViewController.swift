// LuminaVaultShareExtension/ShareViewController.swift
//
// HER-258 — entry point for the iOS share-sheet flow. Bridges from
// `UIViewController` (required by the share-extension principal class
// contract) into SwiftUI. The actual UI lives in `ShareRootView`; this
// controller just unwraps the host-provided `NSExtensionItem`, hands a
// URL string to the SwiftUI hierarchy, and owns the
// `completeRequest` / `cancelRequest` callbacks that close the sheet.

import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadURL { [weak self] urlString in
            self?.present(initialURL: urlString)
        }
    }

    private func present(initialURL: String?) {
        let viewModel = ShareViewModel(initialURL: initialURL ?? "")
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

    // MARK: - Extension item parsing

    /// Iterates the inbound `NSExtensionItem`s looking for the first
    /// `public.url` (and falls back to `public.plain-text` so the user
    /// can paste from anywhere). Calls back on the main thread with
    /// `nil` when no URL is found.
    private func loadURL(completion: @escaping (String?) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }

        guard let provider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
            ?? attachments.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) })
        else {
            completion(nil)
            return
        }

        let identifier = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            ? UTType.url.identifier
            : UTType.plainText.identifier

        provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
            let result: String?
            switch item {
            case let url as URL: result = url.absoluteString
            case let string as String: result = string
            default: result = nil
            }
            DispatchQueue.main.async { completion(result) }
        }
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
