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
  @Published var selectedRecipientID: String?
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
    recipients.first(where: { $0.id == selectedRecipientID })
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
      self.selectedRecipientID = nil
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

          ScrollView {
            LazyVStack(spacing: 10) {
              ForEach(viewModel.recipients) { recipient in
                ShareRecipientCard(
                  recipient: recipient,
                  isSelected: viewModel.selectedRecipientID == recipient.id
                )
                .onTapGesture {
                  withAnimation(.easeInOut(duration: 0.16)) {
                    if viewModel.selectedRecipientID == recipient.id {
                      viewModel.selectedRecipientID = nil
                    } else {
                      viewModel.selectedRecipientID = recipient.id
                    }
                  }
                }
              }
            }
            .padding(.bottom, 12)
          }
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

private struct ShareRecipientCard: View {
  let recipient: ShareRecipient
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      avatarView

      VStack(alignment: .leading, spacing: 4) {
        Text(recipient.displayName)
          .font(.body.weight(.medium))
          .foregroundStyle(.primary)

        if let statusText = recipient.statusText {
          Text(statusText)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          isSelected ? Color.accentColor.opacity(0.85) : Color(.separator).opacity(0.35),
          lineWidth: 1)
    )
  }

  @ViewBuilder
  private var avatarView: some View {
    if let avatarURL = recipient.avatarURL {
      AsyncImage(url: avatarURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
        default:
          initialsAvatar
        }
      }
      .frame(width: 48, height: 48)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    } else {
      initialsAvatar
        .frame(width: 48, height: 48)
    }
  }

  private var initialsAvatar: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color.accentColor.opacity(0.16))

      Text(initials(from: recipient.displayName))
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.accentColor)
    }
  }

  private func initials(from name: String) -> String {
    let components = name.split(separator: " ")
    if components.count >= 2 {
      return components[0].prefix(1).uppercased() + components[1].prefix(1).uppercased()
    }

    return String(name.prefix(2)).uppercased()
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
