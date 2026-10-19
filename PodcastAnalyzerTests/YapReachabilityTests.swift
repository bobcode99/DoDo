//
//  YapReachabilityTests.swift
//  PodcastAnalyzerTests
//
//  A job is only submitted once `/health` answers, so a server that isn't
//  running fails in seconds with "can't reach" rather than after the 60s
//  URLSession.shared default.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@Suite("Yap server reachability probe")
struct YapReachabilityTests {

    @Test("A server that isn't listening fails fast as unreachable")
    func closedPortFailsFast() async throws {
        let base = try #require(URL(string: "http://127.0.0.1:9"))
        let start = ContinuousClock.now

        let error = await #expect(throws: URLError.self) {
            try await YapTranscriptService().ensureReachable(baseURL: base, apiKey: nil)
        }

        #expect(error?.code == .cannotConnectToHost)
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
