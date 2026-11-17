//
//  AppLogTests.swift
//  CineMatchTests
//

import Foundation
import Testing
@testable import CineMatch

struct AppLogTests {

    @Test func errorIncludesTheUnderlyingErrorDetails() {
        let log = AppLog()

        log.error("allSignals failed", URLError(.notConnectedToInternet))

        let entry = log.allEntries.first
        #expect(entry?.level == .error)
        #expect(entry?.message.hasPrefix("allSignals failed: ") == true)
        #expect(entry?.message.contains("notConnectedToInternet") == true || entry?.message.contains("-1009") == true)
    }

    @Test func sourceIsTheFileName() {
        #expect(AppLog.source(from: "CineMatch/SupabaseTasteSignalService.swift") == "SupabaseTasteSignalService")
        #expect(AppLog().allEntries.isEmpty)

        let log = AppLog()
        log.info("hello")
        #expect(log.allEntries.first?.source == "AppLogTests")
    }

    @Test func oldestEntriesAreDroppedAtCapacity() {
        let log = AppLog(capacity: 3)

        for number in 1...5 { log.info("line \(number)") }

        #expect(log.allEntries.map(\.message) == ["line 3", "line 4", "line 5"])
    }

    @Test func reportHasHeaderAndAllLines() {
        let log = AppLog()
        log.info("Supabase: configured")
        log.error("Rate: load failed")

        let report = log.report()

        #expect(report.hasPrefix("CineMatch "))
        #expect(report.contains("[INFO] AppLogTests: Supabase: configured"))
        #expect(report.contains("[ERROR] AppLogTests: Rate: load failed"))
    }

    @Test func emptyReportSaysSo() {
        #expect(AppLog().report().hasSuffix("(empty)"))
    }
}
