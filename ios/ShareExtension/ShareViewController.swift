import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
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
          provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, _ in
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
    // extensionContext.open is the correct way to launch the host app from a
    // Share Extension. The old UIResponder-chain trick never finds UIApplication
    // because extensions run in a separate sandboxed process.
    extensionContext?.open(url) { [weak self] _ in
      self?.completeRequest()
    }
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
