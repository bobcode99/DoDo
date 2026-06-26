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
  @discardableResult
  static func save(_ token: String) -> Bool {
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
    if updateStatus == errSecSuccess { return true }
    if updateStatus == errSecItemNotFound {
      var addQuery = baseQuery
      addQuery.merge(attributes) { _, new in new }
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      return addStatus == errSecSuccess
    }
    return false
  }

  /// Generates and persists a fresh 32-byte base64url token.
  @discardableResult
  static func regenerate() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let token = Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    save(token)
    return token
  }

  /// Returns the existing token, generating one on first use.
  static func loadOrCreate() -> String {
    if let existing = load() { return existing }
    return regenerate()
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
