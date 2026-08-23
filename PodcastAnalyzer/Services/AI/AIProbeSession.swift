//
//  AIProbeSession.swift
//  PodcastAnalyzer
//
//  The URLSession used for reachability probes — "Test Connection", model-list
//  fetches, yap /health.
//
//  These all ran on `URLSession.shared`, whose `timeoutIntervalForRequest`
//  defaults to 60s. A host that is simply absent (typo'd LAN IP, laptop asleep,
//  server not started) drops the SYN rather than refusing it, so nothing comes
//  back and the probe sat spinning for the full minute — and longer where a
//  client falls back to a second endpoint after the first fails.
//
//  A probe is a question with a fast answer: the server replies from memory or
//  it is not there. Ten seconds is generous for a LAN round trip and short
//  enough that a wrong address reads as wrong instead of as broken.
//
//  Chat completions deliberately do NOT use this session — a cold model load or
//  a long generation legitimately takes minutes.
//

import Foundation

nonisolated enum AIProbe {
    /// Wall clock for one probe request. Also the connect timeout, which is the
    /// case that actually mattered here.
    static let timeout: TimeInterval = 10

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        // Without this a probe on a device with no route queues until the
        // network returns instead of failing — the spinner never resolves.
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// True when the request never reached a server, as opposed to reaching one
    /// that answered unhelpfully.
    ///
    /// Clients that try a second endpoint when the first fails must not retry on
    /// these: the host is unreachable, so the fallback pays the same timeout
    /// again and doubles the wait for a guaranteed second failure.
    static func isUnreachable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotFindHost, .cannotConnectToHost, .timedOut,
             .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection:
            return true
        default:
            return false
        }
    }
}
