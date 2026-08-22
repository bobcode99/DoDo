//
//  MacMCPSettingsView.swift
//  PodcastAnalyzer
//
//  Preferences → MCP tab. Controls the embedded MCP server, headless / menubar
//  mode, launch-at-login, and emits ready-to-paste client config snippets.
//

#if os(macOS)
import AppKit
import ServiceManagement
import SwiftUI

struct MacMCPSettingsView: View {
  @State private var manager = MCPServerManager.shared
  @AppStorage(MCPMenubarController.keyHeadless) private var headless: Bool = false
  @AppStorage(MCPMenubarController.keyLaunchAtLogin) private var launchAtLogin: Bool = false
  @State private var showToken = false
  @State private var copiedHint: String?

  var body: some View {
    // Form inside an explicit ScrollView so long content never collides with
    // the Settings window's tab bar — the parent TabView constrains width to
    // 560 and provides scenePadding, so we deliberately don't set a frame
    // here.
    ScrollView {
      Form {
        serverSection
        authSection
        headlessSection
        connectSection
      }
      .formStyle(.grouped)
    }
  }

  // MARK: - Server

  @ViewBuilder
  private var serverSection: some View {
    Section {
      Toggle("Enable MCP server", isOn: $manager.enabled)

      LabeledContent("Port") {
        TextField(
          "Port",
          value: $manager.port,
          format: .number.grouping(.never)
        )
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(width: 90)
      }

      LabeledContent("Status") {
        Label {
          Text(statusLine)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        } icon: {
          Image(systemName: statusSymbol)
            .foregroundStyle(statusTint)
        }
        .accessibilityLabel(statusLine)
      }
    } header: {
      Text("Server")
    } footer: {
      Text("The server binds to 127.0.0.1 only. Clients on this Mac (Claude Code, Claude Desktop via mcp-remote, ChatGPT, etc.) can connect; nothing on the network can.")
    }
  }

  private var statusSymbol: String {
    switch manager.status {
    case .stopped: "network.slash"
    case .running: "network"
    case .error: "exclamationmark.triangle.fill"
    }
  }

  private var statusTint: Color {
    switch manager.status {
    case .stopped: .secondary
    case .running: .green
    case .error: .red
    }
  }

  private var statusLine: String {
    switch manager.status {
    case .stopped: return "Stopped"
    case .running(let url): return "Running at \(url.absoluteString)"
    case .error(let msg): return "Error: \(msg)"
    }
  }

  // MARK: - Authorization

  @ViewBuilder
  private var authSection: some View {
    Section {
      // Token gets its own row beneath the label so revealing it doesn't
      // squeeze the layout sideways.
      VStack(alignment: .leading, spacing: 8) {
        Text("Bearer token")
          .font(.callout)
        HStack(spacing: 6) {
          Text(showToken ? manager.bearerToken : String(repeating: "•", count: 24))
            .font(.system(.callout, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

          Button(
            showToken ? "Hide token" : "Reveal token",
            systemImage: showToken ? "eye.slash" : "eye"
          ) {
            showToken.toggle()
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .help(showToken ? "Hide token" : "Reveal token")

          Button("Copy token", systemImage: "doc.on.doc") {
            copyToPasteboard(manager.bearerToken)
            flashHint("Token copied")
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .help("Copy token")
        }
      }

      Button("Regenerate token", role: .destructive) {
        manager.regenerateToken()
        flashHint("Token regenerated")
      }
    } header: {
      Text("Authorization")
    } footer: {
      Text("All requests must send \"Authorization: Bearer <token>\". Regenerating invalidates any client already connected — they'll need the new token.")
    }
  }

  // MARK: - Headless / launch at login

  @ViewBuilder
  private var headlessSection: some View {
    Section {
      Toggle("Keep running in the menubar when windows close", isOn: $headless)
        .onChange(of: headless) { _, newValue in
          applyActivationPolicy(headless: newValue)
        }
      Toggle("Open at Login", isOn: $launchAtLogin)
        .onChange(of: launchAtLogin) { _, newValue in
          applyLaunchAtLogin(newValue)
        }
    } header: {
      Text("Headless")
    } footer: {
      Text("Closing the last window drops the dock icon and leaves the app in the menubar, so playback, downloads and the server keep going. Opening the app always brings the window back. Open at Login starts the app in the background after macOS login.")
    }
  }

  // MARK: - Connect a client

  @ViewBuilder
  private var connectSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text("Claude Code install command")
          .font(.callout)
        Text(displayedCLICommand)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .foregroundStyle(.secondary)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
          )
        if !showToken {
          Text("Token hidden — reveal in Authorization to see / select the full command.")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      Button("Copy Claude Code CLI command", systemImage: "doc.on.doc") {
        copyToPasteboard(claudeCodeCLICommand)
        flashHint("CLI command copied")
      }
      .help("Run this in a terminal to register the server with Claude Code")

      Button("Copy Claude Code config (HTTP)") {
        copyToPasteboard(claudeCodeConfigSnippet)
        flashHint("Claude Code config copied")
      }
      Button("Copy Claude Desktop config (stdio shim)") {
        copyToPasteboard(claudeDesktopConfigSnippet)
        flashHint("Claude Desktop config copied")
      }
      Button("Copy connection URL") {
        if let url = manager.connectionURL {
          copyToPasteboard(url.absoluteString)
          flashHint("URL copied")
        }
      }
      if let hint = copiedHint {
        Label(hint, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.caption)
          .transition(.opacity)
      }
    } header: {
      Text("Connect a client")
    } footer: {
      Text("Claude Desktop today only speaks stdio MCP. The copied snippet uses the open-source mcp-remote proxy to bridge stdio → this HTTP server. Requires Node.js installed on this Mac.")
    }
  }

  // MARK: - Config snippets

  private var claudeCodeCLICommand: String {
    cliCommand(token: manager.bearerToken)
  }

  /// Same command, but with the token replaced by a placeholder when
  /// `showToken == false` so glance-readability doesn't leak the token to
  /// anyone shoulder-surfing the Settings window.
  private var displayedCLICommand: String {
    cliCommand(token: showToken ? manager.bearerToken : "••••••••••••••••")
  }

  private func cliCommand(token: String) -> String {
    let url = manager.connectionURL?.absoluteString ?? ""
    return #"claude mcp add --transport http pod-analyzer \#(url) --header "Authorization: Bearer \#(token)""#
  }

  private var claudeCodeConfigSnippet: String {
    """
    {
      "mcpServers": {
        "podcast-analyzer": {
          "url": "\(manager.connectionURL?.absoluteString ?? "")",
          "headers": {
            "Authorization": "Bearer \(manager.bearerToken)"
          }
        }
      }
    }
    """
  }

  private var claudeDesktopConfigSnippet: String {
    """
    {
      "mcpServers": {
        "podcast-analyzer": {
          "command": "npx",
          "args": [
            "-y",
            "mcp-remote",
            "\(manager.connectionURL?.absoluteString ?? "")",
            "--header",
            "Authorization: Bearer \(manager.bearerToken)"
          ]
        }
      }
    }
    """
  }

  // MARK: - Helpers

  private func copyToPasteboard(_ string: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(string, forType: .string)
  }

  private func flashHint(_ text: String) {
    withAnimation { copiedHint = text }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation { copiedHint = nil }
    }
  }

  private func applyActivationPolicy(headless: Bool) {
    // Deliberately not `setActivationPolicy(.accessory)` directly: this
    // Preferences window is itself a window, and yanking the dock icon out
    // from under it left the app with no menu bar mid-session. The switch now
    // takes effect when the last window closes.
    MacBackgroundMode.apply()
    MCPMenubarController.shared.refresh()
  }

  private func applyLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      // Reset the toggle on failure so UI matches reality.
      launchAtLogin = !enabled
    }
  }
}

#endif
