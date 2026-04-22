//
//  TranscriptService.swift
//  PodcastAnalyzer
//
//  Core actor: initialization, model installation, lifecycle.
//  Transcription methods are in TranscriptService+Audio.swift,
//  TranscriptService+Progress.swift, and TranscriptService+Chunked.swift.
//

import AVFoundation
import Foundation
import Speech
import OSLog

@available(iOS 26.0, *)
public actor TranscriptService {

  // MARK: - Properties

  nonisolated let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptService")

  var censor: Bool
  var needsAudioTimeRange: Bool
  var targetLocale: Locale

  var transcriber: SpeechTranscriber?
  var analyzer: SpeechAnalyzer?
  var assetSetupError: Error?

  // MARK: - Locale helpers

  /// Whether the target locale is CJK (Chinese, Japanese, Korean).
  var isCJKLocale: Bool {
    let lang = targetLocale.language.languageCode?.identifier ?? ""
    return ["zh", "ja", "ko"].contains(lang)
  }

  /// Max characters per subtitle segment.
  /// CJK: 14 chars, Latin: 40 chars.
  var defaultMaxLength: Int {
    isCJKLocale ? 14 : 40
  }

  // MARK: - Init

  /// Creates a TranscriptService for the given podcast language code (e.g. "zh-tw", "en-us").
  public init(language: String, censor: Bool = false, needsAudioTimeRange: Bool = true) {
    self.censor = censor
    self.needsAudioTimeRange = needsAudioTimeRange
    self.targetLocale = TranscriptLocaleResolver.locale(fromPodcastLanguage: language)
  }

  /// Convenience passthrough kept for callers that already resolved the locale.
  public static func locale(fromPodcastLanguage languageCode: String) -> Locale {
    TranscriptLocaleResolver.locale(fromPodcastLanguage: languageCode)
  }

  // MARK: - Asset setup

  /// Starts asset installation and streams progress (0.0 – 1.0).
  public func setupAndInstallAssets() -> AsyncStream<Double> {
    let (stream, continuation) = AsyncStream.makeStream(of: Double.self)
    let setupTask = Task { await self.setupAndInstallAssetsInternal(continuation: continuation) }
    continuation.onTermination = { _ in setupTask.cancel() }
    return stream
  }

  private func setupAndInstallAssetsInternal(continuation: AsyncStream<Double>.Continuation) async {
    var attributeOptions: Set<SpeechTranscriber.ResultAttributeOption> = [.transcriptionConfidence]
    if needsAudioTimeRange { attributeOptions.insert(.audioTimeRange) }

    let newTranscriber = SpeechTranscriber(
      locale: targetLocale,
      transcriptionOptions: censor ? [.etiquetteReplacements] : [],
      reportingOptions: [],
      attributeOptions: attributeOptions
    )
    self.transcriber = newTranscriber

    do {
      try await releaseAndReserveLocales()
    } catch {
      logger.error("Failed to reserve locale: \(error.localizedDescription)")
      self.assetSetupError = error
    }

    let modules: [any SpeechModule] = [newTranscriber]
    let installed = await Set(SpeechTranscriber.installedLocales)
    logger.info("Installed locales: \(installed.map { $0.identifier }.joined(separator: ", "))")

    if installed.map({ $0.identifier(.bcp47) }).contains(targetLocale.identifier(.bcp47)) {
      self.analyzer = SpeechAnalyzer(modules: modules)
      assert(self.analyzer != nil, "Analyzer should be set before finishing")
      continuation.yield(1.0)
      continuation.finish()
      return
    }

    do {
      if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
        let pollingTask = Task {
          while !request.progress.isFinished && !Task.isCancelled {
            continuation.yield(request.progress.fractionCompleted)
            try? await Task.sleep(for: .milliseconds(100))
          }
        }
        continuation.onTermination = { _ in pollingTask.cancel() }
        try await request.downloadAndInstall()
        continuation.yield(1.0)
      }
    } catch {
      logger.error("Asset setup failed: \(error.localizedDescription)")
      self.assetSetupError = error
    }

    self.analyzer = SpeechAnalyzer(modules: modules)
    assert(self.analyzer != nil, "Analyzer should be set before finishing")
    continuation.finish()
  }

  // MARK: - Lifecycle queries

  /// Returns `true` if the Speech model for the target locale is installed.
  public func isModelReady() async -> Bool {
    let installed = await Set(SpeechTranscriber.installedLocales)
    return installed.map({ $0.identifier(.bcp47) }).contains(targetLocale.identifier(.bcp47))
  }

  /// Returns `true` if both transcriber and analyzer are initialized.
  public func isInitialized() async -> Bool {
    transcriber != nil && analyzer != nil
  }

  /// Returns any error that occurred during asset setup.
  public func getSetupError() -> Error? {
    assetSetupError
  }

  // MARK: - Internal helpers

  func releaseAndReserveLocales() async throws {
    for existingLocale in await AssetInventory.reservedLocales {
      await AssetInventory.release(reservedLocale: existingLocale)
    }
    do {
      try await AssetInventory.reserve(locale: targetLocale)
    } catch {
      logger.error("Failed to reserve locale: \(error.localizedDescription)")
      throw error
    }
  }

  /// Downloads remote URLs to a temp file; returns local URLs unchanged.
  func resolveAudioURL(_ url: URL) async throws -> URL {
    if url.isFileURL { return url }
    let (tempFileURL, _) = try await URLSession.shared.download(from: url)
    return tempFileURL
  }
}
