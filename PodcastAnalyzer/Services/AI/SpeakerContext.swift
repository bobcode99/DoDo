//
//  SpeakerContext.swift
//  PodcastAnalyzer
//
//  Who is talking, assembled for the analysis prompt.
//
//  Without this the model is handed a wall of unattributed prose and asked to
//  summarize a conversation — so it guesses, and an interview comes back with the
//  host's scepticism reported as the guest's argument.
//
//  The single most important thing this type emits is not the cast list: it is the
//  sentence stating whether the transcript carries per-line speaker labels.
//  Analysis flattens the transcript to sentences before sending it, so the model
//  almost always receives names *without* attribution. Supplying a cast list and
//  saying nothing invites confident misattribution, which is worse than saying
//  nothing at all.
//

import Foundation

nonisolated struct SpeakerContext: Equatable {
  /// Hosts, from the show roster or `podcast:person` role="host".
  var hosts: [String] = []
  /// Guests, usually from an episode's own `podcast:person` entries.
  var guests: [String] = []
  /// Names carried by the transcript itself (VTT `<v Name>`), which is the only
  /// source that proves who actually speaks rather than who was credited.
  var labelled: [String] = []
  /// Whether the transcript text the model receives keeps those labels.
  var transcriptIsLabelled: Bool = false

  var isEmpty: Bool {
    hosts.isEmpty && guests.isEmpty && labelled.isEmpty
  }

  /// Distinct speakers across every source, in host → guest → labelled order.
  var allNames: [String] {
    var seen = Set<String>()
    return (hosts + guests + labelled).filter {
      seen.insert($0.lowercased()).inserted
    }
  }

  /// The prompt fragment, or an empty string when nothing is known.
  ///
  /// Emitting nothing is deliberate: a header reading "Speakers: 0" would be a
  /// claim, and a false one — not knowing the cast is not the same as there being
  /// no cast.
  var promptBlock: String {
    guard !isEmpty else { return "" }

    var lines = ["\n\nSpeakers (\(allNames.count)):"]
    for host in hosts { lines.append("- Host: \(host)") }
    for guest in guests { lines.append("- Guest: \(guest)") }
    for name in labelled where !hosts.contains(name) && !guests.contains(name) {
      lines.append("- Speaker: \(name)")
    }

    if transcriptIsLabelled {
      lines.append("The transcript labels each line with its speaker. Attribute quotes and claims accordingly.")
    } else {
      lines.append(
        "The transcript has NO per-line speaker labels. Use these names to understand "
        + "who takes part, but do not attribute a quote or claim to a named speaker "
        + "unless the text itself makes the attribution explicit.")
    }
    lines.append("Reconcile this list with the \"people\" field rather than repeating it.")

    return lines.joined(separator: "\n")
  }

  /// Merge every source, newest-wins per slot, de-duplicated case-insensitively.
  ///
  /// - Parameters:
  ///   - roster: user-maintained show hosts — authoritative, so it leads.
  ///   - feedPeople: `podcast:person` for the show and the episode.
  ///   - author: `itunes:author`, a weak host hint used only when nothing else
  ///     names one. Often a company rather than a person, hence last.
  ///   - transcriptNames: VTT `<v>` names.
  static func build(
    roster: [String] = [],
    feedPeople: [PodcastPerson] = [],
    author: String? = nil,
    transcriptNames: [String] = [],
    transcriptIsLabelled: Bool = false
  ) -> SpeakerContext {
    var hosts = roster.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var guests: [String] = []

    for person in feedPeople {
      let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      if person.isHost {
        hosts.append(name)
      } else if person.role == "guest" {
        guests.append(name)
      }
      // Producers, editors and engineers are credited but don't speak, so they
      // are deliberately dropped rather than listed as speakers.
    }

    if hosts.isEmpty, let author = author?.trimmingCharacters(in: .whitespacesAndNewlines),
       !author.isEmpty {
      hosts.append(author)
    }

    hosts = dedupe(hosts)
    guests = dedupe(guests).filter { guest in
      !hosts.contains { $0.caseInsensitiveCompare(guest) == .orderedSame }
    }

    return SpeakerContext(
      hosts: hosts,
      guests: guests,
      labelled: dedupe(transcriptNames),
      transcriptIsLabelled: transcriptIsLabelled
    )
  }

  private static func dedupe(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names.filter { seen.insert($0.lowercased()).inserted }
  }
}
