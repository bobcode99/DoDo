//
//  ReleaseScheduleGuesserTests.swift
//  PodcastAnalyzerTests
//
//  The cadence guess drives "new episode expected" copy and the background
//  refresh interval, so guessing *confidently wrong* is worse than guessing
//  nothing: a show declared daily that publishes monthly gets polled 30× too
//  often and shows a prediction that is always stale. The coefficient-of-
//  variation gate is what keeps that from happening, so it gets its own tests.
//
//  Dates are built through `Calendar.current` rather than raw epoch arithmetic
//  because the weekday-only branch asks the calendar what day something is.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Release schedule guessing")
struct ReleaseScheduleGuesserTests {

    private let calendar = Calendar.current

    /// A fixed, noon-anchored starting point so daylight-saving shifts can't
    /// move a date onto the neighbouring day.
    private var anchor: Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0,
                      of: Date(timeIntervalSince1970: 1_770_000_000))!
    }

    /// `count` dates ending at `end`, one every `days` days, newest first.
    private func series(endingAt end: Date, count: Int, everyDays days: Int) -> [Date] {
        (0..<count).map { calendar.date(byAdding: .day, value: -($0 * days), to: end)! }
    }

    /// The most recent date on or before `anchor` that falls on `weekday`
    /// (1 = Sunday … 7 = Saturday).
    private func lastDay(_ weekday: Int) -> Date {
        var date = anchor
        while calendar.component(.weekday, from: date) != weekday {
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return date
    }

    // MARK: - Not enough data

    @Test("Fewer than three episodes is not a pattern")
    func needsThreeSamples() {
        #expect(ReleaseScheduleGuesser.guess(pubDates: []).cadence == .irregular)
        #expect(ReleaseScheduleGuesser.guess(pubDates: [anchor]).cadence == .irregular)

        let two = series(endingAt: anchor, count: 2, everyDays: 7)
        let guessed = ReleaseScheduleGuesser.guess(pubDates: two)
        #expect(guessed.cadence == .irregular)
        #expect(guessed.predictedNext == nil)
    }

    // MARK: - Regular cadences

    @Test("A show publishing every day, weekends included, is daily")
    func detectsDaily() throws {
        // Seven consecutive days always covers a Saturday and a Sunday.
        let dates = series(endingAt: anchor, count: 7, everyDays: 1)
        let guessed = ReleaseScheduleGuesser.guess(pubDates: dates)

        #expect(guessed.cadence == .daily)
        let predicted = try #require(guessed.predictedNext)
        #expect(abs(predicted.timeIntervalSince(anchor) - 86_400) < 3_600)
    }

    @Test("A Monday-to-Friday show is weekdays, and its next date skips the weekend")
    func detectsWeekdays() throws {
        let friday = lastDay(6)
        let dates = series(endingAt: friday, count: 5, everyDays: 1)  // Mon…Fri
        let guessed = ReleaseScheduleGuesser.guess(pubDates: dates)

        #expect(guessed.cadence == .weekdays)
        let predicted = try #require(guessed.predictedNext)
        #expect(calendar.component(.weekday, from: predicted) == 2)  // Monday
    }

    @Test("A weekly show is weekly and is expected seven days after the last episode")
    func detectsWeekly() throws {
        let dates = series(endingAt: anchor, count: 6, everyDays: 7)
        let guessed = ReleaseScheduleGuesser.guess(pubDates: dates)

        #expect(guessed.cadence == .weekly)
        let predicted = try #require(guessed.predictedNext)
        #expect(abs(predicted.timeIntervalSince(anchor) - 7 * 86_400) < 3_600)
    }

    @Test("A fortnightly show is biweekly, expected fourteen days out")
    func detectsBiweekly() throws {
        let dates = series(endingAt: anchor, count: 5, everyDays: 14)
        let guessed = ReleaseScheduleGuesser.guess(pubDates: dates)

        #expect(guessed.cadence == .biweekly)
        let predicted = try #require(guessed.predictedNext)
        #expect(abs(predicted.timeIntervalSince(anchor) - 14 * 86_400) < 3_600)
    }

    @Test("Every prediction lands in the future, after the newest episode",
          arguments: [1, 7, 14])
    func predictionsAreForward(everyDays gap: Int) {
        let dates = series(endingAt: anchor, count: 6, everyDays: gap)
        if let predicted = ReleaseScheduleGuesser.guess(pubDates: dates).predictedNext {
            #expect(predicted > anchor)
        }
    }

    // MARK: - Irregular

    @Test("A jittery release pattern is called irregular instead of averaged into a lie")
    func detectsIrregular() {
        // Gaps of 1, 30, 1, 30, 1 days: the mean says fortnightly, the spread
        // says nothing of the sort.
        var dates = [anchor]
        for gap in [1, 30, 1, 30, 1] {
            dates.append(calendar.date(byAdding: .day, value: -gap, to: dates.last!)!)
        }

        let guessed = ReleaseScheduleGuesser.guess(pubDates: dates)
        #expect(guessed.cadence == .irregular)
        #expect(guessed.predictedNext == nil)
    }

    @Test("A monthly show falls outside the supported cadences and predicts nothing")
    func monthlyIsIrregular() {
        let dates = series(endingAt: anchor, count: 5, everyDays: 30)
        let guessed = ReleaseScheduleGuesser.guess(pubDates: dates)

        #expect(guessed.cadence == .irregular)
        #expect(guessed.predictedNext == nil)
    }

    @Test("Episodes sharing one timestamp still produce a forward-looking guess")
    func zeroGapsStillProject() throws {
        // A feed that stamps every item with the same pubDate gives gaps of
        // zero; the guess must still point forward rather than at the past.
        let guessed = ReleaseScheduleGuesser.guess(pubDates: Array(repeating: anchor, count: 5))
        let predicted = try #require(guessed.predictedNext)
        #expect(predicted > anchor)
    }

    // MARK: - Input handling

    @Test("Input order doesn't matter — the dates are sorted before analysis")
    func inputOrderIsIrrelevant() {
        let dates = series(endingAt: anchor, count: 6, everyDays: 7)
        let forward = ReleaseScheduleGuesser.guess(pubDates: dates)
        let shuffled = ReleaseScheduleGuesser.guess(pubDates: dates.reversed())

        #expect(forward.cadence == shuffled.cadence)
        #expect(forward.predictedNext == shuffled.predictedNext)
    }

    @Test("A long back catalogue is capped at the recent window, so an old cadence can't outvote the current one")
    func onlyRecentEpisodesCount() {
        // 20 recent weekly episodes, then a decade of yearly ones underneath.
        var dates = series(endingAt: anchor, count: 20, everyDays: 7)
        let oldest = dates.last!
        dates += (1...10).map { calendar.date(byAdding: .year, value: -$0, to: oldest)! }

        #expect(ReleaseScheduleGuesser.guess(pubDates: dates).cadence == .weekly)
    }
}
