import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

  private var didStartHandling = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    setUpLoadingUI()
  }

  // Brief "Opening Credexa…" placeholder shown while we extract the shared item
  // and hand off to the host app. A visible view also keeps iOS from treating
  // the extension as non-interactive during the switch.
  private func setUpLoadingUI() {
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.startAnimating()
    let label = UILabel()
    label.text = "Opening Credexa…"
    label.font = .systemFont(ofSize: 15, weight: .medium)
    label.textColor = .secondaryLabel

    let stack = UIStackView(arrangedSubviews: [spinner, label])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Wait until the window is up before opening the host app — the responder
    // chain (which we walk to reach UIApplication) isn't fully populated in
    // viewDidLoad. Guarded since viewDidAppear can fire more than once.
    guard !didStartHandling else { return }
    didStartHandling = true
    handleSharedContent()
  }

  private func handleSharedContent() {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      completeRequest()
      return
    }

    let group = DispatchGroup()
    var didHandle = false

    for item in items {
      guard let attachments = item.attachments, !didHandle else { break }
      for provider in attachments {

        if !didHandle && provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
          didHandle = true
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.image.identifier) { item, _ in
            defer { group.leave() }
            var imageData: Data?
            var mime = "image/jpeg"
            if let url = item as? URL {
              imageData = try? Data(contentsOf: url)
              if url.pathExtension.lowercased() == "png" { mime = "image/png" }
            } else if let img = item as? UIImage {
              imageData = img.jpegData(compressionQuality: 0.85)
            } else if let data = item as? Data {
              imageData = data
            }
            if let data = imageData {
              let defaults = UserDefaults(suiteName: "group.com.credexa.shared")
              defaults?.set("image",                      forKey: "sharedType")
              defaults?.set(data.base64EncodedString(),   forKey: "sharedImageBase64")
              defaults?.set(mime,                         forKey: "sharedMimeType")
              defaults?.synchronize()
            }
          }
          break
        }

        if !didHandle && provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          didHandle = true
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
            defer { group.leave() }
            guard let url = item as? URL else { return }
            let defaults = UserDefaults(suiteName: "group.com.credexa.shared")
            defaults?.set("text",              forKey: "sharedType")
            defaults?.set(url.absoluteString,  forKey: "sharedText")
            defaults?.synchronize()
          }
          break
        }

        if !didHandle && provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          didHandle = true
          group.enter()
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
            defer { group.leave() }
            guard let text = item as? String else { return }
            let defaults = UserDefaults(suiteName: "group.com.credexa.shared")
            defaults?.set("text", forKey: "sharedType")
            defaults?.set(text,   forKey: "sharedText")
            defaults?.synchronize()
          }
          break
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      self?.openMainApp()
    }
  }

  private func openMainApp() {
    guard let url = URL(string: "credexa://share") else {
      completeRequest()
      return
    }

    // NSExtensionContext.open() is only truly supported for Today widgets; from a
    // Share Extension it returns success=false and does nothing. The reliable path
    // is to walk the responder chain to the live UIApplication instance — which
    // DOES exist in the extension's own process — and call its modern open(_:).
    if openViaResponderChain(url) {
      // Let the app-switch begin before tearing the extension down; completing
      // the request too early can hand focus back to the host app and cancel it.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
        self?.completeRequest()
      }
      return
    }

    // Fallback so the extension never hangs if the chain walk finds no application.
    extensionContext?.open(url) { [weak self] _ in
      self?.completeRequest()
    }
  }

  /// Walks the responder chain to the live UIApplication and opens the host app
  /// via the modern (non-deprecated) open API. Returns true if the open was
  /// dispatched, false if no UIApplication was found in the chain.
  private func openViaResponderChain(_ url: URL) -> Bool {
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:], completionHandler: nil)
        return true
      }
      responder = current.next
    }
    return false
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
