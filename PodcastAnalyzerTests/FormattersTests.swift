//
//  FormattersTests.swift
//  PodcastAnalyzerTests
//
//  Two things here reach the user constantly and are easy to get wrong without
//  noticing: the speed menu (seven stops that must render as seven *different*
//  labels, or the picker shows duplicates), and the playback clock, which is fed
//  `AVPlayer` durations that are routinely NaN before an item loads — and
//  `Int(Double.nan)` traps.
//
//  The relative-date branch exists because `RelativeDateTimeFormatter` produces
//  English abbreviations for Chinese locales; these tests pin the hand-written
//  Chinese output, including the Simplified/Traditional split.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Formatters")
struct FormattersTests {

    // MARK: - Playback speed

    @Test("A whole-number speed renders without a decimal point")
    func formatsWholeSpeeds() {
        #expect(Formatters.formatSpeed(1.0) == "1x")
        #expect(Formatters.formatSpeed(2.0) == "2x")
    }

    @Test("A fractional speed keeps its fraction")
    func formatsFractionalSpeeds() {
        #expect(Formatters.formatSpeed(0.5) == "0.5x")
        #expect(Formatters.formatSpeed(1.5) == "1.5x")
    }

    @Test("Every selectable speed produces a distinct label")
    func speedLabelsAreDistinct() {
        let labels = Formatters.playbackSpeeds.map(Formatters.formatSpeed)
        #expect(Set(labels).count == Formatters.playbackSpeeds.count)
        #expect(labels.allSatisfy { $0.hasSuffix("x") })
    }

    @Test("The speed stops are ordered and bracket normal playback")
    func speedStopsAreSane() {
        let speeds = Formatters.playbackSpeeds
        #expect(speeds == speeds.sorted())
        #expect(speeds.contains(1.0))
        #expect(speeds.first! > 0)
    }

    // MARK: - Playback clock

    @Test("Times under an hour render as M:SS")
    func formatsShortTimes() {
        #expect(Formatters.formatPlaybackTime(0) == "0:00")
        #expect(Formatters.formatPlaybackTime(9) == "0:09")
        #expect(Formatters.formatPlaybackTime(90) == "1:30")
        #expect(Formatters.formatPlaybackTime(3599) == "59:59")
    }

    @Test("Times of an hour or more gain an hours field with padded minutes")
    func formatsLongTimes() {
        #expect(Formatters.formatPlaybackTime(3600) == "1:00:00")
        #expect(Formatters.formatPlaybackTime(3661) == "1:01:01")
        #expect(Formatters.formatPlaybackTime(36_000) == "10:00:00")
    }

    @Test("NaN, infinite and negative durations fall back to 0:00 instead of trapping")
    func guardsAgainstNonFiniteDurations() {
        #expect(Formatters.formatPlaybackTime(.nan) == "0:00")
        #expect(Formatters.formatPlaybackTime(.infinity) == "0:00")
        #expect(Formatters.formatPlaybackTime(-.infinity) == "0:00")
        #expect(Formatters.formatPlaybackTime(-1) == "0:00")
    }

    @Test("A fractional second is truncated, never rounded into the next second")
    func truncatesFractionalSeconds() {
        #expect(Formatters.formatPlaybackTime(59.99) == "0:59")
    }

    // MARK: - Relative dates

    private func date(_ reference: Date, minusDays days: Int = 0, minusHours hours: Int = 0,
                      minusMinutes minutes: Int = 0) -> Date {
        reference.addingTimeInterval(
            -TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60))
    }

    @Test("Traditional Chinese uses its own unit words")
    func formatsTraditionalChinese() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let locale = Locale(identifier: "zh-Hant-TW")

        #expect(Formatters.formatRelativeDate(date(now, minusDays: 1), relativeTo: now, locale: locale)
                == "1天前")
        #expect(Formatters.formatRelativeDate(date(now, minusHours: 2), relativeTo: now, locale: locale)
                == "2小時前")
        #expect(Formatters.formatRelativeDate(date(now, minusMinutes: 5), relativeTo: now, locale: locale)
                == "5分鐘前")
        #expect(Formatters.formatRelativeDate(date(now, minusDays: 8), relativeTo: now, locale: locale)
                == "1週前")
    }

    @Test("Simplified Chinese swaps in the Simplified forms of the same units")
    func formatsSimplifiedChinese() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let locale = Locale(identifier: "zh-Hans-CN")

        #expect(Formatters.formatRelativeDate(date(now, minusHours: 2), relativeTo: now, locale: locale)
                == "2小时前")
        #expect(Formatters.formatRelativeDate(date(now, minusMinutes: 5), relativeTo: now, locale: locale)
                == "5分钟前")
        #expect(Formatters.formatRelativeDate(date(now, minusDays: 8), relativeTo: now, locale: locale)
                == "1周前")
        // Shared between both scripts.
        #expect(Formatters.formatRelativeDate(date(now, minusDays: 3), relativeTo: now, locale: locale)
                == "3天前")
    }

    @Test("Anything under a minute reads as 'just now' in the right script")
    func formatsJustNow() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let moments = now.addingTimeInterval(-5)

        #expect(Formatters.formatRelativeDate(moments, relativeTo: now,
                                              locale: Locale(identifier: "zh-Hant-TW")) == "剛剛")
        #expect(Formatters.formatRelativeDate(moments, relativeTo: now,
                                              locale: Locale(identifier: "zh-Hans-CN")) == "刚刚")
    }

    @Test("A date months back reports months, not a huge day count")
    func formatsMonthsAndYears() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let locale = Locale(identifier: "zh-Hans-CN")

        #expect(Formatters.formatRelativeDate(date(now, minusDays: 40), relativeTo: now, locale: locale)
                == "1个月前")
        #expect(Formatters.formatRelativeDate(date(now, minusDays: 400), relativeTo: now, locale: locale)
                == "1年前")
    }

    @Test("Non-Chinese locales fall through to Foundation and still say something")
    func formatsEnglishViaFoundation() {
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let english = Formatters.formatRelativeDate(
            date(now, minusDays: 1), relativeTo: now, locale: Locale(identifier: "en_US"))

        // The exact abbreviation is Foundation's to choose and shifts between OS
        // releases; what matters is that it is localised, non-empty, and not the
        // hand-written Chinese string.
        #expect(english.isEmpty == false)
        #expect(english != "1天前")
        #expect(english.contains("1"))
    }
}
