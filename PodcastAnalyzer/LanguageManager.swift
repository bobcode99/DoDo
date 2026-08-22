import Foundation
import Observation

@Observable
@MainActor
final class LanguageManager {
  static let shared = LanguageManager()

  // Stored property so @Observable can track changes and update the UI instantly
  var appLanguage: String {
    didSet { UserDefaults.standard.set(appLanguage, forKey: "appLanguage") }
  }

  private init() {
    self.appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
  }

  var locale: Locale {
    if appLanguage == "system" {
      // If the device's primary language is one we support, honour it.
      // Otherwise fall back to English so unsupported languages (Japanese,
      // Korean, Hindi, …) don't result in missing strings.
      let primary = Locale.preferredLanguages.first ?? "en"
      let isSupported = Self.supportedLanguageIDs.contains { primary.hasPrefix($0) }
      return isSupported ? .autoupdatingCurrent : Locale(identifier: "en")
    }
    return Locale(identifier: appLanguage)
  }

  /// Language IDs (excluding "system") that have translations in Localizable.xcstrings.
  private static let supportedLanguageIDs: [String] = availableLanguages
    .map(\.id)
    .filter { $0 != "system" }

  struct AppLanguage: Identifiable {
    let id: String
    let displayName: String  // in its own language
  }

  static let availableLanguages: [AppLanguage] = [
    AppLanguage(id: "system", displayName: "System Default"),
    AppLanguage(id: "en", displayName: "English"),
    AppLanguage(id: "zh-Hant", displayName: "繁體中文"),
    AppLanguage(id: "zh-Hans", displayName: "简体中文"),
  ]
}

// MARK: - Localizing for String-typed APIs

extension LanguageManager {
  /// Bundle carrying the app-language strings, or nil to use the default.
  ///
  /// Selecting a language means selecting a *bundle*: `String(localized:)` reads
  /// the system language, and its `locale:` argument only controls how numbers
  /// and dates inside the string are formatted — it does not choose the table.
  var stringsBundle: Bundle? {
    guard appLanguage != "system",
          let path = Bundle.main.path(forResource: appLanguage, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return nil }
    return bundle
  }
}

extension String {
  /// Localize against the app's own language setting.
  ///
  /// SwiftUI views taking a `LocalizedStringKey` don't need this — they resolve
  /// through `\.environment(\.locale)` already. Use it only where an API
  /// genuinely requires a `String`, and prefer restructuring so the literal
  /// reaches a `Text` instead.
  @MainActor
  static func appLocalized(_ key: String) -> String {
    guard let bundle = LanguageManager.shared.stringsBundle else {
      return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
  }
}
