//
//  FoundationModelsAvailability.swift
//  PodcastAnalyzer
//
//  Whether Apple's on-device model can run, for the Settings UI that reports it.
//
//  All this file has left. `AppleFoundationModelsService` lived here and existed
//  only to generate the "For You" recommendations, which were removed — see
//  DOCS/DEPRECATED.md. Transcript analysis has always gone
//  through CloudAIService instead: the on-device context window is ~4096 tokens,
//  which a real transcript blows past immediately.
//

import Foundation
import FoundationModels

/// Why the on-device model can't run.
///
/// A case rather than a `String`: these are shown in Settings, and as free-form
/// English they could never reach the string catalog. The view maps them to
/// localized text.
nonisolated enum FoundationModelsUnavailableReason: Equatable {
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case other
}

nonisolated enum FoundationModelsAvailability: Equatable {
    case available
    case unavailable(FoundationModelsUnavailableReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: FoundationModelsUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }

    /// The system's answer, read synchronously.
    ///
    /// `SystemLanguageModel.default.availability` is a plain synchronous
    /// property; reaching it only through an actor forced every caller to be
    /// async, and views need the answer while building a body. There is
    /// therefore no window in which the answer is unknown — which is why there
    /// is no "checking" state.
    static var current: FoundationModelsAvailability {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            return .unavailable(.deviceNotEligible)
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable:
            return .unavailable(.other)
        }
    }

    /// Whether this device could ever run the on-device model.
    ///
    /// Deliberately weaker than `isAvailable`. Apple Intelligence being switched
    /// off, or the model still downloading, are states the user can get out of,
    /// so the UI for those stays visible and says how. Ineligible hardware — or
    /// an OS below 26 — never becomes eligible, so its UI is hidden instead of
    /// shown permanently broken.
    static var isSupported: Bool {
        current != .unavailable(.deviceNotEligible)
    }
}
