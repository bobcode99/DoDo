//
//  YapTranscriptService.swift
//  PodcastAnalyzer
//
//  Actor-based service that submits audio to a local yap HTTP server
//  and streams progress/result via Server-Sent Events.
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

// MARK: - YapHealthResult

/// Result of the Test Connection probe — pairs the /health status with the
/// list of available backends so the Settings UI can confirm both reachability
/// and (when an API key is configured) authentication in one shot.
struct YapHealthResult: Sendable {
    let healthStatus: String
    let backends: [String]
    let defaultBackend: String
}

// MARK: - YapTranscriptService

actor YapTranscriptService {
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "YapTranscriptService")

    private struct SubmitResponse: Decodable { let id: String }

    /// Hits `GET /health` and `GET /backends` to confirm the yap server is
    /// reachable and that the configured API key (when present) is accepted.
    /// `/health` is auth-free; `/backends` is auth-gated, so a 401 here is a
    /// clear signal that the API key is wrong.
    func checkHealth(serverURL: String, apiKey: String?) async throws -> YapHealthResult {
        guard let base = URL(string: serverURL) else {
            throw YapError.invalidServerURL
        }

        let healthStatus = try await fetchHealth(baseURL: base, apiKey: apiKey)
        let (backends, defaultBackend) = try await fetchBackends(baseURL: base, apiKey: apiKey)
        return YapHealthResult(
            healthStatus: healthStatus,
            backends: backends,
            defaultBackend: defaultBackend
        )
    }

    private func fetchHealth(baseURL: URL, apiKey: String?) async throws -> String {
        let url = baseURL.appending(path: "health")
        var request = URLRequest(url: url)
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YapError.serverError("Non-HTTP response from /health")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw YapError.serverError("HTTP \(httpResponse.statusCode) from /health")
        }
        struct HealthResponse: Decodable { let status: String }
        return try JSONDecoder().decode(HealthResponse.self, from: data).status
    }

    private func fetchBackends(baseURL: URL, apiKey: String?) async throws -> ([String], String) {
        let url = baseURL.appending(path: "backends")
        var request = URLRequest(url: url)
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YapError.serverError("Non-HTTP response from /backends")
        }
        if httpResponse.statusCode == 401 {
            throw YapError.serverError("Unauthorized — check API key")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw YapError.serverError("HTTP \(httpResponse.statusCode) from /backends")
        }
        struct BackendsResponse: Decodable {
            let backends: [String]
            let `default`: String
        }
        let decoded = try JSONDecoder().decode(BackendsResponse.self, from: data)
        return (decoded.backends, decoded.default)
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
            logger.warning("[YapServer] cancel request failed for id=\(serverJobID): \(error.localizedDescription, privacy: .public)")
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

        return try JSONDecoder().decode(SubmitResponse.self, from: data).id
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

        return try JSONDecoder().decode(SubmitResponse.self, from: data).id
    }

    func streamEvents(
        jobID: String,
        baseURL: URL,
        apiKey: String?,
        timeout: TimeInterval,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> String {
        let url = baseURL.appending(path: "transcriptions/\(jobID)/events")
        var request = URLRequest(url: url)
        // Proper SSE client headers: without Accept: text/event-stream (and
        // no-cache) URLSession / any intermediary may buffer the whole body and
        // deliver it only at completion — which shows up as 0% then a jump to
        // 100% instead of live progress. `bytes(for:)` itself streams.
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }

        // Configure BEFORE creating the session — URLSession copies its
        // configuration at init, so mutating session.configuration is a no-op.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // max idle gap between SSE events
        config.timeoutIntervalForResource = timeout  // total wall clock for the job
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YapError.serverError("Non-HTTP response from SSE stream")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw YapError.serverError("HTTP \(httpResponse.statusCode) from SSE stream")
        }

        struct SSEEvent: Decodable {
            let id: String
            let status: String
            let progress: Int?
            let transcript: String?
            let format: String?
            let error: String?
        }

        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()

                // Dispatch on the `data:` line directly rather than waiting for the
                // frame's blank-line terminator. URLSession's AsyncLineSequence can
                // withhold that trailing empty line until the *next* frame arrives,
                // which stalls live progress (updates only land one frame late, and
                // the final one only at stream end). Each yap frame carries a single
                // self-contained JSON `data:` line, so per-line dispatch is safe.
                guard line.hasPrefix("data:") else { continue }  // skip event:/comments/blanks
                let json = line.hasPrefix("data: ") ? line.dropFirst(6) : line.dropFirst(5)
                guard let decoded = try? JSONDecoder().decode(SSEEvent.self, from: Data(json.utf8)) else {
                    continue
                }

                switch decoded.status {
                case "queued", "running":
                    if decoded.status == "running", let pct = decoded.progress {
                        onProgress?(Double(pct) / 100.0)
                    }
                    logger.debug("Yap job \(jobID) status=\(decoded.status) progress=\(decoded.progress ?? -1)")
                case "done":
                    guard let srt = decoded.transcript, !srt.isEmpty else {
                        throw YapError.emptyTranscript
                    }
                    logger.info("Yap job \(jobID) completed")
                    return srt
                case "failed":
                    throw YapError.serverError("Job failed: \(decoded.error ?? "unknown")")
                case "cancelled":
                    throw YapError.serverError("Job was cancelled")
                default:
                    break
                }
            }
        } catch let error as YapError {
            throw error  // terminal server states — don't mask them with the GET fallback
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.warning("SSE stream error for job \(jobID): \(error.localizedDescription)")
        }

        logger.warning("SSE stream ended without terminal event for job \(jobID), falling back to GET")
        return try await pollOnce(jobID: jobID, baseURL: baseURL, apiKey: apiKey, timeout: timeout)
    }

    private struct JobStatus: Decodable {
        let id: String
        let status: String
        let progress: Int?
        let transcript: String?
        let error: String?
    }

    private func pollOnce(jobID: String, baseURL: URL, apiKey: String?, timeout: TimeInterval) async throws -> String {
        let url = baseURL.appending(path: "transcriptions/\(jobID)")
        var request = URLRequest(url: url)
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw YapError.serverError("SSE stream ended without completion")
        }
        let decoded = try JSONDecoder().decode(JobStatus.self, from: data)
        switch decoded.status {
        case "done":
            guard let srt = decoded.transcript, !srt.isEmpty else {
                throw YapError.emptyTranscript
            }
            return srt
        case "failed":
            throw YapError.serverError("Job failed: \(decoded.error ?? "unknown")")
        case "cancelled":
            throw YapError.serverError("Job was cancelled")
        default:
            throw YapError.serverError("SSE stream ended without completion")
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
