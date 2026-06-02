//
//  YapTranscriptService.swift
//  PodcastAnalyzer
//
//  Actor-based service that submits audio to a local yap HTTP server
//  and polls for the completed SRT transcript.
//

import Foundation
import OSLog

// MARK: - YapError

enum YapError: LocalizedError {
    case invalidServerURL
    case serverError(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "The yap server URL is invalid. Check Settings > Transcript > Yap Server."
        case .serverError(let message):
            "Yap server error: \(message)"
        case .emptyTranscript:
            "The yap server returned an empty transcript."
        }
    }
}

// MARK: - YapTranscriptService

actor YapTranscriptService {
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "YapTranscriptService")

    /// Uploads the audio file to the yap server and polls until the transcript is ready.
    ///
    /// Uses `URLSession.shared.upload(for:fromFile:)` to stream the audio without
    /// loading it into memory.
    ///
    /// - Parameter onProgress: Called with a 0.0–1.0 fraction each time the server
    ///   reports a `running` status. The closure is invoked synchronously on the
    ///   YapTranscriptService actor — use `Task { await ... }` inside it to hop to
    ///   another actor if needed.
    func transcribeToSRT(
        audioURL: URL,
        locale: String?,
        serverURL: String,
        apiKey: String?,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onJobSubmitted: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let base = URL(string: serverURL) else {
            throw YapError.invalidServerURL
        }

        let jobID = try await submitJob(
            audioURL: audioURL,
            locale: locale,
            baseURL: base,
            apiKey: apiKey
        )

        logger.info("Yap job submitted, id=\(jobID)")
        onJobSubmitted?(jobID)

        return try await pollForResult(jobID: jobID, baseURL: base, apiKey: apiKey, onProgress: onProgress)
    }

    /// Submits a remote audio URL to the yap server (JSON body mode).
    /// Use this when the episode hasn't been downloaded locally.
    ///
    /// - Parameter onProgress: Called with a 0.0–1.0 fraction each time the server
    ///   reports a `running` status. See ``transcribeToSRT`` for threading notes.
    func transcribeRemoteURL(
        remoteURL: String,
        locale: String?,
        serverURL: String,
        apiKey: String?,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onJobSubmitted: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let base = URL(string: serverURL) else {
            throw YapError.invalidServerURL
        }
        let jobID = try await submitRemoteURLJob(
            remoteURL: remoteURL,
            locale: locale,
            baseURL: base,
            apiKey: apiKey
        )
        logger.info("Yap remote-URL job submitted, id=\(jobID)")
        onJobSubmitted?(jobID)
        return try await pollForResult(jobID: jobID, baseURL: base, apiKey: apiKey, onProgress: onProgress)
    }

    /// Sends DELETE /transcriptions/{id} to cancel a queued or running yap server job.
    /// 204 = cancelled, 409 = already done — both are acceptable, all others are logged.
    func cancelJob(serverJobID: String, baseURL: URL, apiKey: String?) async {
        let url = baseURL.appending(path: "transcriptions/\(serverJobID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if status == 204 {
                logger.info("[YapServer] cancelled server job id=\(serverJobID)")
            } else if status == 409 {
                logger.info("[YapServer] job id=\(serverJobID) already finished, cancel ignored")
            } else {
                logger.warning("[YapServer] DELETE /transcriptions/\(serverJobID) returned HTTP \(status)")
            }
        } catch {
            logger.warning("[YapServer] cancel request failed for id=\(serverJobID): \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    func submitJob(
        audioURL: URL,
        locale: String?,
        baseURL: URL,
        apiKey: String?,
        name: String? = nil,
        detectMusic: Bool? = nil,
        musicSensitivity: String? = nil
    ) async throws -> String {
        let maxLen = maxLength(for: locale)
        var components = URLComponents(url: baseURL.appending(path: "transcriptions"), resolvingAgainstBaseURL: false)!
        let resolvedLocale = locale.map { normalizeLocale($0) }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "format", value: "srt"),
            URLQueryItem(name: "max_length", value: "\(maxLen)")
        ]
        if let loc = resolvedLocale {
            queryItems.append(URLQueryItem(name: "locale", value: loc))
        }
        if let name {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }
        if let detectMusic {
            queryItems.append(URLQueryItem(name: "detect_music", value: detectMusic ? "true" : "false"))
        }
        if let musicSensitivity {
            queryItems.append(URLQueryItem(name: "music_sensitivity", value: musicSensitivity))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw YapError.invalidServerURL
        }

        logger.info("[YapServer] submitJob locale_in=\(locale ?? "<nil>") locale_out=\(resolvedLocale ?? "<omitted>") url=\(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType(for: audioURL), forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: audioURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YapError.serverError("Non-HTTP response received")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw YapError.serverError("HTTP \(httpResponse.statusCode): \(body)")
        }

        struct SubmitResponse: Decodable {
            let id: String
        }
        let decoded = try JSONDecoder().decode(SubmitResponse.self, from: data)
        return decoded.id
    }

    func submitRemoteURLJob(
        remoteURL: String,
        locale: String?,
        baseURL: URL,
        apiKey: String?,
        name: String? = nil,
        detectMusic: Bool? = nil,
        musicSensitivity: String? = nil
    ) async throws -> String {
        let url = baseURL.appending(path: "transcriptions")

        let resolvedLocale = locale.map { normalizeLocale($0) }
        var body: [String: Any] = [
            "url": remoteURL,
            "format": "srt",
            "max_length": maxLength(for: locale)
        ]
        if let loc = resolvedLocale {
            body["locale"] = loc
        }
        if let name {
            body["name"] = name
        }
        if let detectMusic {
            body["detect_music"] = detectMusic
        }
        if let musicSensitivity {
            body["music_sensitivity"] = musicSensitivity
        }

        logger.info("[YapServer] submitRemoteURLJob locale_in=\(locale ?? "<nil>") locale_out=\(resolvedLocale ?? "<omitted>") body=\(body)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YapError.serverError("Non-HTTP response received")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let bodyStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw YapError.serverError("HTTP \(httpResponse.statusCode): \(bodyStr)")
        }

        struct SubmitResponse: Decodable { let id: String }
        return try JSONDecoder().decode(SubmitResponse.self, from: data).id
    }

    func pollForResult(
        jobID: String,
        baseURL: URL,
        apiKey: String?,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let pollURL = baseURL.appending(path: "transcriptions/\(jobID)")
        var delay: Duration = .seconds(1)
        let maxDelay: Duration = .seconds(5)

        while true {
            try Task.checkCancellation()

            try await Task.sleep(for: delay)
            delay = min(delay * 2, maxDelay)

            try Task.checkCancellation()

            var request = URLRequest(url: pollURL)
            if let key = apiKey, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "X-API-Key")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw YapError.serverError("Non-HTTP response while polling")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "unknown"
                throw YapError.serverError("HTTP \(httpResponse.statusCode): \(body)")
            }

            struct PollResponse: Decodable {
                let id: String
                let status: String
                let progress: Int?   // 0–99 when status == "running"
                let format: String?
                let transcript: String?
                let error: String?
            }
            let decoded = try JSONDecoder().decode(PollResponse.self, from: data)

            switch decoded.status {
            case "queued", "running":
                if decoded.status == "running", let pct = decoded.progress {
                    // Divide by 100 so the maximum running value is 0.99;
                    // 1.0 is reserved for the explicit "done" signal in the caller.
                    onProgress?(Double(pct) / 100.0)
                }
                logger.debug("Yap job \(jobID) status=\(decoded.status), retrying…")
                continue
            case "done":
                guard let srt = decoded.transcript, !srt.isEmpty else {
                    throw YapError.emptyTranscript
                }
                logger.info("Yap job \(jobID) completed")
                return srt
            case "failed":
                let detail = decoded.error ?? "unknown"
                throw YapError.serverError("Job failed: \(detail)")
            default:
                throw YapError.serverError("Unknown status '\(decoded.status)'")
            }
        }
    }

    // MARK: - Utilities

    /// Maps a raw podcast language code to a yap-compatible BCP 47 locale.
    ///
    /// Mirrors the logic in `TranscriptService.locale(fromPodcastLanguage:)` but outputs
    /// hyphen-separated BCP 47 (e.g. "zh-TW") instead of Foundation underscore format.
    ///
    /// Handles:
    /// - Bare language codes:  "en"      → "en-US"
    /// - Script subtags:       "zh-Hant" → "zh-TW",  "zh-Hans" → "zh-CN"
    /// - Foundation format:    "zh_TW"   → "zh-TW"
    /// - Already correct:      "zh-TW"   → "zh-TW"
    private func normalizeLocale(_ raw: String) -> String {
        // Normalise separators and case for matching
        let lower = raw.lowercased().replacingOccurrences(of: "_", with: "-")

        // Script subtag overrides (must come before the generic split below)
        let scriptMap: [String: String] = [
            "zh-hant": "zh-TW",
            "zh-hans": "zh-CN",
            "zh-hk":   "zh-HK",
            "zh-tw":   "zh-TW",
            "zh-cn":   "zh-CN",
            "yue-cn":  "yue-CN",
        ]
        if let mapped = scriptMap[lower] { return mapped }

        // Bare language code → default region (same table as TranscriptService)
        let defaultRegion: [String: String] = [
            "en": "en-US", "zh": "zh-TW", "ja": "ja-JP", "ko": "ko-KR",
            "fr": "fr-FR", "de": "de-DE", "es": "es-ES", "it": "it-IT",
            "pt": "pt-BR", "ru": "ru-RU", "ar": "ar-SA", "hi": "hi-IN",
            "th": "th-TH", "vi": "vi-VN", "id": "id-ID", "ms": "ms-MY",
            "nl": "nl-NL", "pl": "pl-PL", "tr": "tr-TR", "uk": "uk-UA",
        ]
        if let mapped = defaultRegion[lower] { return mapped }

        // "xx-yy" → normalise to "xx-YY" (lowercase lang, uppercase region)
        let parts = lower.split(separator: "-", maxSplits: 1)
        if parts.count == 2 {
            return "\(parts[0])-\(parts[1].uppercased())"
        }

        return raw
    }

    /// Returns 18 for CJK locales (zh-*, ja-*, ko-*), 40 for all others.
    private func maxLength(for locale: String?) -> Int {
        guard let locale else { return 40 }
        let prefix = locale.prefix(3).lowercased()
        if prefix == "zh-" || prefix == "ja-" || prefix == "ko-" { return 18 }
        let code = locale.prefix(2).lowercased()
        if code == "zh" || code == "ja" || code == "ko" { return 18 }
        return 40
    }

    /// Maps common audio file extensions to MIME types.
    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":  return "audio/mpeg"
        case "wav":  return "audio/wav"
        case "m4a", "mp4": return "audio/mp4"
        default:     return "audio/mpeg"
        }
    }
}
