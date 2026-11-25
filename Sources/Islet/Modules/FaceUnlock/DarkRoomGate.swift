import Foundation

/// Decides from the camera's mean brightness (`FrameLight.luma`, 0...1) whether the room is too dark for the face
/// scan, so the display can light the face at once (`FaceGlow.setFill`) instead of waiting for failed attempts.
///
/// Hysteresis, so it never flickers:
/// - on: `enterLuma` twice in a row, or one reading under `veryDarkLuma` (a plainly black frame);
/// - off: only above `exitLuma`, held for `exitSamples` readings, and not before `minOn` seconds. The exit level is
///   far above the entry one because the glow itself lights the scene: a dark room lit by the screen reads well over
///   `enterLuma`, and must not read as "bright" and switch the light off under the user's face.
/// The scan's first readings are ignored for `settle` seconds (a fresh camera's exposure starts dark in any room);
/// a camera already warm from the lock passes 0.
struct DarkRoomGate: Equatable {
    static let enterLuma = 0.25
    static let veryDarkLuma = 0.12
    static let exitLuma = 0.65
    static let enterSamples = 2
    static let exitSamples = 3
    static let minOn = 3.0

    private(set) var isDark = false
    private var darkRun = 0
    private var brightRun = 0
    private var onSince: Double?

    /// Feeds one reading taken `elapsed` seconds into the scan (after `settle` seconds of ignored settling).
    /// Returns the new state when it changed, else nil.
    @discardableResult
    mutating func feed(luma: Double, elapsed: Double, settle: Double) -> Bool? {
        guard elapsed >= settle else { return nil }
        if !isDark {
            darkRun = luma < Self.enterLuma ? darkRun + 1 : 0
            if luma < Self.veryDarkLuma || darkRun >= Self.enterSamples {
                isDark = true; onSince = elapsed; brightRun = 0
                return true
            }
        } else {
            brightRun = luma > Self.exitLuma ? brightRun + 1 : 0
            if brightRun >= Self.exitSamples, elapsed - (onSince ?? elapsed) >= Self.minOn {
                isDark = false; darkRun = 0; onSince = nil
                return false
            }
        }
        return nil
    }
}
