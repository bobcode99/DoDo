//
//  TranscriptContextManagementView.swift
//  PodcastAnalyzer
//
//  Settings screen to manage each podcast's Transcription Context — a per-show
//  list of proper nouns / jargon (host & guest names, companies, terms) fed to
//  the SpeechAnalyzer as contextual strings so on-device transcription spells
//  them correctly. Stored on `PodcastInfoModel.transcriptionTerms` (survives
//  feed renames); separate from the AI "Show Format" hint.
//
//  Supports an LLM round-trip: copy a generated prompt (every shown show's
//  title / description / language), paste it into any model, then import the
//  JSON reply to fill in terms automatically.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TranscriptContextManagementView: View {
  // Query all rows: list rows only read the top-level `title` / `transcriptionTerms`
  // mirrors (no `podcastInfo` blob decode), and we need unsubscribed-but-has-terms
  // rows too. ponytail: partition in memory rather than add a denormalized
  // has-terms flag + a second query just to skip term-less cached rows.
  @Query(sort: \PodcastInfoModel.title) private var allPodcasts: [PodcastInfoModel]
  @Environment(\.modelContext) private var modelContext

  @State private var showingImporter = false
  @State private var copied = false
  @State private var importSummary: TranscriptContextIO.ImportSummary?
  @State private var importError: String?

  private var subscribed: [PodcastInfoModel] {
    allPodcasts.filter(\.isSubscribed)
  }

  /// Unsubscribed shows the user has set context for. Unsubscribe keeps the row
  /// (`isSubscribed = false`), so these terms would otherwise be unreachable.
  private var unsubscribedWithTerms: [PodcastInfoModel] {
    allPodcasts.filter { !$0.isSubscribed && !$0.transcriptionTerms.isEmpty }
  }

  /// Everything on screen — the set the LLM prompt is built from.
  private var displayed: [PodcastInfoModel] { subscribed + unsubscribedWithTerms }

  var body: some View {
    List {
      Section {
        Button(action: copyPrompt) {
          Label(copied ? "Copied!" : "Copy LLM Prompt",
                systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .disabled(displayed.isEmpty)

        Button(action: importFromClipboard) {
          Label("Paste JSON Reply", systemImage: "doc.on.clipboard")
        }

        Button {
          showingImporter = true
        } label: {
          Label("Import from File", systemImage: "square.and.arrow.down")
        }
      } footer: {
        Text("Copy the prompt, paste it into any LLM, then paste its JSON reply back here to fill in each show's terms automatically. \"Import from File\" reads a saved .json instead.")
      }

      Section {
        if subscribed.isEmpty {
          Text("No subscriptions yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(subscribed) { podcastRow($0) }
        }
      } header: {
        Text("Subscribed Podcasts")
      } footer: {
        Text("Add host and recurring guest names plus show-specific jargon. These terms bias on-device transcription so names come out spelled correctly.")
      }

      if !unsubscribedWithTerms.isEmpty {
        Section {
          ForEach(unsubscribedWithTerms) { podcastRow($0) }
        } header: {
          Text("Other Podcasts")
        } footer: {
          Text("Not subscribed, but you've set context for them. Still editable here so the terms aren't lost.")
        }
      }
    }
    .navigationTitle("Transcription Context")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .overlay {
      if displayed.isEmpty {
        ContentUnavailableView(
          "No Podcasts",
          systemImage: "character.book.closed",
          description: Text("Subscribe to a podcast to add transcription terms.")
        )
      }
    }
    .fileImporter(
      isPresented: $showingImporter,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
    .alert(
      "Import Complete",
      isPresented: Binding(get: { importSummary != nil }, set: { if !$0 { importSummary = nil } })
    ) {
      Button("OK", role: .cancel) { importSummary = nil }
    } message: {
      if let summary = importSummary { Text(summary.message) }
    }
    .alert(
      "Import Failed",
      isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    ) {
      Button("OK", role: .cancel) { importError = nil }
    } message: {
      if let error = importError { Text(error) }
    }
  }

  @ViewBuilder
  private func podcastRow(_ podcast: PodcastInfoModel) -> some View {
    NavigationLink {
      TranscriptContextEditorView(podcast: podcast)
    } label: {
      let count = podcast.transcriptionTerms.count
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(podcast.title).lineLimit(1)
          Text(count > 0 ? "^[\(count) term](inflect: true)" : "No terms set")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if count > 0 {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }
    }
  }

  private func copyPrompt() {
    PlatformClipboard.string = TranscriptContextIO.prompt(for: displayed)
    copied = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }

  private func importFromClipboard() {
    do {
      importSummary = try TranscriptContextIO.importTerms(
        jsonText: PlatformClipboard.string ?? "",
        into: allPodcasts,
        context: modelContext)
    } catch {
      importError = error.localizedDescription
    }
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      // User cancellation surfaces as NSUserCancelledError — not worth an alert.
      if (error as NSError).code != NSUserCancelledError {
        importError = error.localizedDescription
      }
    case .success(let urls):
      guard let url = urls.first else { return }
      do {
        importSummary = try TranscriptContextIO.importTerms(
          from: url, into: allPodcasts, context: modelContext)
      } catch {
        importError = error.localizedDescription
      }
    }
  }
}

// MARK: - Portable JSON + LLM prompt

/// One podcast's context in the portable JSON shape: the LLM prompt asks for it,
/// and the importer reads it back. `title` is matched to `PodcastInfoModel.title`.
private struct PortableContextDoc: Codable {
  struct Entry: Codable {
    let title: String
    let terms: [String]
  }
  let podcasts: [Entry]
}

/// Builds the copy-paste LLM prompt and applies the model's JSON reply.
enum TranscriptContextIO {
  /// Target term count quoted in the prompt. The importer caps higher (below).
  static let promptTermTarget = 10
  /// Hard cap on stored terms per show on import, matching the downstream
  /// `TranscriptService.buildContextualStrings` cap.
  static let maxStoredTerms = 100

  struct ImportSummary {
    let applied: Int
    let unmatched: [String]

    var message: String {
      var text = applied == 0
        ? "No matching shows were updated."
        : "Updated \(applied) show\(applied == 1 ? "" : "s")."
      if !unmatched.isEmpty {
        let shown = unmatched.prefix(8).joined(separator: ", ")
        text += "\n\nNo match for: \(shown)"
        if unmatched.count > 8 { text += " …" }
      }
      return text
    }
  }

  /// The prompt: every shown show's title, language, description, and existing
  /// terms, with a strict JSON output schema so the reply imports cleanly.
  static func prompt(for podcasts: [PodcastInfoModel]) -> String {
    var out = """
    You are building a transcription bias vocabulary for a podcast app. On-device \
    speech recognition often misspells proper nouns — host and guest names, company \
    and brand names, places, and recurring jargon.

    For EACH podcast below, return up to \(promptTermTarget) such context strings most \
    likely to be misrecognized. Prefer names and domain terms over common words. Write \
    them in the podcast's own language.

    Return ONLY valid JSON — no commentary, no code fences — matching exactly:
    {
      "podcasts": [
        { "title": "<the podcast title, copied verbatim>", "terms": ["term one", "term two"] }
      ]
    }

    Podcasts:
    """

    for (index, podcast) in podcasts.enumerated() {
      let info = podcast.podcastInfo
      let description = (info.podcastInfoDescription ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let existing = podcast.transcriptionTerms.isEmpty
        ? "none"
        : podcast.transcriptionTerms.joined(separator: ", ")
      out += """


      \(index + 1). Title: \(podcast.title)
         Language: \(info.language.isEmpty ? "(unknown)" : info.language)
         Description: \(description.isEmpty ? "(none)" : description)
         Existing terms: \(existing)
      """
    }
    return out
  }

  /// User-facing import failures, distinct so the alert can say what's actually wrong.
  enum ImportError: LocalizedError {
    case empty
    case notJSON
    case wrongSchema

    var errorDescription: String? {
      switch self {
      case .empty:
        return "Nothing to import — copy the LLM's JSON reply first."
      case .notJSON:
        return "That doesn't look like JSON. Paste the model's reply — it should contain a { … } object."
      case .wrongSchema:
        return "The JSON doesn't match the expected shape:\n{ \"podcasts\": [ { \"title\": \"…\", \"terms\": [\"…\"] } ] }"
      }
    }
  }

  /// Imports from a raw JSON / clipboard string. Tolerant of code fences or stray
  /// prose around the object (LLMs add them despite the prompt): the outermost
  /// `{ … }` is extracted before parsing. Distinguishes "not JSON" from "valid
  /// JSON, wrong schema" so the alert can guide the fix.
  @MainActor
  static func importTerms(
    jsonText: String,
    into podcasts: [PodcastInfoModel],
    context: ModelContext
  ) throws -> ImportSummary {
    let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ImportError.empty }
    guard let open = trimmed.firstIndex(of: "{"),
          let close = trimmed.lastIndex(of: "}"), open < close else {
      throw ImportError.notJSON
    }
    let data = Data(trimmed[open...close].utf8)
    guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
      throw ImportError.notJSON
    }
    let doc: PortableContextDoc
    do {
      doc = try JSONDecoder().decode(PortableContextDoc.self, from: data)
    } catch {
      throw ImportError.wrongSchema
    }
    return try apply(doc, into: podcasts, context: context)
  }

  /// Imports from a picked `.json` file (delegates to the string path).
  @MainActor
  static func importTerms(
    from url: URL,
    into podcasts: [PodcastInfoModel],
    context: ModelContext
  ) throws -> ImportSummary {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let data = try Data(contentsOf: url)
    guard let text = String(data: data, encoding: .utf8) else { throw ImportError.notJSON }
    return try importTerms(jsonText: text, into: podcasts, context: context)
  }

  /// Writes terms onto matching podcasts. Replaces a show's terms only when the
  /// entry has at least one non-empty term, so an import can never silently wipe
  /// an existing list. Returns counts for the result alert.
  @MainActor
  private static func apply(
    _ doc: PortableContextDoc,
    into podcasts: [PodcastInfoModel],
    context: ModelContext
  ) throws -> ImportSummary {
    func normalize(_ string: String) -> String {
      string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    var byTitle: [String: PodcastInfoModel] = [:]
    for podcast in podcasts { byTitle[normalize(podcast.title)] = podcast }

    var applied = 0
    var unmatched: [String] = []
    for entry in doc.podcasts {
      let cleaned = Array(
        entry.terms
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .prefix(maxStoredTerms)
      )
      guard !cleaned.isEmpty else { continue }  // never wipe on an empty list
      guard let model = byTitle[normalize(entry.title)] else {
        unmatched.append(entry.title)
        continue
      }
      if cleaned != model.transcriptionTerms {
        model.transcriptionTerms = cleaned
        applied += 1
      }
    }
    if applied > 0 { try context.save() }
    return ImportSummary(applied: applied, unmatched: unmatched)
  }
}

// MARK: - Per-podcast term editor

/// Edits one show's transcription vocabulary as a list of terms (one per row),
/// persisting to `PodcastInfoModel.transcriptionTerms` on disappear. Reused both
/// pushed (from the management list) and presented as a sheet (transcript screen).
struct TranscriptContextEditorView: View {
  @Bindable var podcast: PodcastInfoModel
  @Environment(\.modelContext) private var modelContext

  private struct TermEntry: Identifiable { let id = UUID(); var text: String }
  @State private var entries: [TermEntry] = []

  var body: some View {
    List {
      Section {
        ForEach($entries) { $entry in
          TextField("Name or term", text: $entry.text)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
        }
        .onDelete { entries.remove(atOffsets: $0) }

        Button {
          entries.append(TermEntry(text: ""))
        } label: {
          Label("Add term", systemImage: "plus.circle.fill")
        }
      } header: {
        Text(podcast.title)
      } footer: {
        Text("One name or term per row — e.g. host and guest names, companies, or jargon the recognizer tends to get wrong. Leave empty to remove this show's context.")
      }
    }
    .navigationTitle("Edit Terms")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear(perform: load)
    .onDisappear(perform: save)
  }

  private func load() {
    entries = podcast.transcriptionTerms.map { TermEntry(text: $0) }
    if entries.isEmpty { entries = [TermEntry(text: "")] }  // one empty starter row
  }

  private func save() {
    let cleaned = entries
      .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard cleaned != podcast.transcriptionTerms else { return }
    podcast.transcriptionTerms = cleaned
    try? modelContext.save()
  }
}
