import Foundation

/// Finds a sign-in code (2FA, verification, one-time passcode) in a notification, so the card can offer to copy it
/// (DESIGN.md "Notifications", "Codes"). Only digits count (4 to 8, or "123-456" / "123 456"), and only when the text
/// also says it is a code; the number nearest that word wins.
enum OneTimeCode {
    /// Words that say a number is a code. Lowercased; matched anywhere in the lowercased text.
    private static let keywords = [
        "code", "passcode", "password", "verification", "verify", "one-time", "one time", "otp", "2fa", "two-factor",
        "two factor", "authentication", "authenticate", "security", "pin", "sign-in", "sign in", "log in", "login",
        "confirm", "token", "código", "codice", "kode", "kod", "验证码", "認証", "인증",
    ]

    /// Digits 4-8 long, or 3+3 with a dash or space, not part of a longer number, an amount, a time, a date, a link or
    /// a phone number. Google's "G-123456" counts as 123456.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}$€£¥+#@/:.,_-])(?:g-)?(\d{3}[- ]\d{3}|\d{4,8})(?![\p{L}\p{N}%$€£¥/:_]|[.,]\d|-\d| \d)"#)

    static func find(in text: String) -> String? {
        let lower = text.lowercased()
        let ns = lower as NSString
        var hits: [Int] = []
        for k in keywords {
            var r = ns.range(of: k)
            while r.location != NSNotFound {
                // "pin" and "kod" only as whole words ("shipping", "Kodak" aren't codes).
                if k.count > 3 || isWord(r, in: ns) { hits.append(r.location + r.length / 2) }
                let next = r.location + r.length
                r = ns.range(of: k, range: NSRange(location: next, length: ns.length - next))
            }
        }
        guard !hits.isEmpty else { return nil }
        let matches = pattern.matches(in: lower, range: NSRange(location: 0, length: ns.length))
            .filter { !isYear($0.range(at: 1), in: ns) }
        let best = matches.min { a, b in distance(a.range, hits) < distance(b.range, hits) }
        guard let r = best?.range(at: 1) else { return nil }
        return ns.substring(with: r).filter(\.isNumber)
    }

    private static func distance(_ r: NSRange, _ hits: [Int]) -> Int {
        let mid = r.location + r.length / 2
        return hits.map { abs($0 - mid) }.min() ?? .max
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "4 May 2026": a year after a month name, not a code.
    private static func isYear(_ r: NSRange, in s: NSString) -> Bool {
        guard r.length == 4, let n = Int(s.substring(with: r)), (1950...2099).contains(n) else { return false }
        let start = max(0, r.location - 14)
        let before = s.substring(with: NSRange(location: start, length: r.location - start))
        return months.contains { before.contains($0) }
    }

    private static func isWord(_ r: NSRange, in s: NSString) -> Bool {
        func letter(at i: Int) -> Bool {
            guard i >= 0, i < s.length, let u = UnicodeScalar(s.character(at: i)) else { return false }
            return CharacterSet.letters.contains(u)
        }
        return !letter(at: r.location - 1) && !letter(at: r.location + r.length)
    }
}
