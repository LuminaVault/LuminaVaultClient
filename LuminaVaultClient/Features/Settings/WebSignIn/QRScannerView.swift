// LuminaVaultClient/LuminaVaultClient/Features/Settings/WebSignIn/QRScannerView.swift
//
// Minimal AVFoundation QR scanner wrapped for SwiftUI. Fires `onScan` once with
// the decoded string, then stops the session so the caller can transition.
import AVFoundation
import SwiftUI
import UIKit

struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context _: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = onScan
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_: ScannerViewController, context _: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        var onError: ((String) -> Void)?

        private let session = AVCaptureSession()

        /// `@unchecked`: `AVCaptureSession` is not Sendable, but Apple
        /// documents calling `startRunning()` from a background thread, and
        /// nothing else touches the session while it starts.
        nonisolated private struct SessionStarter: @unchecked Sendable {
            let session: AVCaptureSession
            func start() { session.startRunning() }
        }
        private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: session)
        private var hasScanned = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hasScanned = false
            startSession()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            stopSession()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer.frame = view.bounds
        }

        private func configureSession() {
            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                onError?("Camera unavailable.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onError?("Camera unavailable.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
        }

        private func startSession() {
            guard !session.isRunning else { return }
            // `startRunning()` blocks; hop off the main thread.
            let starter = SessionStarter(session: session)
            Task.detached {
                starter.start()
            }
        }

        private func stopSession() {
            guard session.isRunning else { return }
            session.stopRunning()
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard
                !hasScanned,
                let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                let value = object.stringValue
            else { return }
            hasScanned = true
            stopSession()
            onScan?(value)
        }
    }
}
