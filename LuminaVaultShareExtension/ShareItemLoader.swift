// LuminaVaultShareExtension/ShareItemLoader.swift

import Foundation
import UIKit
import UniformTypeIdentifiers

enum ShareItemLoader {
    static func load(from context: NSExtensionContext?) async -> [SharePayload] {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }

        var payloads: [SharePayload] = []
        if let url = await firstURL(from: attachments) {
            payloads.append(.makeURL(url.absoluteString))
        } else if let text = await firstText(from: attachments) {
            if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               url.host?.isEmpty == false {
                payloads.append(.makeURL(url.absoluteString))
            } else {
                payloads.append(.makeText(text))
            }
        }

        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let image = await loadImage(from: provider) {
                payloads.append(image)
            }
        }

        return payloads
    }

    private static func firstURL(from providers: [NSItemProvider]) async -> URL? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let string = item as? String {
                    continuation.resume(returning: URL(string: string))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func firstText(from providers: [NSItemProvider]) async -> String? {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) })
        else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private static func loadImage(from provider: NSItemProvider) async -> SharePayload? {
        let type = preferredImageType(from: provider.registeredTypeIdentifiers)
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: .makeImage(
                    data: data,
                    contentType: type.contentType,
                    fileExtension: type.fileExtension,
                ))
            }
        }
    }

    private static func preferredImageType(from identifiers: [String]) -> ImageType {
        let all = identifiers.compactMap(UTType.init)
        if all.contains(where: { $0.conforms(to: .heic) }) { return .heic }
        if all.contains(where: { $0.conforms(to: .jpeg) }) { return .jpeg }
        if all.contains(where: { $0.conforms(to: .png) }) { return .png }
        if all.contains(where: { $0.conforms(to: .webP) }) { return .webP }
        if all.contains(where: { $0.conforms(to: .gif) }) { return .gif }
        return .jpeg
    }
}

private struct ImageType {
    let identifier: String
    let contentType: String
    let fileExtension: String

    static let heic = ImageType(identifier: UTType.heic.identifier, contentType: "image/heic", fileExtension: "heic")
    static let jpeg = ImageType(identifier: UTType.jpeg.identifier, contentType: "image/jpeg", fileExtension: "jpg")
    static let png = ImageType(identifier: UTType.png.identifier, contentType: "image/png", fileExtension: "png")
    static let webP = ImageType(identifier: UTType.webP.identifier, contentType: "image/webp", fileExtension: "webp")
    static let gif = ImageType(identifier: UTType.gif.identifier, contentType: "image/gif", fileExtension: "gif")
}
