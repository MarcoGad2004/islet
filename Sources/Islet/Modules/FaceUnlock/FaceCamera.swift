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

    private static let cachedDevice = OSAllocatedUnfairLock<AVCaptureDevice?>(initialState: nil)

    /// `builtIn()`, remembered: the device discovery is slow and `start` runs on the main thread.
    static func builtInCached() -> AVCaptureDevice? {
        if let d = cachedDevice.withLock({ $0 }), d.isConnected { return d }
        let d = builtIn()
        cachedDevice.withLock { $0 = d }
        return d
    }

    /// Looks the camera up off the main thread, so the first scan's `start` finds it cached.
    static func prefetch() { DispatchQueue.global(qos: .utility).async { _ = builtInCached() } }

    /// Seconds since this camera delivered its first frame (its exposure starts dark and settles after that), or nil
    /// before one has arrived. Not reset by `attach`.
    var secondsSinceFirstFrame: Double? { firstFrameTime.withLock { $0 }.map { CACurrentMediaTime() - $0 } }
    private let firstFrameTime = OSAllocatedUnfairLock<Double?>(initialState: nil)

    /// `fps` caps the frame rate (a camera that only warms up has no use for 30 a second); `attach` lifts it.
    /// The session is configured and started on the camera's queue, off the main thread (it took tens of ms and ran
    /// while the scan was animating in); a failure there shows as no frames.
    func start(fps: Double? = nil, handler: @escaping @Sendable (CVPixelBuffer) -> Void) throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw CameraError.denied }
        guard let device = Self.builtInCached() else {
            Self.log.error("no built-in camera")
            throw CameraError.noCamera
        }
        self.device = device
        self.handler = handler
        startedAt = CACurrentMediaTime(); firstFrameLogged = false
        queue.async { [self, session] in
            guard let input = try? AVCaptureDeviceInput(device: device) else { Self.log.error("camera input failed"); return }
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
            session.startRunning()
            if let fps { Self.setMinFrameDuration(device, CMTime(value: 1, timescale: CMTimeScale(fps))) }
        }
    }

    /// The frame duration to ask for: `wanted` seconds, moved into what the camera's active format can do (each range is
    /// its fastest and slowest frame duration, in seconds). The camera throws an Objective-C exception, which can't be
    /// caught and ends the app, for a duration outside every range: the built-in cameras can't go slower than about
    /// 15 frames a second, so a 5 fps cap crashed the app on locking the Mac. Nil when there are no ranges.
    static func clampedFrameDuration(_ wanted: Double, ranges: [(min: Double, max: Double)]) -> Double? {
        guard let lo = ranges.map(\.min).min(), let hi = ranges.map(\.max).max(), lo > 0, hi >= lo else { return nil }
        return Swift.min(Swift.max(wanted, lo), hi)
    }

    private static func setMinFrameDuration(_ device: AVCaptureDevice, _ d: CMTime) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if d.isValid, d.seconds > 0 {
            let ranges = device.activeFormat.videoSupportedFrameRateRanges.map { (min: $0.minFrameDuration.seconds, max: $0.maxFrameDuration.seconds) }
            guard let secs = clampedFrameDuration(d.seconds, ranges: ranges) else { return }
            device.activeVideoMinFrameDuration = CMTime(seconds: secs, preferredTimescale: 1_000_000)
        } else {
            device.activeVideoMinFrameDuration = .invalid   // back to the format's default
        }
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
            if let device = self.device { Self.setMinFrameDuration(device, .invalid) }
            self.handler = handler
            self.startedAt = CACurrentMediaTime(); self.firstFrameLogged = false
        }
    }

    func stop() {
        if device?.exposureMode == .locked { holdExposure(false) }
        queue.async { [self, session] in
            handler = nil // on the queue that reads it
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if firstFrameTime.withLock({ $0 }) == nil { firstFrameTime.withLock { $0 = CACurrentMediaTime() } }
        if !firstFrameLogged {
            firstFrameLogged = true
            Self.log.debug("first camera frame \(Int((CACurrentMediaTime() - self.startedAt) * 1000)) ms after start, \(CVPixelBufferGetWidth(pb))x\(CVPixelBufferGetHeight(pb))")
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
