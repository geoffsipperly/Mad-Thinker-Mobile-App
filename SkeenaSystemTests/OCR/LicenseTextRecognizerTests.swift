import XCTest
import Foundation
import CoreGraphics

@testable import SkeenaSystem

final class OCRParsingUnitTests: XCTestCase {

    // MARK: - Helpers

    /// Normalize DOB string by parsing known formats and returning ISO8601 date string "YYYY-MM-DD".
    /// Used here only for cross-checking expected results.
    static func normalizeDOBToISO(_ dobString: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        // Try "MMM d, yyyy"
        formatter.dateFormat = "MMM d, yyyy"
        if let date = formatter.date(from: dobString) {
            return ISO8601DateFormatter().string(from: date).prefix(10).description
        }

        // Try "MM/dd/yyyy"
        formatter.dateFormat = "MM/dd/yyyy"
        if let date = formatter.date(from: dobString) {
            return ISO8601DateFormatter().string(from: date).prefix(10).description
        }

        // Try "yyyy-MM-dd"
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: dobString) {
            return ISO8601DateFormatter().string(from: date).prefix(10).description
        }

        return nil
    }

    struct TestOCRLine { let text: String }
    struct TestOCRScanResult { let fullText: String; let lines: [TestOCRLine] }

    // MARK: - Tests

    func testNormalizeDOBToISO() {
        let fullText = "Some text\nDate of Birth: Mar 7, 1986\nMore text"
        guard let dobRange = fullText.range(of: "Date of Birth:") else {
            XCTFail("DOB label missing"); return
        }
        let dobStringStart = fullText.index(dobRange.upperBound, offsetBy: 1)
        let dobString = fullText[dobStringStart...].components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = Self.normalizeDOBToISO(dobString)
        XCTAssertEqual(normalized, "1986-03-07")
    }

    func testExtractTelephone() {
        let fullText = """
        Customer service phone: (604) 555-1234
        Please call for assistance.
        """
        let pattern = #"\(?\d{3}\)?[-\s.]?\d{3}[-\s.]?\d{4}"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: fullText, options: [], range: NSRange(fullText.startIndex..., in: fullText))
        XCTAssertFalse(matches.isEmpty, "No phone number found")
        if let match = matches.first {
            let range = Range(match.range, in: fullText)!
            let phone = String(fullText[range])
            XCTAssertTrue(phone.contains("555"))
            XCTAssertTrue(phone.contains("1234"))
        }
    }

    func testResidencyNormalization() {
        func extractResidency(from text: String) -> String? {
            guard let range = text.range(of: "Residency:") else { return nil }
            return text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let fullText1 = "Residency: NOT A CANADIAN RESIDENT"
        let residency1 = extractResidency(from: fullText1)
        XCTAssertEqual(residency1, "NOT A CANADIAN RESIDENT")
        let fullText2 = "Residency: B.C. Resident"
        let residency2 = extractResidency(from: fullText2)
        XCTAssertEqual(residency2, "B.C. Resident")
    }

    func testNameParsingFromLabeledLines() {
        let fullText = """
        Licensee: DOE, JOHN
        Some other info here
        """
        guard let labelRange = fullText.range(of: "Licensee:") else { XCTFail("Licensee label missing"); return }
        let rawName = fullText[labelRange.upperBound...].components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        func parseLastCommaFirstName(_ input: String) -> String {
            let parts = input.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return input.capitalized }
            let lastName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let firstNamePart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let firstNames = firstNamePart.split(separator: " ").map { $0.capitalized }
            let firstName = firstNames.joined(separator: " ")
            return "\(firstName) \(lastName.capitalized)"
        }
        let parsedName = parseLastCommaFirstName(rawName)
        XCTAssertEqual(parsedName, "John Doe")
    }

    func testLicenseExtractionFallback() {
        let fullText = "This text contains ABC123456 somewhere in the text."
        let tokens = fullText.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        let licenseNumber = tokens.first(where: { $0.range(of: #"^[A-Z0-9]{8,}$"#, options: .regularExpression) != nil })
        XCTAssertEqual(licenseNumber, "ABC123456")
    }

    func testExtractLastCommaFirstHelper() {
        let line = "SMITH, JANE MIDDLE"
        func parseLastCommaFirstName(_ input: String) -> String {
            let parts = input.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { return input.capitalized }
            let lastName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let firstNamePart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let firstNames = firstNamePart.split(separator: " ").map { $0.capitalized }
            let firstName = firstNames.joined(separator: " ")
            return "\(firstName) \(lastName.capitalized)"
        }
        let parsedName = parseLastCommaFirstName(line)
        XCTAssertEqual(parsedName, "Jane Middle Smith")
    }

    @MainActor func testOptionsDefaults() {
        let options = FSELicenseTextRecognizer.Options()
        XCTAssertEqual(options.recognitionLanguages, ["en-CA", "en-US"])
        XCTAssertEqual(options.region, .auto)
    }

    func testResultStructsExistAndAreUsable() {
        let classified = ClassifiedLicenceParse(
            licNumber: "ABC123456",
            water: "Some Water",
            validFrom: nil,
            validTo: nil,
            guideName: "",
            vendor: ""
        )
        let result = FSELicenseScanResult(
            fullText: "some recognized text",
            name: "John Doe",
            licenseNumber: "ABC123456",
            classifiedLicences: [classified],
            dobISO8601: "1986-03-07",
            telephone: "(604) 555-1234",
            residency: "B.C. Resident"
        )
        XCTAssertEqual(result.fullText, "some recognized text")
        XCTAssertEqual(result.name, "John Doe")
        XCTAssertEqual(result.licenseNumber, "ABC123456")
        XCTAssertEqual(result.classifiedLicences.count, 1)
        XCTAssertEqual(result.dobISO8601, "1986-03-07")
        XCTAssertEqual(result.telephone, "(604) 555-1234")
        XCTAssertEqual(result.residency, "B.C. Resident")
    }

    func testDocumentationRegexPatterns() {
        let phonePattern = #"\(?\d{3}\)?[-\s.]?\d{3}[-\s.]?\d{4}"#
        let phoneRegex = try! NSRegularExpression(pattern: phonePattern)
        let phoneTestString = "Call me at (604) 555-1234"
        let phoneMatches = phoneRegex.matches(in: phoneTestString, range: NSRange(phoneTestString.startIndex..., in: phoneTestString))
        XCTAssertFalse(phoneMatches.isEmpty)

        let datePattern = #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]* \d{1,2}, \d{4}"#
        let dateRegex = try! NSRegularExpression(pattern: datePattern)
        let dateTestString = "Date of Birth: Mar 7, 1986"
        let dateMatches = dateRegex.matches(in: dateTestString, range: NSRange(dateTestString.startIndex..., in: dateTestString))
        XCTAssertFalse(dateMatches.isEmpty)
    }
}

