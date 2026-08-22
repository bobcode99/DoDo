//
//  DownloadPayloadValidatorTests.swift
//  PodcastAnalyzerTests
//
//  A rotted enclosure URL commonly answers 200 with an HTML error page, which
//  URLSession reports as a successful download. Without a payload check the
//  file is filed as audio and only fails at play time, far from the cause.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@Suite("Download payload validation")
struct DownloadPayloadValidatorTests {

    @Test("Real audio passes")
    func acceptsAudio() {
        #expect(
            DownloadPayloadValidator.rejectionReason(
                fileSize: 40_000_000, contentType: "audio/mpeg"
            ) == nil
        )
    }

    @Test("An HTML error page served as an episode is rejected")
    func rejectsHTMLErrorPage() {
        #expect(
            DownloadPayloadValidator.rejectionReason(
                fileSize: 2_000, contentType: "text/html"
            ) != nil
        )
    }

    @Test("Content-Type parameters don't defeat the text check")
    func rejectsHTMLWithCharsetParameter() {
        #expect(
            DownloadPayloadValidator.rejectionReason(
                fileSize: 30_000, contentType: "text/html; charset=utf-8"
            ) != nil
        )
    }

    @Test("An empty or truncated download is rejected whatever it claims to be")
    func rejectsTruncatedAudio() {
        #expect(
            DownloadPayloadValidator.rejectionReason(
                fileSize: 512, contentType: "audio/mpeg"
            ) != nil
        )
    }

    @Test("A short trailer is not rejected for being small alone")
    func acceptsShortAudio() {
        // Under the suspicious threshold, but the type is audio — size alone
        // must not reject it, or legitimate trailers break.
        #expect(
            DownloadPayloadValidator.rejectionReason(
                fileSize: 400_000, contentType: "audio/mpeg"
            ) == nil
        )
    }

    @Test("A missing Content-Type is judged on size alone")
    func acceptsAudioWithoutContentType() {
        #expect(
            DownloadPayloadValidator.rejectionReason(
                fileSize: 400_000, contentType: nil
            ) == nil
        )
    }
}
