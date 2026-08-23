//
//  AccentContrastGuardTests.swift
//  PodcastAnalyzerTests
//
//  A source guard, not a behaviour test.
//
//  Painting a surface with the accent and then hardcoding `.foregroundStyle(.white)`
//  is invisible in exactly one configuration — the shipped monochrome accent in
//  dark mode — so it survives review and every light-mode screenshot. The fix is
//  `.accentFilled(in:)`, which derives the label from the fill. This fails if a
//  new one appears.
//

import Foundation
import Testing

@Suite("Accent contrast guard")
struct AccentContrastGuardTests {

    /// Walk up from this file to the repo, so the test doesn't care where it runs.
    private var viewsDirectory: URL? {
        var dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PodcastAnalyzerTests
            .deletingLastPathComponent()   // repo root
        dir.append(path: "PodcastAnalyzer/Views")
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    @Test("No view fills with the accent and then hardcodes a white label")
    func noWhiteOnAccent() throws {
        let root = try #require(viewsDirectory, "couldn't locate PodcastAnalyzer/Views")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty, "found no sources to scan — the guard would pass vacuously")

        var offenders: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                // An opaque accent fill. `.tint.opacity(…)` is a wash behind
                // ordinary text and is fine, so it is deliberately excluded.
                let fillsWithAccent =
                    (line.contains("background(.tint,") || line.contains("fill(.tint)")
                     || line.contains("AnyShapeStyle(.tint)"))
                    && !line.contains(".tint.opacity")
                guard fillsWithAccent else { continue }

                // Look for a hardcoded white label in the same view's block.
                let window = lines[max(0, index - 6)...min(lines.count - 1, index + 6)]
                if window.contains(where: {
                    $0.contains("foregroundStyle(.white)") || $0.contains("foregroundColor(.white)")
                }) {
                    let name = file.lastPathComponent
                    offenders.append("\(name):\(index + 1)")
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "accent-filled surfaces with a hardcoded white label — use .accentFilled(in:): \(offenders)"
        )
    }
}
