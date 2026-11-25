@preconcurrency import AVFoundation
import os

/// Front camera frames as BGRA pixel buffers, delivered on a private queue.
///
/// Face unlock only ever uses the Mac's own built-in camera. A Continuity Camera iPhone, a USB webcam or a virtual
/// camera (OBS and the like) could feed in prepared video, so they're refused rather than used as a fallback.
final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "islet.face.camera")
    private var handler: (@Sendable (CVPixelBuffer) -> Void)?
    private var device: AVCaptureDevice?
    private static let log = Logger(subsystem: "com.marcogad.islet", category: "camera")
    /// For tuning the speed of a scan (1.7.1): when `start` was called, and whether the first frame has been logged.
    private var startedAt = CACurrentMediaTime()
    private var firstFrameLogged = false

    enum CameraError: Error { case denied, noCamera }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// The Mac's built-in camera, or nil when it has none (or the lid is closed on a clamshell setup).
    static func builtIn() -> AVCaptureDevice? {
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video,
                                                     position: .unspecified).devices
        return found.first { isBuiltIn($0) }
    }

    /// Built in, made by Apple and not a phone: the rules a device has to pass, kept apart so they're readable.
    static func isBuiltIn(_ d: AVCaptureDevice) -> Bool {
        d.deviceType == .builtInWideAngleCamera && !d.isContinuityCamera && d.manufacturer == "Apple Inc."
    }

    func start(handler: @escaping @Sendable (CVPixelBuffer) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CameraError.denied }
        guard let device = Self.builtIn(), let input = try? AVCaptureDeviceInput(device: device) else {
            Self.log.error("no built-in camera")
            throw CameraError.noCamera
        }
        self.device = device
        self.handler = handler
        startedAt = CACurrentMediaTime(); firstFrameLogged = false
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        // 720p where the camera has it (all the built-in ones do; the older, notch-less Macs top out there): twice the
        // pixels across a face, so it still reads at a greater distance. The 1080p ones aren't used: more to process
        // for no gain the recogniser can use.
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        else if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        queue.async { [session] in session.startRunning() }
    }

    /// Holds exposure and white balance still (true) or hands them back to the camera (false), so the brightness
    /// pulse isn't cancelled out by auto-exposure. Returns false when the camera can't lock; the pulse check then
    /// relies on ratios that exposure changes don't affect.
    @discardableResult func holdExposure(_ hold: Bool) -> Bool {
        guard let device, (try? device.lockForConfiguration()) != nil else { return false }
        defer { device.unlockForConfiguration() }
        var held = false
        if hold {
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked; held = true }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
        } else {
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
        return held
    }

    /// Takes over a camera that's already running (`start` with a handler that ignored the frames): the frames then go
    /// to `handler`. Frames are only ever delivered on the camera's queue, so the swap is made there.
    func attach(handler: @escaping @Sendable (CVPixelBuffer) -> Void) {
        queue.async {
            self.handler = handler
            self.startedAt = CACurrentMediaTime(); self.firstFrameLogged = false
        }
    }

    func stop() {
        handler = nil
        if device?.exposureMode == .locked { holdExposure(false) }
        queue.async { [session] in session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if !firstFrameLogged {
            firstFrameLogged = true
            Self.log.notice("first camera frame \(Int((CACurrentMediaTime() - self.startedAt) * 1000)) ms after start, \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb))")
        }
        // When the frame was taken, on the wall clock: the light check compares it with when the screen changed, and a
        // frame can be handled 100 ms or more after it was taken (face model, spoof model).
        let age = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) - CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        if age.isFinite, age >= 0, age < 1 {
            CVBufferSetAttachment(pb, Self.capturedKey, NSNumber(value: Date().timeIntervalSinceReferenceDate - age), .shouldNotPropagate)
        }
        handler?(pb)
    }

    private static let capturedKey = "IsletCaptured" as CFString

    /// When the camera took this frame; now if it wasn't stamped.
    static func captured(_ pb: CVPixelBuffer) -> Date {
        (CVBufferCopyAttachment(pb, capturedKey, nil) as? NSNumber).map { Date(timeIntervalSinceReferenceDate: $0.doubleValue) } ?? Date()
    }
}
