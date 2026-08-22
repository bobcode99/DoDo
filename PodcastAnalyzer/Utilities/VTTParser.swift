//
//  VTTParser.swift
//  PodcastAnalyzer
//
//  Utility for parsing WebVTT (VTT) transcript files
//  Reference: https://www.w3.org/TR/webvtt1/
//

import Foundation

/// Utility for parsing WebVTT subtitle files and converting to SRT format
struct VTTParser: Sendable {

  // MARK: - Parse to Segments

  /// Parse VTT content into structured segments with timestamps
  /// - Parameter vttContent: Raw VTT file content
  /// - Returns: Array of transcript segments with timing information
  nonisolated static func parseSegments(from vttContent: String) -> [TranscriptSegment] {
    var segments: [TranscriptSegment] = []
    var segmentIndex = 1

    // Normalize line endings and split into blocks
    let normalized = vttContent.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")

    // Split by double newlines to get cue blocks
    let blocks = normalized.components(separatedBy: "\n\n")

    for block in blocks {
      let lines = block.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      guard !lines.isEmpty else { continue }

      // Skip WEBVTT header
      if lines[0].hasPrefix("WEBVTT") {
        continue
      }

      // Skip NOTE comments
      if lines[0].hasPrefix("NOTE") {
        continue
      }

      // Skip STYLE blocks
      if lines[0].hasPrefix("STYLE") {
        continue
      }

      // Skip REGION blocks
      if lines[0].hasPrefix("REGION") {
        continue
      }

      // Find the timestamp line
      var timestampLineIndex: Int?
      for (index, line) in lines.enumerated() {
        if line.contains("-->") {
          timestampLineIndex = index
          break
        }
      }

      guard let tsIndex = timestampLineIndex else { continue }

      // Parse timestamp line
      let timestampLine = lines[tsIndex]
      let timestampParts = timestampLine.components(separatedBy: "-->")
      guard timestampParts.count == 2 else { continue }

      // Extract timestamps (may have position/alignment settings after)
      let startTimeStr = timestampParts[0].trimmingCharacters(in: .whitespaces)
      let endPartStr = timestampParts[1].trimmingCharacters(in: .whitespaces)

      // End time may have settings after it (e.g., "00:00:05.000 position:50%")
      let endTimeStr =
        endPartStr.components(separatedBy: .whitespaces).first
        ?? endPartStr

      guard let startTime = parseTimestamp(startTimeStr),
        let endTime = parseTimestamp(endTimeStr)
      else { continue }

      // Collect text lines (everything after timestamp line)
      let textLines = Array(lines[(tsIndex + 1)...])
      let strippedLines = textLines.map { stripVTTTags($0) }
      let text = CJKTextUtils.joinTexts(strippedLines)
        .trimmingCharacters(in: .whitespaces)

      guard !text.isEmpty else { continue }

      segments.append(
        TranscriptSegment(
          id: segmentIndex,
          startTime: startTime,
          endTime: endTime,
          text: text
        ))
      segmentIndex += 1
    }

    return segments
  }

  // MARK: - Convert to SRT

  /// Convert VTT content to SRT format for standardized storage
  /// - Parameter vttContent: Raw VTT file content
  /// - Returns: SRT formatted content
  nonisolated static func convertToSRT(_ vttContent: String) -> String {
    let segments = parseSegments(from: vttContent)

    var srtContent = ""
    for segment in segments {
      srtContent += "\(segment.id)\n"
      srtContent += "\(formatSRTTime(segment.startTime)) --> \(formatSRTTime(segment.endTime))\n"
      srtContent += "\(segment.text)\n"
      srtContent += "\n"
    }

    return srtContent
  }

  // MARK: - Extract Plain Text

  /// Extract plain text from VTT content (no timestamps)
  /// - Parameter vttContent: Raw VTT file content
  /// - Returns: Plain text transcript
  nonisolated static func extractPlainText(from vttContent: String) -> String {
    let segments = parseSegments(from: vttContent)
    return CJKTextUtils.joinTexts(segments.map { $0.text })
  }

  // MARK: - Private Helpers

  /// Parse VTT timestamp to TimeInterval
  /// Formats: HH:MM:SS.mmm, MM:SS.mmm, or with comma separator
  /// - Parameter timestamp: Timestamp string
  /// - Returns: TimeInterval in seconds, or nil if parsing fails
  private nonisolated static func parseTimestamp(_ timestamp: String) -> TimeInterval? {
    // Replace comma with period for consistency
    let cleaned = timestamp.replacingOccurrences(of: ",", with: ".")
      .trimmingCharacters(in: .whitespaces)

    let components = cleaned.components(separatedBy: ":")

    switch components.count {
    case 2:
      // MM:SS.mmm format
      guard let minutes = Double(components[0]),
        let seconds = Double(components[1])
      else { return nil }
      return minutes * 60 + seconds

    case 3:
      // HH:MM:SS.mmm format
      guard let hours = Double(components[0]),
        let minutes = Double(components[1]),
        let seconds = Double(components[2])
      else { return nil }
      return hours * 3600 + minutes * 60 + seconds

    default:
      return nil
    }
  }

  /// Format TimeInterval to SRT timestamp format (HH:MM:SS,mmm)
  private nonisolated static func formatSRTTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60
    let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
  }

  /// Speaker names carried by `<v Name>` voice tags, in first-appearance order.
  ///
  /// These used to be stripped and thrown away with the rest of the markup, which
  /// discarded the only per-line speaker attribution a transcript can carry. The
  /// tag is still removed from the visible text — only the name is kept.
  public nonisolated static func speakerNames(in vtt: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "<v\\s+([^>]+)>") else { return [] }
    let range = NSRange(vtt.startIndex..., in: vtt)
    var seen = Set<String>()
    var names: [String] = []
    for match in regex.matches(in: vtt, range: range) {
      guard match.numberOfRanges > 1,
            let nameRange = Range(match.range(at: 1), in: vtt) else { continue }
      // A cue can be `<v Bob Chen>` or `<v.loud Bob Chen>`; the class suffix
      // lives on the tag name, so what's captured here is already just the name.
      let name = String(vtt[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
      names.append(name)
    }
    return names
  }

  /// Strip VTT formatting tags from text
  /// Handles: <v Speaker>, <c.class>, <b>, <i>, <u>, etc.
  private nonisolated static func stripVTTTags(_ text: String) -> String {
    // Remove voice tags: <v Speaker Name>
    var result = text.replacingOccurrences(
      of: "<v[^>]*>",
      with: "",
      options: .regularExpression
    )

    // Remove all other HTML-like tags
    result = result.replacingOccurrences(
      of: "<[^>]+>",
      with: "",
      options: .regularExpression
    )

    // Remove timestamp tags (e.g., <00:00:00.000>)
    result = result.replacingOccurrences(
      of: "<\\d+:\\d+[:\\.]\\d+[.\\d]*>",
      with: "",
      options: .regularExpression
    )

    // Decode HTML entities
    result = decodeHTMLEntities(result)

    return result.trimmingCharacters(in: .whitespaces)
  }

  /// Decode common HTML entities in text
  private nonisolated static func decodeHTMLEntities(_ text: String) -> String {
    var result = text

    // Common HTML entities
    let entities: [(String, String)] = [
      ("&nbsp;", " "),
      ("&amp;", "&"),
      ("&lt;", "<"),
      ("&gt;", ">"),
      ("&quot;", "\""),
      ("&apos;", "'"),
      ("&#39;", "'"),
      ("&rsquo;", "'"),
      ("&lsquo;", "'"),
      ("&rdquo;", "\""),
      ("&ldquo;", "\""),
      ("&ndash;", "–"),
      ("&mdash;", "—"),
      ("&hellip;", "…"),
      ("&#160;", " "),  // Numeric form of &nbsp;
    ]

    for (entity, replacement) in entities {
      result = result.replacingOccurrences(of: entity, with: replacement)
    }

    // Handle numeric HTML entities (&#NNN;)
    if let regex = try? NSRegularExpression(pattern: "&#(\\d+);", options: []) {
      let nsString = result as NSString
      let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

      // Process matches in reverse to avoid index shifting
      for match in matches.reversed() {
        if match.numberOfRanges >= 2 {
          let codeRange = match.range(at: 1)
          if let code = Int(nsString.substring(with: codeRange)),
             let scalar = Unicode.Scalar(code) {
            let replacement = String(Character(scalar))
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
          }
        }
      }
    }

    return result
  }
}

// MARK: - VTT Detection

extension VTTParser {
  /// Check if content appears to be VTT format
  nonisolated static func isVTTContent(_ content: String) -> Bool {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("WEBVTT")
  }

  /// Check if MIME type indicates VTT format
  nonisolated static func isVTTType(_ mimeType: String) -> Bool {
    let type = mimeType.lowercased()
    return type.contains("vtt") || type == "text/vtt"
  }
}
