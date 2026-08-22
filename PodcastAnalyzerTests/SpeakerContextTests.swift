//
//  SpeakerContextTests.swift
//  PodcastAnalyzerTests
//
//  The speaker block goes into every analysis prompt, so its failure modes are
//  quiet ones: a wrong cast list produces confident, wrong attribution in a
//  summary that still reads fine.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@Suite("Speaker context")
struct SpeakerContextTests {

    // MARK: - The empty case

    @Test("No sources produces no block at all")
    func emptyProducesNothing() {
        let context = SpeakerContext.build()
        #expect(context.isEmpty)
        #expect(context.promptBlock.isEmpty, "a 'Speakers: 0' header would be a claim, and a false one")
    }

    @Test("Blank and whitespace names don't count as speakers")
    func blankNamesIgnored() {
        let context = SpeakerContext.build(roster: ["", "   "], author: "  ")
        #expect(context.isEmpty)
        #expect(context.promptBlock.isEmpty)
    }

    // MARK: - The anti-fabrication instruction

    @Test("An unlabelled transcript is stated as unlabelled")
    func unlabelledWarning() {
        let block = SpeakerContext.build(
            roster: ["Bob Chen"], transcriptIsLabelled: false
        ).promptBlock

        #expect(block.contains("NO per-line speaker labels"))
        #expect(block.contains("unless the text itself makes the attribution explicit"))
    }

    @Test("A labelled transcript says so instead")
    func labelledWording() {
        let block = SpeakerContext.build(
            roster: ["Bob Chen"],
            transcriptNames: ["Bob Chen", "Jane Doe"],
            transcriptIsLabelled: true
        ).promptBlock

        #expect(block.contains("labels each line"))
        #expect(!block.contains("NO per-line speaker labels"))
    }

    // MARK: - Merging sources

    @Test("podcast:person roles map to hosts and guests")
    func rolesMapped() {
        let context = SpeakerContext.build(feedPeople: [
            PodcastPerson(name: "Bob Chen", role: "host", group: nil),
            PodcastPerson(name: "Dr. Jane Doe", role: "guest", group: nil),
        ])
        #expect(context.hosts == ["Bob Chen"])
        #expect(context.guests == ["Dr. Jane Doe"])
        #expect(context.allNames.count == 2)
    }

    @Test("A person with no role is a host, per the spec")
    func unroledIsHost() {
        let context = SpeakerContext.build(feedPeople: [
            PodcastPerson(name: "Bob Chen", role: nil, group: nil)
        ])
        #expect(context.hosts == ["Bob Chen"])
    }

    @Test("Non-speaking credits are not listed as speakers")
    func nonSpeakingRolesDropped() {
        let context = SpeakerContext.build(feedPeople: [
            PodcastPerson(name: "Bob Chen", role: "host", group: nil),
            PodcastPerson(name: "Sam Producer", role: "producer", group: nil),
            PodcastPerson(name: "Ed Editor", role: "editor", group: nil),
        ])
        #expect(context.allNames == ["Bob Chen"], "a producer is credited, not heard")
    }

    @Test("The same person from two sources is listed once")
    func dedupesAcrossSources() {
        let context = SpeakerContext.build(
            roster: ["Bob Chen"],
            feedPeople: [PodcastPerson(name: "bob chen", role: "host", group: nil)],
            transcriptNames: ["BOB CHEN"]
        )
        #expect(context.allNames.count == 1)
    }

    @Test("Someone can't be both host and guest")
    func hostWinsOverGuest() {
        let context = SpeakerContext.build(
            roster: ["Bob Chen"],
            feedPeople: [PodcastPerson(name: "Bob Chen", role: "guest", group: nil)]
        )
        #expect(context.hosts == ["Bob Chen"])
        #expect(context.guests.isEmpty)
    }

    // MARK: - itunes:author fallback

    @Test("Author fills in only when nothing else names a host")
    func authorIsLastResort() {
        let withPerson = SpeakerContext.build(
            feedPeople: [PodcastPerson(name: "Bob Chen", role: "host", group: nil)],
            author: "Some Media Network"
        )
        #expect(withPerson.hosts == ["Bob Chen"], "a real credit beats the feed's author field")

        let withoutPerson = SpeakerContext.build(author: "Some Media Network")
        #expect(withoutPerson.hosts == ["Some Media Network"])
    }

    // MARK: - Block shape

    @Test("The block counts speakers and labels their roles")
    func blockShape() {
        let block = SpeakerContext.build(
            roster: ["Bob Chen"],
            feedPeople: [PodcastPerson(name: "Dr. Jane Doe", role: "guest", group: nil)]
        ).promptBlock

        #expect(block.contains("Speakers (2):"))
        #expect(block.contains("- Host: Bob Chen"))
        #expect(block.contains("- Guest: Dr. Jane Doe"))
        // The schema already asks the model to extract "people"; without this it
        // would dutifully echo the list back as its own finding.
        #expect(block.contains("\"people\""))
    }
}

@MainActor
@Suite("VTT speaker labels")
struct VTTSpeakerTests {

    private let vtt = """
    WEBVTT

    00:00:01.000 --> 00:00:04.000
    <v Bob Chen>Welcome to the show.

    00:00:04.000 --> 00:00:08.000
    <v Dr. Jane Doe>Thanks for having me.

    00:00:08.000 --> 00:00:10.000
    <v Bob Chen>Let's begin.
    """

    @Test("Speaker names are recovered from voice tags")
    func namesRecovered() {
        #expect(VTTParser.speakerNames(in: vtt) == ["Bob Chen", "Dr. Jane Doe"])
    }

    @Test("A transcript without voice tags yields no names")
    func noTags() {
        let plain = "WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nJust text.\n"
        #expect(VTTParser.speakerNames(in: plain).isEmpty)
    }

    @Test("The visible transcript text still has its tags stripped")
    func textStillClean() {
        let segments = VTTParser.parseSegments(from: vtt)
        let text = segments.map(\.text).joined(separator: " ")
        #expect(!text.contains("<v"), "the name is kept as metadata, not left in the prose")
        #expect(text.contains("Welcome to the show."))
    }
}

@MainActor
@Suite("Podcast people survive SwiftData")
struct PodcastPeoplePersistenceTests {

    /// `PodcastInfo` is persisted as a SwiftData blob, and SwiftData's decoder
    /// **traps** on `decodeIfPresent` of a custom type — it tolerates only the
    /// primitives the struct already used. Holding the cast as an encoded String
    /// is what keeps the blob readable; storing `[PodcastPerson]` directly
    /// crashed the app on the first read, taking the whole test bundle with it.
    @Test("A show with credited people round-trips through the store")
    func peopleRoundTrip() throws {
        let container = try ModelContainer(
            for: PodcastInfoModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let info = PodcastInfo(
            title: "The Swift Podcast",
            description: nil,
            episodes: [],
            rssUrl: "https://example.com/feed.xml",
            imageURL: "",
            language: "en",
            author: "Some Media Network",
            people: [PodcastPerson(name: "Bob Chen", role: "host", group: nil)],
            episodePeople: ["ep-1": [PodcastPerson(name: "Dr. Jane Doe", role: "guest", group: nil)]]
        )
        context.insert(PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: true))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<PodcastInfoModel>()).first)
        // Reading the blob back is the operation that used to trap.
        #expect(stored.podcastInfo.people.map(\.name) == ["Bob Chen"])
        #expect(stored.podcastInfo.episodePeople["ep-1"]?.first?.name == "Dr. Jane Doe")
        #expect(stored.feedAuthor == "Some Media Network")
        #expect(stored.feedHostNames == ["Bob Chen"])
        #expect(stored.episodeGuestNames["ep-1"] == ["Dr. Jane Doe"])
    }

    @Test("A show with no credits stores nothing and still reads back")
    func noPeopleRoundTrip() throws {
        let container = try ModelContainer(
            for: PodcastInfoModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let info = PodcastInfo(
            title: "Solo Show", description: nil, episodes: [],
            rssUrl: "https://example.com/solo.xml", imageURL: "", language: "en"
        )
        context.insert(PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: true))
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<PodcastInfoModel>()).first)
        #expect(stored.podcastInfo.people.isEmpty)
        #expect(stored.podcastInfo.peopleJSON == nil, "absent, not an empty envelope")
        #expect(stored.feedHostNames.isEmpty)
    }
}
