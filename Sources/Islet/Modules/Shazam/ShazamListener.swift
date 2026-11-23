import AppKit
import AVFoundation
import OSLog
import ShazamKit

/// A song Shazam found.
struct ShazamSong: Equatable {
    var title: String
    var artist: String
    var artwork: NSImage?
    var artworkURL: URL?
    /// Where a click goes: Apple Music when Shazam knows the song there, else its Shazam page.
    var url: URL?
}

/// Names the song playing near the Mac (DESIGN.md "Shazam"). ShazamKit's managed session records from the microphone,
/// sends a signature (not the audio) to Shazam and answers with the song. Asks for the microphone the first time.
@MainActor
final class ShazamListener {
    enum Outcome: Equatable {
        case match(ShazamSong)
        case noMatch
        /// The microphone is off for Dynamic Peninsula: a click opens its pane in System Settings.
        case micDenied
        case failed(String)
    }

    /// Long enough for a quiet room or a song between verses, short enough not to feel stuck.
    static let timeout: Double = 15

    private var session: SHManagedSession?
    private var task: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var timedOut = false
    private let log = Logger(subsystem: "com.marcogad.islet", category: "shazam")

    var listening: Bool { task != nil }

    /// Starts listening; `done` is called once, on the main actor, unless `cancel()` comes first.
    func listen(done: @escaping (Outcome) -> Void) {
        cancel()
        timedOut = false
        task = Task { [weak self] in
            guard await Self.microphoneAllowed() else {
                guard !Task.isCancelled else { return }
                self?.finish(.micDenied, done)
                return
            }
            guard !Task.isCancelled, let self else { return }
            let session = SHManagedSession()
            self.session = session
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeout))
                guard !Task.isCancelled, let self else { return }
                self.timedOut = true
                self.session?.cancel()
            }
            await session.prepare()
            let result = await session.result()
            guard !Task.isCancelled else { return }
            switch result {
            case .match(let match):
                guard let item = match.mediaItems.first else { self.finish(.noMatch, done); return }
                var song = ShazamSong(title: item.title ?? "Unknown song", artist: item.artist ?? "",
                                      artworkURL: item.artworkURL, url: item.appleMusicURL ?? item.webURL)
                // Into the Shazam library, as the system's Music Recognition does, so it's in Shazam's history on
                // the iPhone too.
                Task { try? await SHLibrary.default.addItems([item]) }
                if let url = item.artworkURL { song.artwork = await Self.image(url) }
                guard !Task.isCancelled else { return }
                self.finish(.match(song), done)
            case .noMatch:
                self.finish(.noMatch, done)
            case .error(let error, _):
                if self.timedOut { self.finish(.noMatch, done); return }
                self.log.error("Shazam failed: \(String(describing: error), privacy: .public)")
                self.finish(.failed(Self.message(error)), done)
            }
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        timeoutTask?.cancel(); timeoutTask = nil
        session?.cancel(); session = nil
    }

    private func finish(_ outcome: Outcome, _ done: (Outcome) -> Void) {
        timeoutTask?.cancel(); timeoutTask = nil
        // The session has already answered: cancelling it now crashes inside ShazamKit (EXC_BAD_ACCESS, 2026-11-23).
        session = nil
        task = nil
        done(outcome)
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private static func image(_ url: URL) async -> NSImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }

    private static func message(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return "No internet connection" }
        if ns.domain == SHErrorDomain {
            switch SHError.Code(rawValue: ns.code) {
            case .matchAttemptFailed?: return "Couldn't reach Shazam"
            case .audioDiscontinuity?, .invalidAudioFormat?: return "Couldn't hear the microphone"
            default: break
            }
        }
        return "Shazam isn't available"
    }
}
