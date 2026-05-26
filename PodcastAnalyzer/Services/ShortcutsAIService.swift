//
//  ShortcutsAIService.swift
//  PodcastAnalyzer
//
//  Service for invoking Apple Shortcuts for AI analysis
//  Runs shortcuts directly with x-callback-url and gets results back
//

import Foundation
import OSLog

#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let logger = Logger(subsystem: "com.podcastanalyzer", category: "ShortcutsAIService")

// MARK: - Shortcuts AI Service

@MainActor
@Observable
class ShortcutsAIService {
    static let shared = ShortcutsAIService()

    var isProcessing = false
    var lastResult: String?
    var lastError: String?

    /// The currently selected (active) shortcut name.
    var shortcutName: String {
        didSet {
            UserDefaults.standard.set(shortcutName, forKey: "shortcuts_ai_name")
            // Keep it present in the saved list
            if !shortcutNames.contains(shortcutName) {
                shortcutNames.append(shortcutName)
            }
        }
    }

    /// All saved shortcut names (the selectable list).
    var shortcutNames: [String] {
        didSet { saveShortcutNames() }
    }

    // Continuation for async/await support
    private var pendingContinuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    // The input we wrote to the clipboard for the in-flight shortcut run.
    // Used to reject the clipboard fallback when it still contains our own
    // prompt (shortcut never wrote back). Cleared on every result/error.
    private var pendingClipboardInput: String?

    // Default shortcut name
    static let defaultShortcutName = "PA-WithAIViaGPT" // CHANGE THIS TO THE NAME OF YOUR SHORTCUT

    private init() {
        // Load the saved list, falling back to the legacy single-name key.
        // Use a local variable so the assignment to shortcutName below
        // never reads self.shortcutNames through @Observable during init.
        let loadedNames: [String]
        if let data = UserDefaults.standard.data(forKey: "shortcuts_ai_names"),
           let decoded = try? JSONDecoder().decode([String].self, from: data),
           !decoded.isEmpty {
            loadedNames = decoded
        } else {
            let legacy = UserDefaults.standard.string(forKey: "shortcuts_ai_name")
                ?? Self.defaultShortcutName
            loadedNames = [legacy]
        }
        self.shortcutNames = loadedNames

        // Resolve the active name without touching self.shortcutNames
        let saved = UserDefaults.standard.string(forKey: "shortcuts_ai_name") ?? loadedNames[0]
        self.shortcutName = loadedNames.contains(saved) ? saved : loadedNames[0]

        setupNotificationObserver()
    }

    // MARK: - Shortcut List Management

    func addShortcutName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !shortcutNames.contains(trimmed) else { return }
        shortcutNames.append(trimmed)
        shortcutName = trimmed  // auto-select the newly added shortcut
    }

    func removeShortcutName(_ name: String) {
        shortcutNames.removeAll { $0 == name }
        if shortcutNames.isEmpty {
            shortcutNames = [Self.defaultShortcutName]
        }
        if shortcutName == name {
            shortcutName = shortcutNames[0]
        }
    }

    private func saveShortcutNames() {
        if let data = try? JSONEncoder().encode(shortcutNames) {
            UserDefaults.standard.set(data, forKey: "shortcuts_ai_names")
        }
    }

    // MARK: - Setup

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: .shortcutsAnalysisCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let result = notification.userInfo?["result"] as? String else { return }
            Task { @MainActor [self] in
                logger.info("App Intent delivered result (\(result.count) chars) via SaveAnalysisResultIntent")
                self.handleResult(result)
            }
        }
    }

    // MARK: - URL Callback Handling

    /// Call this from SceneDelegate/AppDelegate when receiving a URL
    func handleURL(_ url: URL) {
        logger.info("Received callback URL: \(url.absoluteString)")

        guard url.scheme == "podcastanalyzer" else { return }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if url.host == "shortcut-result" {
            // Parse result from URL
            if let resultItem = components.queryItems?.first(where: { $0.name == "result" }),
               let result = resultItem.value?.removingPercentEncoding {
                handleResult(result)
            } else if let outputItem = components.queryItems?.first(where: { $0.name == "output" }),
                      let result = outputItem.value?.removingPercentEncoding {
                handleResult(result)
            }
        } else if url.host == "shortcut-error" {
            if let errorItem = components.queryItems?.first(where: { $0.name == "error" }),
               let error = errorItem.value?.removingPercentEncoding {
                handleError(error)
            }
        } else if url.host == "x-callback-url" {
            // Handle x-callback-url format
            handleXCallbackURL(url)
        }
    }

    private func handleXCallbackURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        // The path indicates success, error, or cancel
        switch url.path {
        case "/success":
            let queryResult = components.queryItems?
                .first(where: { $0.name == "result" || $0.name == "output" })?
                .value?
                .removingPercentEncoding
            let trimmedQuery = queryResult?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let value = trimmedQuery, !value.isEmpty {
                // Shortcuts returned the result inline via x-callback. Use it.
                logger.info("x-success delivered result via query param (\(value.count) chars)")
                handleResult(value)
                return
            }

            // result=<empty> or missing — Shortcuts likely truncated a large
            // output. Fall back to the clipboard, but reject the value if it
            // still matches the input we wrote there (shortcut never copied
            // its output back, so the clipboard echo would be misleading).
            logger.warning("x-success had no usable result param — falling back to clipboard")
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Brief delay so the shortcut's final "Copy to Clipboard" has
                // time to land on the pasteboard before we read it.
                try? await Task.sleep(for: .milliseconds(200))
                self.resolveFromClipboardFallback()
            }
        case "/error":
            let errorMsg = components.queryItems?.first(where: { $0.name == "errorMessage" })?.value?.removingPercentEncoding ?? "Shortcut failed"
            handleError(errorMsg)
        case "/cancel":
            handleError("Shortcut was cancelled")
        default:
            resolveFromClipboardFallback()
        }
    }

    /// Reads the clipboard and resolves the pending continuation with it,
    /// unless the clipboard still contains the input we wrote there (which
    /// means the shortcut never copied its output back).
    private func resolveFromClipboardFallback() {
        guard let clipboardContent = PlatformClipboard.string,
              !clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            handleError("Shortcut returned no output. Add a 'Save Analysis Result' action at the end of your shortcut (recommended), or end with 'Copy to Clipboard'.")
            return
        }

        if let input = pendingClipboardInput, clipboardContent == input {
            handleError("Shortcut didn't write its result back. Add a 'Save Analysis Result' action at the end of your shortcut, or end with 'Copy to Clipboard'.")
            return
        }

        handleResult(clipboardContent)
    }

    private func handleResult(_ result: String) {
        logger.info("Received shortcut result: \(result.prefix(100))...")
        isProcessing = false
        lastResult = result
        lastError = nil
        timeoutTask?.cancel()
        pendingClipboardInput = nil
        pendingContinuation?.resume(returning: result)
        pendingContinuation = nil

        // Bring our app back to foreground
        activateApp()
    }

    /// Brings our app to foreground after shortcut completes
    private func activateApp() {
        #if os(macOS)
        // Activate our app window
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Also bring windows to front
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
        #endif
        // iOS doesn't need this - the URL callback automatically brings the app forward
    }

    private func handleError(_ error: String) {
        logger.error("Shortcut error: \(error)")
        isProcessing = false
        lastError = error
        timeoutTask?.cancel()
        pendingClipboardInput = nil
        pendingContinuation?.resume(throwing: ShortcutsError.shortcutFailed(error))
        pendingContinuation = nil

        // Bring our app back to foreground
        activateApp()
    }

    // MARK: - Run Shortcut Directly

    /// Runs the configured shortcut with input and waits for result
    func runShortcut(
        input: String,
        timeout: TimeInterval = 120
    ) async throws -> String {
        #if os(macOS)
        // On macOS, use AppleScript for smoother experience (runs in background)
        return try await runShortcutViaAppleScript(input: input, timeout: timeout)
        #else
        // On iOS, use URL scheme (requires app switch)
        return try await runShortcutViaURLScheme(input: input, timeout: timeout)
        #endif
    }

    // MARK: - macOS: CLI Method (Background Execution)

    #if os(macOS)
    /// Runs shortcut via command-line tool - background execution on macOS
    /// Falls back to URL scheme if CLI fails (e.g., sandbox restrictions)
    private func runShortcutViaAppleScript(
        input: String,
        timeout: TimeInterval = 120
    ) async throws -> String {
        // Try CLI method first (runs in background)
        do {
            return try await runShortcutViaCLI(input: input, timeout: timeout)
        } catch {
            // CLI failed - fall back to URL scheme (opens Shortcuts app briefly)
            logger.warning("CLI method failed: \(error.localizedDescription). Falling back to URL scheme.")
            return try await runShortcutViaURLScheme(input: input, timeout: timeout)
        }
    }

    /// Runs shortcut via /usr/bin/shortcuts CLI - completely in background
    private func runShortcutViaCLI(
        input: String,
        timeout: TimeInterval = 120
    ) async throws -> String {
        isProcessing = true
        lastError = nil

        // Use clipboard for input - shortcut should use "Get Clipboard" action
        PlatformClipboard.string = input
        logger.info("Running shortcut via CLI: \(self.shortcutName)")

        // Capture values for sendable closure
        let shortcutNameCopy = shortcutName
        let inputCopy = input

        defer { isProcessing = false }

        // Use task group for timeout handling
        return try await withThrowingTaskGroup(of: ShortcutCLIResult.self) { group in
            // Process execution task
            group.addTask {
                try await Self.executeShortcutProcess(shortcutName: shortcutNameCopy, input: inputCopy)
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw ShortcutsError.timeout
            }

            // Wait for first result
            guard let result = try await group.next() else {
                throw ShortcutsError.noResult
            }
            group.cancelAll()

            // Process the result
            if let error = result.error {
                self.lastError = error
                throw ShortcutsError.shortcutFailed(error)
            } else if let output = result.output {
                self.lastResult = output
                return output
            } else {
                throw ShortcutsError.noResult
            }
        }
    }

    /// Sendable result from CLI execution
    private struct ShortcutCLIResult: Sendable {
        let output: String?
        let error: String?
    }

    /// Nonisolated helper to execute the shortcuts CLI process
    /// Detached to avoid blocking @MainActor with synchronous Process I/O
    private nonisolated static func executeShortcutProcess(
        shortcutName: String,
        input: String
    ) async throws -> ShortcutCLIResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", shortcutName]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            if process.terminationStatus != 0 {
                let errorMsg = errorOutput ?? "Shortcut execution failed (exit code: \(process.terminationStatus))"
                return ShortcutCLIResult(output: nil, error: errorMsg)
            } else if let output = output, !output.isEmpty {
                return ShortcutCLIResult(output: output, error: nil)
            } else {
                // Check clipboard for result on MainActor (pasteboard requires main thread)
                let clipboardResult = await MainActor.run { PlatformClipboard.string }
                if let clipboardResult, !clipboardResult.isEmpty, clipboardResult != input {
                    return ShortcutCLIResult(output: clipboardResult, error: nil)
                } else {
                    return ShortcutCLIResult(output: nil, error: nil)
                }
            }
        }.value
    }
    #endif

    // MARK: - iOS: URL Scheme Method (Requires App Switch)

    /// Runs shortcut via URL scheme - required for iOS
    private func runShortcutViaURLScheme(
        input: String,
        timeout: TimeInterval = 120
    ) async throws -> String {
        isProcessing = true
        lastError = nil

        // For long input, use clipboard
        let useClipboard = input.count > 2000

        if useClipboard {
            PlatformClipboard.string = input
            pendingClipboardInput = input
        } else {
            pendingClipboardInput = nil
        }

        // Build URL with x-callback-url
        let encodedName = shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? shortcutName
        let successURL = "podcastanalyzer://x-callback-url/success"
        let errorURL = "podcastanalyzer://x-callback-url/error"
        let cancelURL = "podcastanalyzer://x-callback-url/cancel"

        var urlString: String
        if useClipboard {
            // Shortcut should use "Get Clipboard" action
            urlString = "shortcuts://x-callback-url/run-shortcut?name=\(encodedName)"
            urlString += "&x-success=\(successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? successURL)"
            urlString += "&x-error=\(errorURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? errorURL)"
            urlString += "&x-cancel=\(cancelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cancelURL)"
        } else {
            let encodedInput = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            urlString = "shortcuts://x-callback-url/run-shortcut?name=\(encodedName)&input=text&text=\(encodedInput)"
            urlString += "&x-success=\(successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? successURL)"
            urlString += "&x-error=\(errorURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? errorURL)"
            urlString += "&x-cancel=\(cancelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cancelURL)"
        }

        guard let url = URL(string: urlString) else {
            throw ShortcutsError.invalidURL
        }

        logger.info("Running shortcut via URL: \(self.shortcutName)")

        // Use withCheckedThrowingContinuation for async/await
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation

            // Set timeout
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.pendingContinuation != nil {
                    self.isProcessing = false
                    self.pendingContinuation?.resume(throwing: ShortcutsError.timeout)
                    self.pendingContinuation = nil
                }
            }

            // Open the shortcut URL
            #if os(iOS)
            UIApplication.shared.open(url) { success in
                if !success {
                    self.isProcessing = false
                    self.timeoutTask?.cancel()
                    self.pendingContinuation?.resume(throwing: ShortcutsError.failedToOpen)
                    self.pendingContinuation = nil
                }
            }
            #else
            // macOS fallback: Use NSWorkspace to open URLs
            let success = NSWorkspace.shared.open(url)
            if !success {
                self.isProcessing = false
                self.timeoutTask?.cancel()
                self.pendingContinuation?.resume(throwing: ShortcutsError.failedToOpen)
                self.pendingContinuation = nil
            }
            #endif
        }
    }

    // MARK: - Analyze Transcript

    /// Analyze transcript using Shortcuts
    func analyzeTranscript(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        timeout: TimeInterval? = nil
    ) async throws -> CloudAnalysisResult {
        let timeout = timeout ?? (AISettingsManager.shared.shortcutsTimeout * 1.5)
        let prompt = buildPrompt(
            transcript: transcript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType
        )

        let result = try await runShortcut(input: prompt, timeout: timeout)

        return CloudAnalysisResult(
            type: analysisType,
            content: result,
            parsedAnalysis: nil,
            provider: .applePCC,
            model: "Shortcuts",
            timestamp: Date()
        )
    }

    // MARK: - Build Prompts

    private func buildPrompt(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType
    ) -> String {
        let settings = AISettingsManager.shared
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(customLanguageName: settings.customAnalysisLanguageName)

        switch analysisType {
        case .analysis:
            return """
            Please provide one complete analysis of this podcast episode.

            Podcast: \(podcastTitle)
            Episode: \(episodeTitle)

            \(languageInstruction)

            Transcript:
            \(transcript)

            Provide:
            1. Executive Summary (2-3 paragraphs)
            2. Main Topics Discussed
            3. Key Takeaways
            4. Key Insights and Learnings
            5. Target Audience and engagement level
            6. People, organizations, products, locations, and resources mentioned
            7. Highlights and notable quotes
            8. Action items or actionable advice
            9. Controversial or entertaining moments if present
            10. Conclusion
            """
        }
    }

    // MARK: - Helpers

    func openShortcutsApp() {
        if let url = URL(string: "shortcuts://") {
            #if os(iOS)
            UIApplication.shared.open(url)
            #else
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    func createShortcutURL() -> URL? {
        // Deep link to create a new shortcut
        URL(string: "shortcuts://create-shortcut")
    }

    /// Check if Shortcuts app is available
    var isShortcutsAvailable: Bool {
        #if os(iOS)
        guard let url = URL(string: "shortcuts://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        // On macOS, Shortcuts is available on macOS 12+
        if #available(macOS 12.0, *) {
            return true
        }
        return false
        #endif
    }
}

// MARK: - Shortcuts Errors

enum ShortcutsError: LocalizedError {
    case shortcutNotFound(name: String)
    case failedToOpen
    case noResult
    case timeout
    case cancelled
    case invalidURL
    case shortcutFailed(String)

    var errorDescription: String? {
        switch self {
        case .shortcutNotFound(let name):
            return "Shortcut '\(name)' not found. Please create it in the Shortcuts app."
        case .failedToOpen:
            return "Failed to open Shortcuts app. Please make sure it's installed."
        case .noResult:
            return "No result received from the shortcut."
        case .timeout:
            return "Shortcut took too long to respond. Please try again."
        case .cancelled:
            return "Shortcut was cancelled."
        case .invalidURL:
            return "Invalid shortcut URL."
        case .shortcutFailed(let message):
            return "Shortcut failed: \(message)"
        }
    }
}

// Note: Notification.Name extensions are defined in PodcastAppIntents.swift
