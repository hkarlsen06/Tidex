import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let viewModel = ShareExtensionViewModel()
  private var hostingController: UIHostingController<ShareRootView>?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    viewModel.configure(extensionContext: extensionContext)

    let hostingController = UIHostingController(rootView: ShareRootView(viewModel: viewModel))
    addChild(hostingController)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(hostingController.view)

    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    hostingController.didMove(toParent: self)
    self.hostingController = hostingController

    Task {
      await viewModel.load()
    }
  }
}

@MainActor
private final class ShareExtensionViewModel: ObservableObject {
  @Published var recipients: [ShareRecipient] = []
  @Published var recipientSelection = ShareRecipientSelectionState()
  @Published var messageText = ""
  @Published var previewImage: UIImage?
  @Published var isLoading = true
  @Published var isSending = false
  @Published var errorMessage: String?

  private weak var extensionContext: NSExtensionContext?
  private var sharedImageData: Data?

  var canSend: Bool {
    selectedRecipient != nil && sharedImageData != nil && !isLoading && !isSending
  }

  var selectedRecipient: ShareRecipient? {
    recipientSelection.selectedRecipient(in: recipients)
  }

  func configure(extensionContext: NSExtensionContext?) {
    self.extensionContext = extensionContext
  }

  func load() async {
    isLoading = true
    errorMessage = nil

    do {
      async let recipientsTask = ShareExtensionMessagingClient.fetchRecipients()
      async let imageTask = loadSharedImage()

      let (recipients, imagePayload) = try await (recipientsTask, imageTask)
      self.recipients = recipients
      recipientSelection = ShareRecipientSelectionState()
      self.previewImage = imagePayload.image
      self.sharedImageData = imagePayload.data

      if recipients.isEmpty {
        errorMessage = String(localized: "share.error.no_recipients")
      }
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  func send() async {
    guard let recipient = selectedRecipient, let sharedImageData else { return }

    isSending = true
    errorMessage = nil

    do {
      try await ShareExtensionMessagingClient.sendSharedImage(
        to: recipient.id,
        message: messageText,
        imageData: sharedImageData
      )

      extensionContext?.completeRequest(returningItems: nil)
    } catch {
      errorMessage = error.localizedDescription
      isSending = false
    }
  }

  func dismiss() {
    let error = NSError(domain: "TidexShareExtension", code: NSUserCancelledError)
    extensionContext?.cancelRequest(withError: error)
  }

  private func loadSharedImage() async throws -> (image: UIImage, data: Data) {
    guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
      throw ShareLoadingError.missingInputItems
    }

    for item in inputItems {
      for provider in item.attachments ?? [] {
        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
          continue
        }

        if let data = try await provider.loadImageData(),
          let image = UIImage(data: data)
        {
          return (image, data)
        }
      }
    }

    throw ShareLoadingError.noSupportedImage
  }

  private enum ShareLoadingError: LocalizedError {
    case missingInputItems
    case noSupportedImage

    var errorDescription: String? {
      switch self {
      case .missingInputItems:
        return String(localized: "share.error.missing_input")
      case .noSupportedImage:
        return String(localized: "share.error.no_supported_image")
      }
    }
  }
}

private struct ShareRootView: View {
  @ObservedObject var viewModel: ShareExtensionViewModel
  @FocusState private var isMessageFieldFocused: Bool

  var body: some View {
    ZStack {
      Color(.systemGroupedBackground)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        topBar

        if viewModel.isLoading {
          Spacer()
          ProgressView()
          Spacer()
        } else {
          composerRow

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.red)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          ShareRecipientPickerList(
            recipients: viewModel.recipients,
            selectionState: Binding(
              get: { viewModel.recipientSelection },
              set: { viewModel.recipientSelection = $0 }
            )
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 16)
      .padding(.bottom, 12)
    }
  }

  private var topBar: some View {
    HStack(spacing: 12) {
      Button(String(localized: "share.action.dismiss")) {
        viewModel.dismiss()
      }
      .font(.body)
      .buttonStyle(.plain)

      Spacer()

      Text(String(localized: "share.title"))
        .font(.headline.weight(.semibold))

      Spacer()

      if viewModel.isSending {
        ProgressView()
          .frame(width: 56, alignment: .trailing)
      } else {
        Button(String(localized: "share.action.send")) {
          Task {
            await viewModel.send()
          }
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.plain)
        .disabled(!viewModel.canSend)
        .foregroundStyle(viewModel.canSend ? Color.accentColor : Color.secondary)
        .frame(width: 56, alignment: .trailing)
      }
    }
  }

  private var composerRow: some View {
    HStack(alignment: .top, spacing: 12) {
      previewTile
      messageField
    }
    .padding(12)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private var previewTile: some View {
    Group {
      if let previewImage = viewModel.previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFit()
          .frame(width: 96, height: 128, alignment: .center)
          .background(Color(.secondarySystemBackground))
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color(.secondarySystemBackground))
          .frame(width: 96, height: 128)
      }
    }
  }

  private var messageField: some View {
    TextField(
      String(localized: "share.placeholder.message"), text: $viewModel.messageText, axis: .vertical
    )
    .textInputAutocapitalization(.sentences)
    .autocorrectionDisabled(false)
    .font(.body)
    .textFieldStyle(.plain)
    .lineLimit(3...6)
    .focused($isMessageFieldFocused)
    .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .onTapGesture {
      isMessageFieldFocused = true
    }
  }
}

extension NSItemProvider {
  fileprivate func loadImageData() async throws -> Data? {
    do {
      if let fileData = try await loadImageFileData() {
        return fileData
      }
    } catch {
      // Fall back to data representation for providers that do not vend file URLs.
    }

    return try await loadImageDataRepresentation()
  }

  private func loadImageFileData() async throws -> Data? {
    try await withCheckedThrowingContinuation { continuation in
      loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let url else {
          continuation.resume(returning: nil)
          return
        }

        do {
          let data = try Data(contentsOf: url)
          continuation.resume(returning: data)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func loadImageDataRepresentation() async throws -> Data? {
    try await withCheckedThrowingContinuation { continuation in
      loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        continuation.resume(returning: data)
      }
    }
  }
}
