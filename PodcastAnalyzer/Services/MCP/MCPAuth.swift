//
//  MCPAuth.swift
//  PodcastAnalyzer
//
//  Bearer-token storage (Keychain) + HTTPRequestValidator for the MCP server.
//

#if os(macOS)
import Foundation
import MCP
import Security

/// Keychain-backed storage for the MCP server's pre-shared bearer token.
/// All API is `@MainActor` because the manager + Settings UI live there.
@MainActor
enum MCPTokenStore {
  private static let service = "com.jn.PodcastAnalyzer.mcp"
  private static let account = "bearerToken"

  /// Loads the existing token from Keychain, or returns nil if none has been generated.
  static func load() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let token = String(data: data, encoding: .utf8)
    else { return nil }
    return token
  }

  /// Writes the token to Keychain, replacing any existing value.
  /// Returns the underlying `OSStatus` so callers can report *why* a write failed
  /// — a token the user copied out of Settings but that never reached the
  /// Keychain would silently stop working on the next launch.
  @discardableResult
  static func save(_ token: String) -> OSStatus {
    let baseQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [
      kSecValueData as String: Data(token.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess { return updateStatus }
    if updateStatus == errSecItemNotFound {
      var addQuery = baseQuery
      addQuery.merge(attributes) { _, new in new }
      return SecItemAdd(addQuery as CFDictionary, nil)
    }
    return updateStatus
  }

  /// Generates and persists a fresh 32-byte base64url token.
  /// Throws when the Keychain write fails: returning an unpersisted token would
  /// have the user configure their MCP client with a value the server forgets
  /// on relaunch.
  static func regenerate() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let randomStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard randomStatus == errSecSuccess else {
      // `bytes` is still all zeros here, which would install a trivially
      // guessable bearer token on a listening socket. Refuse instead.
      throw MCPTokenStoreError.entropyUnavailable(randomStatus)
    }
    let token = Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    let saveStatus = save(token)
    guard saveStatus == errSecSuccess else {
      throw MCPTokenStoreError.keychainWriteFailed(saveStatus)
    }
    return token
  }

  /// Returns the existing token, generating one on first use.
  static func loadOrCreate() throws -> String {
    if let existing = load() { return existing }
    return try regenerate()
  }
}

/// Why the MCP server has no usable bearer token.
enum MCPTokenStoreError: LocalizedError {
  case entropyUnavailable(OSStatus)
  case keychainWriteFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .entropyUnavailable(let status):
      return "Could not generate a secure token (SecRandomCopyBytes: \(status))."
    case .keychainWriteFailed(let status):
      return "Could not save the token to the Keychain (OSStatus \(status))."
    }
  }
}

/// Validator that rejects any request lacking `Authorization: Bearer <token>`.
/// Skips validation for unauthenticated probes (e.g. `/healthz`) by short-
/// circuiting outside this validator — the validator sees only requests
/// routed to the MCP endpoint.
nonisolated struct MCPBearerTokenValidator: HTTPRequestValidator {
  let expectedToken: String

  func validate(_ request: HTTPRequest, context: HTTPValidationContext) -> HTTPResponse? {
    guard let header = request.header("Authorization") else {
      return .error(statusCode: 401, .invalidRequest("Missing Authorization header"))
    }
    let prefix = "Bearer "
    guard header.hasPrefix(prefix) else {
      return .error(statusCode: 401, .invalidRequest("Authorization must be a Bearer token"))
    }
    let presented = String(header.dropFirst(prefix.count))
    // Constant-time compare to avoid token leakage via timing.
    guard timingSafeEqual(presented, expectedToken) else {
      return .error(statusCode: 401, .invalidRequest("Invalid token"))
    }
    return nil
  }

  private func timingSafeEqual(_ a: String, _ b: String) -> Bool {
    let ad = Array(a.utf8)
    let bd = Array(b.utf8)
    guard ad.count == bd.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<ad.count {
      diff |= ad[i] ^ bd[i]
    }
    return diff == 0
  }
}

#endif
