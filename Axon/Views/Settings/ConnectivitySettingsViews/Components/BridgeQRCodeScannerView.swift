//
//  BridgeQRCodeScannerView.swift
//  Axon
//
//  iOS QR scanner for importing Axon Bridge connection payloads.
//

#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

struct BridgeQRCodeScannerView: View {
    let onScanned: (String) -> Void
    let onCancel: () -> Void

    @State private var isAuthorized = false
    @State private var permissionDenied = false
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            Group {
                if permissionDenied {
                    permissionDeniedView
                } else if let scannerError, !scannerError.isEmpty {
                    errorView(scannerError)
                } else if isAuthorized {
                    scannerView
                } else {
                    ProgressView("Requesting camera access...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Scan Bridge QR")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
            .onAppear {
                requestCameraAccessIfNeeded()
            }
        }
    }

    private var scannerView: some View {
        ZStack(alignment: .bottom) {
            QRCodeCameraPreview(
                onScanned: { payload in
                    onScanned(payload)
                },
                onFailure: { message in
                    scannerError = message
                }
            )
            .ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                Text("Center the Axon Bridge QR code inside the frame.")
                    .font(AppTypography.bodySmall())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.45))
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 30))
                .foregroundColor(AppColors.accentWarning)

            Text("Camera permission is required to scan QR codes.")
                .font(AppTypography.bodyMedium(.medium))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)

            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaces.color(.contentBackground))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(AppColors.accentError)

            Text(message)
                .font(AppTypography.bodySmall())
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                scannerError = nil
                requestCameraAccessIfNeeded()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurfaces.color(.contentBackground))
    }

    private func requestCameraAccessIfNeeded() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            permissionDenied = false
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    isAuthorized = granted
                    permissionDenied = !granted
                }
            }
        case .denied, .restricted:
            isAuthorized = false
            permissionDenied = true
        @unknown default:
            isAuthorized = false
            permissionDenied = true
        }
    }
}

private struct QRCodeCameraPreview: UIViewRepresentable {
    let onScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        context.coordinator.attachPreview(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updatePreviewFrame(uiView.bounds)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSession()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onScanned: (String) -> Void
        private let onFailure: (String) -> Void
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var hasScanned = false

        init(onScanned: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onScanned = onScanned
            self.onFailure = onFailure
            super.init()
        }

        func attachPreview(to view: UIView) {
            configureSessionIfNeeded()

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        func updatePreviewFrame(_ frame: CGRect) {
            previewLayer?.frame = frame
        }

        func stopSession() {
            guard session.isRunning else { return }
            session.stopRunning()
        }

        private func configureSessionIfNeeded() {
            guard session.inputs.isEmpty else { return }

            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                onFailure("No camera available on this device.")
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                } else {
                    onFailure("Unable to use camera input for QR scanning.")
                    return
                }
            } catch {
                onFailure("Unable to configure camera: \(error.localizedDescription)")
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                onFailure("Unable to configure QR metadata output.")
            }
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned else { return }
            guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  metadataObject.type == .qr,
                  let payload = metadataObject.stringValue,
                  !payload.isEmpty else { return }

            hasScanned = true
            stopSession()
            onScanned(payload)
        }
    }
}
#endif
