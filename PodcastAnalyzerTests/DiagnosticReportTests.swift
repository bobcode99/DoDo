//
//  DiagnosticReportTests.swift
//  PodcastAnalyzerTests
//
//  The shareable diagnostic report: it must carry the logs and context a
//  developer needs, and never the user's credentials.
//

import Foundation
import OSLog
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Diagnostic report", .serialized)
struct DiagnosticReportTests {

    @Test("The header names the problem and the settings, but never Yap's URL or key")
    func headerOmitsSecrets() {
        let defaults = UserDefaults.standard
        let saved = (defaults.object(forKey: "yap_server_url"), defaults.object(forKey: "yap_server_api_key"))
        defer {
            defaults.set(saved.0, forKey: "yap_server_url")
            defaults.set(saved.1, forKey: "yap_server_api_key")
        }
        defaults.set("http://192.168.1.50:8080", forKey: "yap_server_url")
        defaults.set("sk-secret-123", forKey: "yap_server_api_key")

        let header = DiagnosticReport.header(
            problem: "Transcription failed — 曼報 / EP134 — engine: appleSpeech",
            libraryStats: [("Subscribed podcasts", 6)]
        )

        #expect(header.contains("Problem: Transcription failed — 曼報 / EP134"))
        #expect(header.contains("Subscribed podcasts: 6"))
        #expect(header.contains("transcriptEngine:"))
        #expect(header.contains("subtitle_split_long_audio:"))
        #expect(header.contains("yap_server: configured"))
        #expect(!header.contains("192.168.1.50"), "a private server address must not leave the device")
        #expect(!header.contains("sk-secret-123"), "credentials must not leave the device")
    }

    @Test("The report carries this session's logs, read live, readable rather than <private>")
    func reportIncludesCurrentSessionLogs() throws {
        let marker = "diag-test-\(UUID().uuidString)"
        Logger(subsystem: "com.podcast.analyzer", category: "Test")
            .notice("Transcript started: \(marker, privacy: .public)")

        let url = try DiagnosticReport.makeFile(problem: "probe")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try String(contentsOf: url, encoding: .utf8)

        #expect(text.hasPrefix("=== DoDo diagnostic report ==="))
        #expect(text.contains("=== Current session"))
        #expect(text.contains("Transcript started: \(marker)"), "the report's log section used to be empty")
    }
}
