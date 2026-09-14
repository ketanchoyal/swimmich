import SwiftUI
import AVFoundation

/// Camera QR scanner (P5 qr-scan): AVCaptureSession + metadata output over a
/// plain preview layer. Fires `onFound` once per distinct code and pauses the
/// session; the presenting sheet dismisses itself. Shows a permission-denied
/// state when the camera is unavailable.
struct QRScannerView: UIViewRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession(on: view, coordinator: context.coordinator)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        startSession(on: view, coordinator: context.coordinator)
                    } else {
                        context.coordinator.showPermissionDenied(on: view)
                    }
                }
            }
        default:
            context.coordinator.showPermissionDenied(on: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func startSession(on view: UIView, coordinator: Coordinator) {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            coordinator.showPermissionDenied(on: view)
            return
        }
        captureSession.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(metadataOutput) else {
            coordinator.showPermissionDenied(on: view)
            return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)

        coordinator.session = captureSession
        coordinator.previewLayer = preview
        coordinator.updateLayout(for: view)
        captureSession.startRunning()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onFound: (String) -> Void
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var lastFound = ""

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func updateLayout(for view: UIView) {
            guard let previewLayer else { return }
            DispatchQueue.main.async {
                previewLayer.frame = view.bounds
            }
        }

        func showPermissionDenied(on view: UIView) {
            let label = UILabel()
            label.text = String(localized: "Camera access is required to scan a server QR code.")
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
                label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            ])
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue,
                  value != lastFound else { return }
            lastFound = value
            session?.stopRunning()
            onFound(value)
        }
    }
}
