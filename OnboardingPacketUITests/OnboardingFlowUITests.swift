import UIKit
import XCTest

/// Drives the packet the way a branch adviser does with a customer:
/// fill the account opening form, try to sign too early, finish the form,
/// sign it with a drawn signature, flatten and share it, complete the identity
/// verification record with two signatures, then start the consent form.
///
/// The values are fictitious. Text is entered with the keyboard's Paste button,
/// because the Nutrient form editor does not expose its text input to UI tests.
/// Set SHOT_DIR to a folder to also save the screenshots as PNG files.
final class OnboardingFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testOnboardingPacket() throws {
        startNewPacket()

        // Account opening application: page 1.
        openForm("account-opening")
        type("Ms", into: "title")
        type("Ava", into: "first_name")
        type("Thompson", into: "last_name")
        pickDate(into: "date_of_birth", year: "1988", month: "April", day: "12")
        type("Canadian", into: "nationality")
        type("+1 555 0142", into: "mobile_phone")
        type("ava.thompson@example.com", into: "email")
        type("48 Larkfield Road", into: "address_line1")
        type("Apartment 5", into: "address_line2")
        type("Brookhaven", into: "city")
        type("K2P 0A9", into: "postal_code")
        type("Canada", into: "country")
        tap("employment_status.0")
        type("Product designer", into: "occupation")

        // Signing before the form is complete is refused, with the missing fields listed.
        tap("customer_signature")
        let alert = app.alerts["Complete the form before signing"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Source of funds'")).firstMatch.exists)
        screenshot("02-check-before-signing")
        alert.buttons["OK"].tap()

        // A row of the checklist goes to the page of its field.
        app.staticTexts["Date"].firstMatch.tap()
        sleep(2)
        let pdfFrame = app.otherElements["PDF View"].firstMatch.frame
        let dateFrame = field("signature_date").frame
        XCTAssertTrue(pdfFrame.contains(CGPoint(x: dateFrame.midX, y: dateFrame.midY)), "The date field is not on screen")

        // Page 2.
        tap("account_type.0")
        type("2500", into: "initial_deposit")
        type("Salary", into: "source_of_funds")
        tap("debit_card")
        tap("online_banking")
        type("Canada", into: "tax_country")
        tap("declaration_true")
        tap("terms_accepted")
        pickTodaysDate(into: "signature_date")

        // Ready: the primary button now says Sign.
        let primary = app.buttons["primary-action"]
        XCTAssertTrue(primary.waitForLabel("Sign", timeout: 5))
        sign("customer_signature")
        XCTAssertTrue(primary.waitForLabel("Finish and share", timeout: 5))
        primary.tap()

        // Completed: flattened PDF, checks and JSON, then the share sheet.
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["0 form fields left"].exists)
        sleep(2)
        screenshot("03-completed-form")
        app.buttons["share"].tap()
        // The share sheet runs in a system process; its popover is visible to the test.
        XCTAssertTrue(app.otherElements["PopoverDismissRegion"].waitForExistence(timeout: 10), "No share sheet")
        sleep(2)
        dismissShareSheet()
        app.navigationBars.buttons["Onboarding packet"].tap()

        // Identity verification record: two signatures, customer and staff member.
        openForm("identity-verification")
        type("Ava Thompson", into: "customer_name")
        tap("id_document_type.0")
        type("PX4821937", into: "id_document_number")
        type("Canada", into: "id_issuing_country")
        pickDate(into: "id_expiry_date", year: "2031", month: "March", day: "14")
        tap("address_proof.0")
        tap("verification_channel.1")
        type("Daniel Okafor", into: "staff_name")
        type("AG-2207", into: "staff_id")
        tap("originals_seen")
        pickTodaysDate(into: "verification_date")
        pickTodaysDate(into: "staff_signature_date")
        sign("verification_customer_signature")
        XCTAssertTrue(primary.waitForLabel("Sign", timeout: 5), "One signature is still missing")
        sign("staff_signature", strokes: Self.staffInitials)
        XCTAssertTrue(primary.waitForLabel("Finish and share", timeout: 5))
        primary.tap()
        XCTAssertTrue(app.staticTexts["Completed"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["0 form fields left"].exists)
        app.navigationBars.buttons["Onboarding packet"].tap()

        // Consent form: started, not finished.
        openForm("privacy-consent")
        type("Ava Thompson", into: "full_name")
        tap("privacy_notice_read")
        tap("marketing_email")
        app.navigationBars.buttons["Onboarding packet"].tap()

        XCTAssertTrue(app.staticTexts["2 of 3 forms completed"].waitForExistence(timeout: 5))
        sleep(1)
        screenshot("01-packet-progress")
    }

    // MARK: Steps

    private func startNewPacket() {
        let reset = app.buttons["New packet"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
        app.buttons["Clear all forms"].tap()
        XCTAssertTrue(app.staticTexts["0 of 3 forms completed"].waitForExistence(timeout: 5))
    }

    private func openForm(_ id: String) {
        app.buttons["form-\(id)"].firstMatch.tap()
        XCTAssertTrue(app.buttons["primary-action"].waitForExistence(timeout: 10))
        sleep(1)
    }

    private func field(_ id: String) -> XCUIElement {
        app.otherElements[id].firstMatch
    }

    /// Scrolls the document until the field is in the upper part of the screen, above the keyboard.
    private func reveal(_ id: String) -> XCUIElement {
        let element = field(id)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "No field \(id)")
        let pdf = app.otherElements["PDF View"].firstMatch
        for _ in 0..<10 {
            let frame = element.frame
            let top = pdf.frame.minY + 120
            let bottom = pdf.frame.minY + pdf.frame.height * 0.55
            if frame.minY >= top && frame.maxY <= bottom && element.isHittable { break }
            let delta = frame.midY - (top + bottom) / 2
            let distance = min(max(abs(delta), 60), pdf.frame.height * 0.4) / pdf.frame.height
            let from = pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
            let to = pdf.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: delta > 0 ? 0.5 - distance : 0.5 + distance))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 600, thenHoldForDuration: 0.3)
        }
        return element
    }

    private func tap(_ id: String) {
        reveal(id).tap()
        dismissTips()
    }

    private func type(_ text: String, into id: String) {
        tap(id)
        let paste = app.buttons["assistantPaste:forEvent:"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "No keyboard for \(id)")
        UIPasteboard.general.string = text
        paste.tap()
        dismissTips()
    }

    /// Nutrient shows a calendar for fields with a date format. It starts on today's date.
    private func pickTodaysDate(into id: String) {
        tap(id)
        let done = app.popovers.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    private func pickDate(into id: String, year: String, month: String, day: String) {
        tap(id)
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        popover.buttons["DatePicker.Show"].tap()
        let wheels = popover.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 5))
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: month)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: year)
        popover.buttons["DatePicker.Hide"].tap()
        // Day buttons are labelled like "Tuesday 12 April" or "Tuesday, April 12" depending on the region.
        let dayButton = NSPredicate(format: "label CONTAINS %@ AND label MATCHES %@", month, ".*\\b\(day)\\b.*")
        popover.buttons.matching(dayButton).firstMatch.tap()
        popover.buttons["Done"].tap()
    }

    /// Initials drawn as straight strokes: XCUITest drags in straight lines, one stroke per drag.
    private typealias Stroke = [(Double, Double)]
    private static let customerInitials: [Stroke] = [
        [(0.20, 0.70), (0.30, 0.24), (0.40, 0.70)],             // A
        [(0.24, 0.52), (0.37, 0.50)],
        [(0.46, 0.28), (0.74, 0.25)],                           // T
        [(0.60, 0.26), (0.57, 0.70)],
        [(0.14, 0.82), (0.86, 0.75)],                           // underline
    ]
    private static let staffInitials: [Stroke] = [
        [(0.22, 0.26), (0.22, 0.70)],                           // D
        [(0.22, 0.26), (0.34, 0.30), (0.40, 0.48), (0.34, 0.66), (0.22, 0.70)],
        [(0.58, 0.26), (0.68, 0.34), (0.70, 0.50), (0.66, 0.64), (0.56, 0.70),
         (0.48, 0.62), (0.47, 0.44), (0.51, 0.31), (0.58, 0.26)],  // O
        [(0.16, 0.80), (0.84, 0.82)],                           // underline
    ]

    /// Taps the signature field and draws the initials in the Nutrient signature sheet.
    private func sign(_ id: String, strokes: [Stroke] = customerInitials) {
        tap(id)
        let canvas = app.otherElements["Signature Area"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "No signature sheet for \(id)")
        for stroke in strokes {
            for (a, b) in zip(stroke, stroke.dropFirst()) {
                let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: a.0, dy: a.1))
                let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: b.0, dy: b.1))
                from.press(forDuration: 0.05, thenDragTo: to, withVelocity: 500, thenHoldForDuration: 0)
            }
        }
        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled, "The signature was not drawn")
        add.tap()
        sleep(1)
    }

    private func dismissShareSheet() {
        // The share sheet is a popover on iPad: tapping outside closes it.
        let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.waitForExistence(timeout: 3) {
            dismiss.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        }
        sleep(1)
    }

    /// iPadOS shows a one-time tip about editing gestures the first time a text field is used.
    private func dismissTips() {
        let next = app.buttons["Continue"]
        var count = 0
        while next.waitForExistence(timeout: 0.6) && count < 4 {
            next.tap()
            count += 1
        }
    }

    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOT_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? shot.pngRepresentation.write(to: url)
        }
    }
}

private extension XCUIElement {
    func waitForLabel(_ label: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
