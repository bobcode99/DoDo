//
//  ShareViewController.swift
//  OpenInDoDoExtension
//
//  "Open in DoDo" share-sheet entry: receives a shared web URL (e.g. an Apple
//  Podcasts episode link), forwards it to the main app via the
//  podcastanalyzer:// scheme, and dismisses immediately. All parsing and
//  navigation happen in the app — this extension is a dumb pipe.
//

import OSLog
import UIKit
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.jn.PodcastAnalyzer.OpenInDoDo", category: "Share")

final class ShareViewController: UIViewController {

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task {
      await forwardSharedURL()
      extensionContext?.completeRequest(returningItems: nil)
    }
  }

  private func forwardSharedURL() async {
    // Safari shares only the link. Apps such as Podcasts add a title and
    // artwork beside it, or send the link inside text — the activation rule
    // admits all of those, so look across every attachment.
    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    logger.info("Shared types: \(providers.map(\.registeredTypeIdentifiers), privacy: .public)")

    guard let shared = await sharedLink(in: providers),
          var components = URLComponents(string: "podcastanalyzer://open-shared-link")
    else { return }

    components.queryItems = [URLQueryItem(name: "url", value: shared.absoluteString)]
    guard let deepLink = components.url else { return }
    openContainerApp(deepLink)
  }

  /// A URL attachment if there is one, else the first link found in shared text.
  private func sharedLink(in providers: [NSItemProvider]) async -> URL? {
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
       let raw = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
    {
      // Safari vends URL, some apps vend the URL's data representation.
      if let url = (raw as? URL) ?? (raw as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) {
        return url
      }
    }
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      guard let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
            let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
      else { continue }
      return match.url
    }
    return nil
  }

  /// UIApplication.shared is unavailable in extensions — walk the responder
  /// chain to the hosting UIApplication and ask it to open the URL.
  ///
  /// Must be `openURL:options:completionHandler:`. The one-argument `openURL:`
  /// is refused outright since iOS 18 ("Force returning false (NO)"), which
  /// left this extension dismissing without ever opening the app. Three
  /// arguments rule out `perform(_:with:)`, so the method is called through
  /// its implementation pointer.
  private func openContainerApp(_ url: URL) {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var responder: UIResponder? = self
    while let current = responder {
      if current is UIApplication, let method = class_getInstanceMethod(type(of: current), selector) {
        typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        unsafeBitCast(method_getImplementation(method), to: Open.self)(current, selector, url as NSURL, [:], nil)
        return
      }
      responder = current.next
    }
  }
}
