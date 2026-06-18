//
//  MCPHTTPServer.swift
//  PodcastAnalyzer
//
//  Hummingbird wrapper that exposes the MCP StatelessHTTPServerTransport on
//  127.0.0.1:<port> with a single `POST /mcp` endpoint and a `GET /healthz`
//  probe. Bearer-token validation is enforced inside the transport's
//  validation pipeline.
//

#if os(macOS)
import Foundation
import Hummingbird
import HTTPTypes
import MCP
import NIOCore
import NIOFoundationCompat
import OSLog
import ServiceLifecycle

/// Encapsulates the running state of the embedded MCP HTTP server.
@MainActor
final class MCPHTTPServer {

  // Public state
  let port: Int
  let bearerToken: String

  // Runtime
  private var serverTask: Task<Void, Error>?
  private var mcpServer: Server?
  private var transport: StatelessHTTPServerTransport?

  // Logging
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "MCPHTTPServer")

  init(port: Int, bearerToken: String) {
    self.port = port
    self.bearerToken = bearerToken
  }

  // MARK: - Lifecycle

  /// Starts the server. Returns once it is accepting connections (best effort) or throws on bind failure.
  func start(gateway: MCPDataGateway) async throws {
    guard serverTask == nil else { return }

    // 1. Build the validation pipeline: localhost-only + JSON Accept + content-type
    //    + protocol-version + bearer-token.
    let pipeline = StandardValidationPipeline(validators: [
      OriginValidator.localhost(),
      AcceptHeaderValidator(mode: .jsonOnly),
      ContentTypeValidator(),
      ProtocolVersionValidator(),
      MCPBearerTokenValidator(expectedToken: bearerToken),
    ])
    let transport = StatelessHTTPServerTransport(validationPipeline: pipeline)
    self.transport = transport

    // 2. Build the MCP server and register handlers.
    let server = Server(
      name: "PodcastAnalyzer",
      version: "1.0.0",
      capabilities: .init(tools: .init(listChanged: false))
    )
    self.mcpServer = server

    _ = await server.withMethodHandler(ListTools.self) { _ in
      return ListTools.Result(tools: MCPTools.allTools)
    }
    _ = await server.withMethodHandler(CallTool.self) { params in
      // Gateway hits SwiftData on the main actor; the dispatcher does the hop.
      await MCPTools.dispatch(params, gateway: gateway)
    }

    try await server.start(transport: transport)

    // 3. Build Hummingbird router with /mcp and /healthz.
    let router = Router()
    let bridge = MCPHTTPBridge(transport: transport)
    let healthz = MCPHealthHandler()

    router.post("/mcp") { request, _ -> Response in
      try await bridge.handle(request: request)
    }
    router.get("/healthz") { _, _ -> Response in
      healthz.respond()
    }

    let app = Application(
      router: router,
      configuration: ApplicationConfiguration(
        address: .hostname("127.0.0.1", port: port),
        serverName: "PodcastAnalyzer-MCP"
      )
    )

    // 4. Run inside a Task. Cancellation triggers ServiceGroup graceful shutdown.
    self.serverTask = Task { [logger] in
      do {
        try await app.run()
      } catch {
        if !(error is CancellationError) {
          logger.error("Hummingbird server exited: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  func stop() async {
    serverTask?.cancel()
    _ = try? await serverTask?.value
    serverTask = nil
    if let server = mcpServer {
      await server.stop()
    }
    mcpServer = nil
    transport = nil
  }

  var isRunning: Bool { serverTask != nil }
}

// MARK: - Hummingbird ↔ MCP request bridge

/// `Sendable` adapter that translates Hummingbird requests to MCP HTTP requests,
/// invokes the transport, and translates the response back. Captures the
/// transport by reference (it's an `actor`) for use inside Hummingbird's
/// `@Sendable` route handler.
struct MCPHTTPBridge: Sendable {
  let transport: StatelessHTTPServerTransport

  /// Maximum request body — generous for tool-call JSON, refused beyond this.
  private static let maxBodyBytes = 4 * 1024 * 1024

  func handle(request: Hummingbird.Request) async throws -> Hummingbird.Response {
    // 1. Collect body bytes.
    var mutableRequest = request
    let buffer = try await mutableRequest.collectBody(upTo: Self.maxBodyBytes)
    let bodyData = buffer.readableBytes > 0
      ? Data(buffer.readableBytesView)
      : nil

    // 2. Convert headers HTTPFields → [String:String].
    var headers: [String: String] = [:]
    for field in request.headers {
      headers[field.name.canonicalName] = field.value
    }

    // 3. Build MCP.HTTPRequest and hand off.
    let mcpRequest = MCP.HTTPRequest(
      method: request.method.rawValue,
      headers: headers,
      body: bodyData,
      path: request.uri.path
    )
    let mcpResponse = await transport.handleRequest(mcpRequest)

    // 4. Translate MCP.HTTPResponse → Hummingbird Response.
    return Self.convert(mcpResponse)
  }

  private static func convert(_ mcpResponse: MCP.HTTPResponse) -> Hummingbird.Response {
    var responseHeaders = HTTPFields()
    for (key, value) in mcpResponse.headers {
      if let name = HTTPField.Name(key) {
        responseHeaders[name] = value
      }
    }
    let status = HTTPResponse.Status(code: mcpResponse.statusCode)

    if let data = mcpResponse.bodyData {
      let buffer = ByteBuffer(data: data)
      return Hummingbird.Response(
        status: status,
        headers: responseHeaders,
        body: .init(byteBuffer: buffer)
      )
    }
    return Hummingbird.Response(status: status, headers: responseHeaders)
  }
}

// MARK: - Healthz

nonisolated struct MCPHealthHandler: Sendable {
  func respond() -> Hummingbird.Response {
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    let body = Data("""
      {"status":"ok","server":"PodcastAnalyzer-MCP"}
      """.utf8)
    return Hummingbird.Response(
      status: .ok,
      headers: headers,
      body: .init(byteBuffer: ByteBuffer(data: body))
    )
  }
}

#endif
