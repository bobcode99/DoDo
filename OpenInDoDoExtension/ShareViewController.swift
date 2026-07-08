//
//  ShareViewController.swift
//  OpenInDoDoExtension
//
//  "Open in DoDo" share-sheet entry: receives a shared web URL (e.g. an Apple
//  Podcasts episode link), forwards it to the main app via the
//  podcastanalyzer:// scheme, and dismisses immediately. All parsing and
//  navigation happen in the app — this extension is a dumb pipe.
//

import UIKit
import UniformTypeIdentifiers

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
    guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
          let provider = item.attachments?.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
          }),
          let raw = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
    else { return }

    // Safari vends URL, some apps vend the URL's data representation.
    let shared = (raw as? URL)
      ?? (raw as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
    guard let shared,
          var components = URLComponents(string: "podcastanalyzer://open-shared-link")
    else { return }

    components.queryItems = [URLQueryItem(name: "url", value: shared.absoluteString)]
    guard let deepLink = components.url else { return }
    openContainerApp(deepLink)
  }

  /// UIApplication.shared is unavailable in extensions — walk the responder
  /// chain to the hosting UIApplication and ask it to open the URL.
  private func openContainerApp(_ url: URL) {
    let selector = NSSelectorFromString("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if current is UIApplication, current.responds(to: selector) {
        current.perform(selector, with: url)
        return
      }
      responder = current.next
    }
  }
}
