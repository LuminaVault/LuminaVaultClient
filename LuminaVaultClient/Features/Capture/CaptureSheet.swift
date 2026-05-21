// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureSheet.swift
//
// HER-256 — wraps `CapturePhotosView` and `TextCaptureView` behind a
// segmented control so the FAB stays single-purpose. New capture modes
// (URL — HER-257, voice, etc.) slot in here without forking the FAB.

import SwiftUI

struct CaptureSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case photo
        case text
        case url
        var id: String { rawValue }
        var label: String {
            switch self {
            case .photo: return "Photos"
            case .text: return "Text"
            case .url: return "Link"
            }
        }
    }

    @State private var mode: Mode = .photo
    private let photoViewModel: CapturePhotosViewModel
    private let textViewModel: TextCaptureViewModel
    private let urlViewModel: URLCaptureViewModel

    init(
        photoViewModel: CapturePhotosViewModel,
        textViewModel: TextCaptureViewModel,
        urlViewModel: URLCaptureViewModel
    ) {
        self.photoViewModel = photoViewModel
        self.textViewModel = textViewModel
        self.urlViewModel = urlViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Capture mode", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch mode {
            case .photo: CapturePhotosView(viewModel: photoViewModel)
            case .text: TextCaptureView(viewModel: textViewModel)
            case .url: URLCaptureView(viewModel: urlViewModel)
            }
        }
    }
}
