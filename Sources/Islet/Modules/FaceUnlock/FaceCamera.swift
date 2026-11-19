@preconcurrency import AVFoundation

/// Front camera frames as BGRA pixel buffers, delivered on a private queue.
final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "islet.face.camera")
    private var handler: (@Sendable (CVPixelBuffer) -> Void)?

    enum CameraError: Error { case denied, noCamera }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start(handler: @escaping @Sendable (CVPixelBuffer) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CameraError.denied }
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device) else {
            throw CameraError.noCamera
        }
        self.handler = handler
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        queue.async { [session] in session.startRunning() }
    }

    func stop() {
        handler = nil
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let pb = CMSampleBufferGetImageBuffer(sampleBuffer) { handler?(pb) }
    }
}
