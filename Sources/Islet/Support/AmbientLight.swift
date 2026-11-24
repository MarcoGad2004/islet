import Foundation

/// The built-in ambient light sensor, in lux. Private IOHIDEventSystem calls (the sensor is the Apple vendor page
/// 0xff00, usage 4; event type 12): no entitlement needed (verified on macOS 27.2, 2026-11-23). Nil when there's no
/// sensor or the calls are gone. Private API: personal use only, may break on a macOS update.
@MainActor
enum AmbientLight {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    private static let eventType: Int64 = 12 // kIOHIDEventTypeAmbientLightSensor
    private static let luxField: Int32 = 12 << 16

    /// The client is kept with the service: a service outlives nothing once its client is released, and reading it then
    /// crashed inside IOKit (1.6 test build, Check Light).
    private static let reader: (client: AnyObject, service: AnyObject, copy: CopyEvent, get: GetFloat)? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOHIDEventSystemClientCreate"), let m = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let s = dlsym(h, "IOHIDEventSystemClientCopyServices"), let e = dlsym(h, "IOHIDServiceClientCopyEvent"),
              let f = dlsym(h, "IOHIDEventGetFloatValue"),
              let client = unsafeBitCast(c, to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        unsafeBitCast(m, to: SetMatching.self)(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 4] as CFDictionary)
        guard let services = unsafeBitCast(s, to: CopyServices.self)(client)?.takeRetainedValue() as? [AnyObject],
              let service = services.first else { return nil }
        return (client, service, unsafeBitCast(e, to: CopyEvent.self), unsafeBitCast(f, to: GetFloat.self))
    }()

    /// `lux()`, giving the sensor up to ~120 ms for a first reading when it has one but hasn't answered yet. Returns at
    /// once on a Mac with no sensor.
    static func settledLux() async -> Double? {
        guard reader != nil else { return nil }
        for _ in 0..<5 {
            if let lux = lux() { return lux }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return lux()
    }

    /// The light falling on the screen's bezel now, in lux.
    static func lux() -> Double? {
        guard let r = reader, let event = r.copy(r.service, eventType, 0, 0)?.takeRetainedValue() else { return nil }
        let v = r.get(event, luxField)
        return v.isFinite && v >= 0 ? v : nil
    }
}
