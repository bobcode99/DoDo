//
//  DownloadPayloadValidator.swift
//  PodcastAnalyzer
//
//  Sanity check on a finished download before it is filed as audio.
//
//  A feed whose enclosure URL has rotted often answers 200 with an HTML error
//  page, or a few hundred bytes of nothing. URLSession reports that as a
//  successful download, so without this check the episode is stored as
//  `.downloaded` and only reveals itself as broken when the user hits play —
//  far from the action that caused it. Failing here instead surfaces a Retry
//  row in the context menus immediately.
//

import Foundation

nonisolated enum DownloadPayloadValidator {
  /// Anything this small cannot be an episode, whatever it claims to be.
  static let minimumBytes: Int64 = 16_384

  /// Below this we additionally distrust a textual content type. Some very
  /// short trailers are legitimately under a megabyte, so size alone is not
  /// enough to reject them — but a *text* payload at that size never is.
  static let suspiciousBytes: Int64 = 1_048_576

  /// Human-readable reason to fail the download, or `nil` when the payload
  /// looks like real audio.
  static func rejectionReason(fileSize: Int64, contentType: String?) -> String? {
    if fileSize < minimumBytes {
      return "The download was empty or truncated (\(fileSize) bytes). The episode may no longer be available."
    }

    if fileSize < suspiciousBytes, isTextual(contentType) {
      return "The server returned a web page instead of audio. The episode may have moved or been removed."
    }

    return nil
  }

  private static func isTextual(_ contentType: String?) -> Bool {
    guard let contentType else { return false }
    // Content-Type carries parameters ("text/html; charset=utf-8"), so match
    // the type prefix rather than the whole header value.
    let type = contentType.lowercased()
    return type.hasPrefix("text/") || type.hasPrefix("application/xhtml")
  }
}
