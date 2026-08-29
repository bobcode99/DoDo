//
//  RSSParser.swift
//  PodcastAnalyzer
//
//  XMLParserDelegate that turns a podcast RSS feed into [Episode].
//

import Foundation

class RSSParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var episodes: [Episode] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentEnclosureUrl = ""
    private var currentGuid = ""
    private var language = ""  // From channel <language>

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [Episode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return episodes
        } else if let error = parser.parserError {
            throw error
        } else {
            throw URLError(.cannotParseResponse)
        }
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentDuration = ""
            currentEnclosureUrl = ""
            currentGuid = ""
        } else if elementName == "enclosure" {
            currentEnclosureUrl = attributeDict["url"] ?? ""
        } else if elementName == "itunes:duration" {
            currentDuration = ""
        } else if elementName == "language" {
            language = ""
        } else if elementName == "guid" {
            currentGuid = ""
        } else if elementName == "description" {
            currentDescription = ""
        }  // Add more for other fields if needed
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        switch currentElement {
        case "title": currentTitle += trimmed
        case "description": currentDescription += trimmed
        case "pubDate": currentPubDate += trimmed
        case "itunes:duration": currentDuration += trimmed
        case "guid": currentGuid += trimmed
        case "language": language += trimmed
        default: break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            // Parse duration to millis (like string parsing in Java)
            var millis: Int? = nil
            if !currentDuration.isEmpty {
                if let sec = Int(currentDuration) {
                    millis = sec * 1000
                } else {
                    let parts = currentDuration.split(separator: ":")
                    if parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]),
                        let s = Int(parts[2])
                    {
                        millis = (h * 3600 + m * 60 + s) * 1000
                    } else if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
                        millis = (m * 60 + s) * 1000
                    }
                }
            }

            let episode = Episode(
                wrapperType: "podcastEpisode",
                kind: "podcast-episode",
                trackId: nil,  // No Apple ID
                trackName: currentTitle,
                description: currentDescription,
                shortDescription: nil,
                releaseDate: currentPubDate,
                trackTimeMillis: millis,
                contentAdvisoryRating: nil,
                trackViewUrl: nil,  // No Apple link available from RSS
                previewUrl: nil,
                episodeUrl: currentEnclosureUrl,
                artworkUrl600: nil,
                artworkUrl160: nil,
                country: nil,
                language: language,  // From RSS
                genres: nil,
                collectionId: nil,
                collectionName: nil,
                episodeGuid: currentGuid,
                closedCaptioning: nil,
                episodeContentType: nil,
                episodeFileExtension: nil
            )
            episodes.append(episode)
        }
    }
}
