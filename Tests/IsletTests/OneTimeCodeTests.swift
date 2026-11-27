import XCTest
@testable import Islet

final class OneTimeCodeTests: XCTestCase {
    func testFindsCodes() {
        let samples: [(String, String)] = [
            ("Your verification code is 482913", "482913"),
            ("G-731942 is your Google verification code.", "731942"),
            ("123456 is your Instagram code. Don't share it.", "123456"),
            ("Your Apple Account code is: 845 221. Don't share it with anyone.", "845221"),
            ("Use 9182 to sign in to Uber", "9182"),
            ("Your one-time passcode is 77881234", "77881234"),
            ("Amazon: Your OTP is 304-118. Valid for 10 minutes.", "304118"),
            ("WhatsApp code 612-907. You can also tap this link to verify your phone: v.whatsapp.com/612907", "612907"),
            ("Tu código de verificación es 4417", "4417"),
            ("Your security code is 3381. It expires at 10:30.", "3381"),
        ]
        for (text, code) in samples { XCTAssertEqual(OneTimeCode.find(in: text), code, text) }
    }

    func testIgnoresOtherNumbers() {
        let samples = [
            "Are you coming for dinner tonight? Bring 2 bottles.",
            "Your order #123456 has shipped",
            "Shipping update: arrives Friday 2026",
            "You paid $1250 to Sam",
            "Call me at 555-123-4567",
            "Battery is at 1000 cycles",
            "Meeting moved to 14:30",
            "Your code review is ready",
            "Total 1,234.56 due 12/05",
            "New login from Safari on 4 May 2026",
            "Use code SAVE20 for 20% off",
        ]
        for text in samples { XCTAssertNil(OneTimeCode.find(in: text), text) }
    }
}
