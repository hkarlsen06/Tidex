// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_trait_for_button
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline explicit_acl explicit_top_level_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_type_interface file_types_order no_magic_numbers required_deinit
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable strict_fileprivate type_contents_order
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let viewModel = ShareExtensionViewModel()
  private var hostingController: UIHostingController<ShareRootView>?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(SharedPalette.background)

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
@Observable
private final class ShareExtensionViewModel {
  var recipients: [ShareRecipient] = []
  var recipientSelection = ShareRecipientSelectionState()
  var messageText = ""
  var previewImage: UIImage?
  var isLoading = true
  var isSending = false
  var errorMessage: String?

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
        errorMessage = String(localized: .shareErrorNoRecipients)
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
        return String(localized: .shareErrorMissingInput)

      case .noSupportedImage:
        return String(localized: .shareErrorNoSupportedImage)
      }
    }
  }
}

private struct ShareRootView: View {
  @Bindable var viewModel: ShareExtensionViewModel
  @FocusState private var isMessageFieldFocused: Bool
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ZStack {
      SharedPalette.background
        .ignoresSafeArea()

      VStack(spacing: 18) {
        topBar

        if viewModel.isLoading {
          Spacer()
          ProgressView()
            .accessibilityLabel(Text(.shareAccessibilityLoading))
          Spacer()
        } else {
          composerRow

          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(SharedPalette.error)
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
    // A failed send would otherwise show its error only to people who can see the screen.
    .onChange(of: viewModel.errorMessage) { _, newMessage in
      if let newMessage {
        AccessibilityNotification.Announcement(newMessage).post()
      }
    }
  }

  /// At accessibility text sizes the buttons and title stack, so "Send" is never cut off.
  private var topBarLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(spacing: 12))
  }

  private var topBar: some View {
    topBarLayout {
      Button(String(localized: .shareActionDismiss)) {
        viewModel.dismiss()
      }
      .font(.body)
      .buttonStyle(.plain)

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer()
      }

      Text(.shareTitle)
        .font(.headline.weight(.semibold))
        .accessibilityAddTraits(.isHeader)

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer()
      }

      if viewModel.isSending {
        ProgressView()
          .accessibilityLabel(Text(.shareAccessibilitySending))
          .frame(minWidth: 56, alignment: .trailing)
      } else {
        Button(String(localized: .shareActionSend)) {
          Task {
            await viewModel.send()
          }
        }
        .font(.body.weight(.semibold))
        .buttonStyle(.plain)
        .disabled(!viewModel.canSend)
        .foregroundStyle(viewModel.canSend ? SharedPalette.blueText : SharedPalette.textSecondary)
        .frame(minWidth: 56, alignment: .trailing)
      }
    }
  }

  private var composerLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
  }

  private var composerRow: some View {
    composerLayout {
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
          .background(SharedPalette.surfaceSecondary)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .accessibilityLabel(Text(.shareAccessibilityPreview))
      } else {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(SharedPalette.surfaceSecondary)
          .frame(width: 96, height: 128)
          .accessibilityHidden(true)
      }
    }
  }

  private var messageField: some View {
    TextField(
      String(localized: .sharePlaceholderMessage), text: $viewModel.messageText, axis: .vertical
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
        .fill(SharedPalette.surfacePrimary)
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
