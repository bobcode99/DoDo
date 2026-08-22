//
//  PodcastNamespaceParser.swift
//  PodcastAnalyzer
//
//  Parses Podcasting 2.0 namespace elements from RSS feeds
//  Reference: https://github.com/Podcastindex-org/podcast-namespace
//

import Foundation
import OSLog

/// Information about a podcast transcript from RSS
public nonisolated struct TranscriptInfo: Sendable, Equatable {
  /// URL to the transcript file
  public let url: String

  /// MIME type of the transcript (e.g., "text/vtt", "application/srt", "text/plain")
  public let type: String

  /// Language of the transcript (optional)
  public let language: String?

  /// Relationship type (e.g., "captions" for closed captions)
  public let rel: String?
}

/// A person credited on a show or an episode.
///
/// `<podcast:person>` carries the name as element text plus a `role`
/// ("host", "guest", "producer"…) and an optional `group`. It is the only
/// structured speaker information a podcast feed can publish, so where a show
/// provides it we get an exact cast list for free.
public nonisolated struct PodcastPerson: Sendable, Equatable, Hashable, Codable {
  public let name: String
  /// Lowercased role as published; nil when the feed omits it, which the spec
  /// says means "host".
  public let role: String?
  public let group: String?

  public init(name: String, role: String?, group: String?) {
    self.name = name
    self.role = role
    self.group = group
  }

  /// The spec's default: an unroled person is a host.
  public var isHost: Bool {
    guard let role else { return true }
    return role == "host"
  }
}

/// Everything the Podcasting 2.0 pass extracts in one traversal.
public nonisolated struct PodcastNamespaceData: Sendable {
  /// Episode GUID → transcript.
  public let transcripts: [String: TranscriptInfo]
  /// Channel-level people — the show's regular cast.
  public let showPeople: [PodcastPerson]
  /// Episode GUID → people credited on that episode, typically guests.
  public let episodePeople: [String: [PodcastPerson]]
}

/// Parser for Podcasting 2.0 namespace elements
/// Extracts podcast:transcript and podcast:person tags from RSS feeds
public nonisolated struct PodcastNamespaceParser: Sendable {

  public init() {}

  /// Parse transcripts and people in a single pass.

  public func parse(from data: Data) -> PodcastNamespaceData {
    TranscriptXMLParser(data: data).parseAll()
  }

  /// Parse RSS data to extract transcript information for each episode
  /// - Parameter data: Raw RSS XML data
  /// - Returns: Dictionary mapping episode GUIDs to their transcript info

  public func parseTranscripts(from data: Data) -> [String: TranscriptInfo] {
    let parser = TranscriptXMLParser(data: data)
    return parser.parse()
  }
}

// MARK: - XML Parser Implementation

/// Internal XML parser delegate for extracting transcript tags
/// XMLParser calls delegate methods synchronously on the calling thread.

private nonisolated final class TranscriptXMLParser: NSObject, XMLParserDelegate {

  private let data: Data
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastNamespaceParser")

  // Current parsing state
  private var currentGuid = ""
  private var currentItemGuid = ""
  private var insideItem = false

  // Results
  private var transcripts: [String: TranscriptInfo] = [:]
  private var showPeople: [PodcastPerson] = []
  private var episodePeople: [String: [PodcastPerson]] = [:]

  // Temporary storage for current item's transcript
  private var currentItemTranscript: TranscriptInfo?

  // podcast:person carries its name as element text, so the attributes are held
  // while the characters accumulate and are combined on the closing tag.
  private var currentItemPeople: [PodcastPerson] = []
  private var personRole: String?
  private var personGroup: String?
  private var personName = ""
  private var capturingPerson = false

  init(data: Data) {
    self.data = data
    super.init()
  }

  func parseAll() -> PodcastNamespaceData {
    _ = runParse()
    return PodcastNamespaceData(
      transcripts: transcripts,
      showPeople: showPeople,
      episodePeople: episodePeople
    )
  }

  func parse() -> [String: TranscriptInfo] {
    runParse()
  }

  private func runParse() -> [String: TranscriptInfo] {
    let parser = XMLParser(data: data)
    parser.delegate = self
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true

    if parser.parse() {
      return transcripts
    } else {
      logger.error("XML parsing failed: \(parser.parserError?.localizedDescription ?? "unknown")")
      return [:]
    }
  }

  // MARK: - XMLParserDelegate

  func parser(
    _ parser: XMLParser,
    didStartElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?,
    attributes attributeDict: [String: String] = [:]
  ) {
    // Handle item start
    if elementName == "item" {
      insideItem = true
      currentItemGuid = ""
      currentItemTranscript = nil
      currentItemPeople = []
    }

    let isPersonElement =
      elementName == "person"
      || elementName == "podcast:person"
      || (namespaceURI?.contains("podcastindex.org") == true && elementName == "person")

    if isPersonElement {
      capturingPerson = true
      personName = ""
      personRole = attributeDict["role"]?.lowercased()
      personGroup = attributeDict["group"]?.lowercased()
    }

    // Handle guid inside item
    if elementName == "guid" && insideItem {
      currentGuid = ""
    }

    // Handle podcast:transcript element
    // The element might come as "transcript" with namespace or "podcast:transcript"
    let isTranscriptElement =
      elementName == "transcript"
      || elementName == "podcast:transcript"
      || (namespaceURI?.contains("podcastindex.org") == true && elementName == "transcript")

    if isTranscriptElement && insideItem {
      // Extract attributes
      // VTT example: <podcast:transcript type="text/vtt" url="https://..." language="en"/>
      if let url = attributeDict["url"], let type = attributeDict["type"] {
        // Prefer VTT or SRT transcripts
        let typeLC = type.lowercased()
        let isPreferredType =
          typeLC.contains("vtt")
          || typeLC.contains("srt")
          || typeLC == "text/vtt"
          || typeLC == "application/srt"

        // Only store if we don't have one yet, or if this is a preferred type
        if currentItemTranscript == nil || isPreferredType {
          currentItemTranscript = TranscriptInfo(
            url: url,
            type: type,
            language: attributeDict["language"],
            rel: attributeDict["rel"]
          )
          logger.debug("Found transcript: type=\(type), url=\(url)")
        }
      }
    }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    // A person's name is element text, and people appear at both channel and
    // item level — so this is captured regardless of `insideItem`.
    if capturingPerson {
      personName += string
      return
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty && insideItem {
      currentGuid += trimmed
    }
  }

  func parser(
    _ parser: XMLParser,
    didEndElement elementName: String,
    namespaceURI: String?,
    qualifiedName qName: String?
  ) {
    // Store guid when closing guid element
    if elementName == "guid" && insideItem {
      currentItemGuid = currentGuid.trimmingCharacters(in: .whitespacesAndNewlines)
      currentGuid = ""
    }

    if capturingPerson,
       elementName == "person" || elementName == "podcast:person" {
      let name = personName.trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty {
        let person = PodcastPerson(name: name, role: personRole, group: personGroup)
        if insideItem {
          currentItemPeople.append(person)
        } else {
          showPeople.append(person)
        }
      }
      capturingPerson = false
      personName = ""
      personRole = nil
      personGroup = nil
    }

    // Store transcript when closing item
    if elementName == "item" {
      if let transcript = currentItemTranscript, !currentItemGuid.isEmpty {
        transcripts[currentItemGuid] = transcript
        logger.debug("Stored transcript for guid: \(self.currentItemGuid)")
      }
      if !currentItemPeople.isEmpty, !currentItemGuid.isEmpty {
        episodePeople[currentItemGuid] = currentItemPeople
      }
      insideItem = false
      currentItemGuid = ""
      currentItemTranscript = nil
      currentItemPeople = []
    }
  }

  func parserDidEndDocument(_ parser: XMLParser) {
    logger.info("Parsed \(self.transcripts.count) transcripts from RSS feed")
  }
}

// MARK: - Convenience Extensions

extension TranscriptInfo {
  /// Check if this is a VTT transcript
  var isVTT: Bool {
    let typeLC = type.lowercased()
    return typeLC.contains("vtt") || typeLC == "text/vtt"
  }

  /// Check if this is an SRT transcript
  var isSRT: Bool {
    let typeLC = type.lowercased()
    return typeLC.contains("srt") || typeLC == "application/srt"
  }

  /// Check if this is a plain text transcript
  var isPlainText: Bool {
    let typeLC = type.lowercased()
    return typeLC == "text/plain"
  }

  /// Get the URL as a URL object
  var urlObject: URL? {
    URL(string: url)
  }
}
