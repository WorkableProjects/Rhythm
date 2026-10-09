import XCTest
@testable import RhythmCore

final class QuicklinkValidatorTests: XCTestCase {
    func testValidHTTPSURL() throws {
        let result = try QuicklinkURLValidator.validate("  https://classroom.google.com/u/0 \n").get()
        XCTAssertEqual(result.kind, .website)
        XCTAssertEqual(result.url.absoluteString, "https://classroom.google.com/u/0")
        XCTAssertNil(result.warning)
    }

    func testHTTPIsAllowedWithWarning() throws {
        let result = try QuicklinkURLValidator.validate("http://example.com").get()
        XCTAssertEqual(result.kind, .website)
        XCTAssertNotNil(result.warning)
    }

    func testEmptyURL() {
        XCTAssertEqual(QuicklinkURLValidator.validate("   ").failure, .empty)
    }

    func testMalformedURLs() {
        XCTAssertEqual(QuicklinkURLValidator.validate("https://exa mple.com").failure, .malformed)
        XCTAssertEqual(QuicklinkURLValidator.validate("https://").failure, .missingHost)
        XCTAssertEqual(QuicklinkURLValidator.validate("music:").failure, .malformed)
    }

    func testMissingSchemeOffersSuggestionButDoesNotRewrite() {
        XCTAssertEqual(QuicklinkURLValidator.validate("example.com/page").failure,
                       .missingScheme(suggestion: "https://example.com/page"))
        XCTAssertEqual(QuicklinkURLValidator.validate("hello").failure, .missingScheme(suggestion: nil))
    }

    func testBlockedSchemes() {
        XCTAssertEqual(QuicklinkURLValidator.validate("javascript:alert(1)").failure, .unsupportedScheme("javascript"))
        XCTAssertEqual(QuicklinkURLValidator.validate("file:///etc/hosts").failure, .unsupportedScheme("file"))
    }

    func testShortcutAndAppSchemes() throws {
        XCTAssertEqual(try QuicklinkURLValidator.validate("shortcuts://run-shortcut?name=Study%20Mode").get().kind, .shortcut)
        XCTAssertEqual(try QuicklinkURLValidator.validate("music://").get().kind, .app)
    }
}

final class ExportImportTests: XCTestCase {
    private func sampleExport() -> RhythmExport {
        let template = SampleTimetable.template()
        let pe = template.periods.last!
        return RhythmExport(
            exportedAt: Date(timeIntervalSince1970: 1_790_000_000),
            templates: [template],
            assignments: Weekday.schoolWeek.map { .init(weekday: $0, templateID: template.id) },
            overrides: [OverrideDefinition(date: Fixtures.friday, kind: .noSchool, title: "Holiday")],
            quicklinks: [QuicklinkDefinition(title: "Classroom", urlString: "https://classroom.google.com", kind: .website)],
            reminders: [ReminderDefinition(periodID: pe.id, title: "Bring gym clothes", trigger: .beforeStart(minutes: 15))]
        )
    }

    func testRoundTrip() throws {
        let export = sampleExport()
        let data = try ExportImportCodec.encode(export)
        let preview = try ExportImportCodec.decodeAndValidate(data).get()
        XCTAssertEqual(preview.export, export)
        XCTAssertEqual(preview.templateCount, 1)
        XCTAssertEqual(preview.periodCount, 7)
        XCTAssertEqual(preview.reminderCount, 1)
    }

    func testUnknownSchemaVersion() throws {
        var export = sampleExport()
        export.schemaVersion = 99
        let data = try ExportImportCodec.encode(export)
        XCTAssertEqual(ExportImportCodec.decodeAndValidate(data).failure, .unsupportedVersion(99))
    }

    func testMalformedData() {
        XCTAssertEqual(ExportImportCodec.decodeAndValidate(Data("not json".utf8)).failure, .malformed)
        XCTAssertEqual(ExportImportCodec.decodeAndValidate(Data(#"{"schemaVersion":1}"#.utf8)).failure, .malformed)
    }

    func testDuplicateID() throws {
        var export = sampleExport()
        export.quicklinks.append(QuicklinkDefinition(id: export.quicklinks[0].id, title: "Copy", urlString: "https://a.com", kind: .website))
        guard case .invalid(let problems) = try XCTUnwrap(ExportImportCodec.decodeAndValidate(ExportImportCodec.encode(export)).failure) else {
            return XCTFail("Expected invalid")
        }
        XCTAssertTrue(problems.contains { $0.contains("Duplicate ID") })
    }

    func testInvalidPeriodRangeAndOverlap() throws {
        var export = sampleExport()
        export.templates[0].periods[0].end = ClockTime(hour: 7, minute: 0)
        export.templates[0].periods[2].start = ClockTime(hour: 9, minute: 30)
        guard case .invalid(let problems) = try XCTUnwrap(ExportImportCodec.decodeAndValidate(ExportImportCodec.encode(export)).failure) else {
            return XCTFail("Expected invalid")
        }
        XCTAssertTrue(problems.contains { $0.contains("must end after it starts") })
        XCTAssertTrue(problems.contains { $0.contains("overlaps") })
    }

    func testInvalidRelationships() throws {
        var export = sampleExport()
        export.reminders[0].periodID = UUID()
        export.assignments.append(.init(weekday: .saturday, templateID: UUID()))
        guard case .invalid(let problems) = try XCTUnwrap(ExportImportCodec.decodeAndValidate(ExportImportCodec.encode(export)).failure) else {
            return XCTFail("Expected invalid")
        }
        XCTAssertTrue(problems.contains { $0.contains("missing period") })
        XCTAssertTrue(problems.contains { $0.contains("no longer exists") })
    }

    func testValidationIsPureAndDoesNotMutateInput() throws {
        let export = sampleExport()
        let copy = export
        _ = ExportImportCodec.validate(export)
        XCTAssertEqual(export, copy)
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
