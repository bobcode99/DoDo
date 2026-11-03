//
//  DiagnosticReport.swift
//  PodcastAnalyzer
//
//  One shareable text file for bug reports: what went wrong, the app, device
//  and settings it happened under, and the logs leading up to it.
//

import Foundation

enum DiagnosticReport {
  /// Builds the report into a temp file for the share sheet. Reads the log
  /// store, which is slow; call off the main actor.
  /// - Parameters:
  ///   - problem: What failed, e.g. the error the user saw. Included verbatim.
  ///   - libraryStats: Counts the caller read from SwiftData.
  nonisolated static func makeFile(problem: String?, libraryStats: [(String, Int)] = []) throws -> URL {
    let text = header(problem: problem, libraryStats: libraryStats)
      + "\n\n" + PersistentLogService.diagnosticLogText()
    let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
      .replacingOccurrences(of: ":", with: "")
    let url = URL.temporaryDirectory.appending(path: "DoDo-diagnostic-\(stamp).txt")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  /// Settings that change how transcription, downloads and playback behave.
  /// Never secrets: API keys are credentials and stay out.
  private nonisolated static let settingKeys = [
    "transcriptEngine", "whisper_selected_model", "selectedTranscriptLocale",
    "subtitle_split_long_audio", "subtitle_enable_music_detection",
    "subtitle_music_detection_sensitivity", "subtitle_auto_generate_transcripts",
    "subtitle_auto_download_transcripts", "subtitle_auto_translate", "subtitle_target_language",
    "selectedPodcastRegion", "defaultPlaybackSpeed", "autoPlayNextEpisode", "autoDownloadNewEpisodes",
  ]

  nonisolated static func header(problem: String?, libraryStats: [(String, Int)]) -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let defaults = UserDefaults.standard
    var lines = ["=== DoDo diagnostic report ==="]
    if let problem { lines.append("Problem: \(problem)") }
    lines += [
      "Date: \(Date.now.formatted(.iso8601))",
      "App: \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
      "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "Device: \(deviceModel)",
      "Free storage: \(freeStorage)",
      "Languages: \(Locale.preferredLanguages.prefix(3).joined(separator: ", "))",
    ]
    lines += libraryStats.map { "\($0.0): \($0.1)" }
    lines.append("Settings:")
    for key in settingKeys {
      lines.append("  \(key): \(defaults.object(forKey: key).map { "\($0)" } ?? "default")")
    }
    // The URL can be a private host, so only whether one is set.
    let yapConfigured = !(defaults.string(forKey: "yap_server_url") ?? "").isEmpty
    lines.append("  yap_server: \(yapConfigured ? "configured" : "not configured")")
    return lines.joined(separator: "\n")
  }

  /// Hardware identifier, e.g. "iPhone17,3".
  private nonisolated static var deviceModel: String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafeBytes(of: &systemInfo.machine) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }

  private nonisolated static var freeStorage: String {
    let values = try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return "unknown" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}
