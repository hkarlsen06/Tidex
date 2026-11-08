import ExyteChat
import ImageIO
import SwiftUI
import UIKit

struct FriendsChatImageAttachmentCard: View {
  let attachment: FriendMessageAttachment
  let isCurrentUser: Bool
  let groupContext: FriendsChatMessageGroupContext?
  let isHighlighted: Bool
  let displaySize: CGSize?
  let cornerRadius: CGFloat
  let placeholderSymbolSize: CGFloat
  // swiftlint:disable:next explicit_acl
  var onTap: (() -> Void)?

  @State private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isCurrentUser: Bool,
    groupContext: FriendsChatMessageGroupContext? = nil,
    isHighlighted: Bool = false,
    displaySize: CGSize? = nil,
    cornerRadius: CGFloat = CornerRadius.lg,
    placeholderSymbolSize: CGFloat = 22,
    onTap: (() -> Void)? = nil
  ) {
    self.attachment = attachment
    self.isCurrentUser = isCurrentUser
    self.groupContext = groupContext
    self.isHighlighted = isHighlighted
    self.displaySize = displaySize
    self.cornerRadius = cornerRadius
    self.placeholderSymbolSize = placeholderSymbolSize
    self.onTap = onTap
    let resolvedDisplaySize = displaySize ?? attachment.friendsChatImageFrameSize()
    let displayScale = max(UITraitCollection.current.displayScale, 1)
    let pixelSize = CGSize(
      width: resolvedDisplaySize.width * displayScale,
      height: resolvedDisplaySize.height * displayScale
    )
    let variant = FriendsChatImageLoader.Variant.display(pixelSize: pixelSize)
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath, variant: variant)
    let initialImage = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment)
    _loader = State(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage, variant: variant)
    )
  }

  var body: some View {
    ZStack {
      if let image = loader.image {
        loadedImage(image)
      } else if loader.didFail {
        placeholder {
          Image(systemName: "photo")
            .font(.system(size: placeholderSymbolSize, weight: .medium))
            .foregroundStyle(Color.tidexTextMuted)
            .accessibilityLabel(Text(.friendsChatPreviewImage))
        }
      } else {
        placeholder {
          loadingIndicator
        }
      }
    }
    .task(id: attachment.storagePath) {
      await loader.loadIfNeeded(attachment: attachment)
    }
  }

  private var imageFrameSize: CGSize {
    displaySize ?? attachment.friendsChatImageFrameSize()
  }

  @ViewBuilder
  private func loadedImage(_ image: UIImage) -> some View {
    if let onTap {
      imageContent(image)
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
    } else {
      imageContent(image)
    }
  }

  private func imageContent(_ image: UIImage) -> some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFill()
      .accessibilityLabel(Text(.friendsChatPreviewImage))
      .accessibilityAddTraits(.isImage)
      .frame(width: imageFrameSize.width, height: imageFrameSize.height)
      .clipShape(imageShape)
      .overlay {
        imageShape
          .strokeBorder(
            imageBorderColor,
            lineWidth: 1
          )
      }
      .overlay {
        if isHighlighted {
          imageShape
            .fill(Color.tidexBlue.opacity(0.14))
        }
      }
      .contentShape(imageShape)
  }

  private var imageShape: UnevenRoundedRectangle {
    if let groupContext {
      return FriendsChatMessageBubbleShapeResolver.shape(for: groupContext)
    }
    return FriendsChatMessageBubbleShapeResolver.uniformShape(cornerRadius: cornerRadius)
  }

  private var imageBorderColor: Color {
    if isHighlighted {
      return .tidexBlue
    }
    return isCurrentUser ? Color.white.opacity(0.2) : Color.tidexBorder.opacity(0.45)
  }

  private var loadingIndicator: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .tint(.tidexTextMuted)
      .controlSize(.regular)
      .scaleEffect(placeholderSymbolSize <= 14 ? 0.72 : 1)
  }

  @ViewBuilder
  private func placeholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    imageShape
      .fill(Color.tidexSurfacePrimary)
      .frame(width: imageFrameSize.width, height: imageFrameSize.height)
      .overlay {
        content()
      }
      .overlay {
        imageShape
          .strokeBorder(
            imageBorderColor,
            lineWidth: 1
          )
      }
  }
}

struct FriendsChatImageGalleryOverlay: View {
  let attachments: [FriendMessageAttachment]
  let initialAttachmentID: String
  let onDismiss: () -> Void
  let onSaveImage: (UIImage) async -> Bool

  @State private var selectedAttachmentID: String
  @State private var loadedImagesByAttachmentID: [String: UIImage] = [:]
  @State private var savedAttachmentIDs: Set<String> = []
  @State private var savingAttachmentID: String?
  @State private var selectedPageIsZoomed = false
  @GestureState private var dismissTranslationY: CGFloat = 0

  private let galleryDismissThreshold: CGFloat = 120

  init(
    attachments: [FriendMessageAttachment],
    initialAttachmentID: String,
    onDismiss: @escaping () -> Void,
    onSaveImage: @escaping (UIImage) async -> Bool
  ) {
    self.attachments = attachments
    self.initialAttachmentID = initialAttachmentID
    self.onDismiss = onDismiss
    self.onSaveImage = onSaveImage
    _selectedAttachmentID = State(initialValue: initialAttachmentID)
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      TabView(selection: $selectedAttachmentID) {
        ForEach(attachments) { attachment in
          FriendsChatImageGalleryPage(
            attachment: attachment,
            isSelected: attachment.id == selectedAttachmentID,
            onImageLoaded: { image in
              loadedImagesByAttachmentID[attachment.id] = image
            },
            onZoomStateChanged: { isZoomed in
              if attachment.id == selectedAttachmentID {
                selectedPageIsZoomed = isZoomed
              }
            }
          )
          .tag(attachment.id)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .offset(y: currentDismissOffsetY)

      VStack {
        topBar
          .padding(.horizontal, Spacing.mlg)
          .padding(.top, Spacing.mlg)
        Spacer()
        pageIndicator
          .padding(.bottom, Spacing.xl)
      }
    }
    .simultaneousGesture(verticalDismissGesture)
    .onChange(of: selectedAttachmentID) { _, _ in
      selectedPageIsZoomed = false
    }
    .statusBarHidden()
  }

  private var topBar: some View {
    HStack {
      if let selectedImage {
        Button {
          saveSelectedImage(selectedImage)
        } label: {
          Image(systemName: saveButtonIconName)
            .font(.system(size: 30))
            .foregroundStyle(Color.white.opacity(0.88))
            .frame(width: 44, height: 44)
            .background(
              Circle()
                .fill(Color.black.opacity(0.32))
            )
        }
        .buttonStyle(.plain)
        .disabled(savingAttachmentID == selectedAttachmentID)
        .accessibilityLabel(
          Text(saveButtonAccessibilityLabel)
        )
      }

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 30))
          .foregroundStyle(Color.white.opacity(0.88))
          .frame(width: 44, height: 44)
          .background(
            Circle()
              .fill(Color.black.opacity(0.32))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.commonDismiss))
    }
    .padding(.vertical, Spacing.xs)
  }

  @ViewBuilder
  private var pageIndicator: some View {
    if let selectedIndex, attachments.count > 1 {
      Text("\(selectedIndex + 1) / \(attachments.count)")
        .accessibilityLabel(
          Text(.friendsAccessibilityPosition(selectedIndex + 1, attachments.count))
        )
        .font(.tidexFootnoteMedium)
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
          Capsule(style: .continuous)
            .fill(Color.black.opacity(0.35))
        )
        .allowsHitTesting(false)
    }
  }

  private var selectedImage: UIImage? {
    loadedImagesByAttachmentID[selectedAttachmentID]
  }

  private var selectedImageIsSaved: Bool {
    savedAttachmentIDs.contains(selectedAttachmentID)
  }

  private var saveButtonIconName: String {
    selectedImageIsSaved ? "checkmark.circle.fill" : "arrow.down.circle.fill"
  }

  private var saveButtonAccessibilityLabel: String {
    if selectedImageIsSaved {
      return String(localized: .friendsChatImageSaved)
    }
    return String(localized: .friendsChatActionSaveImage)
  }

  private var selectedIndex: Int? {
    attachments.firstIndex(where: { $0.id == selectedAttachmentID })
  }

  private var currentDismissOffsetY: CGFloat {
    guard !selectedPageIsZoomed else { return 0 }
    return max(0, dismissTranslationY)
  }

  private var verticalDismissGesture: some Gesture {
    DragGesture(minimumDistance: 12)
      .updating($dismissTranslationY) { value, state, _ in
        guard !selectedPageIsZoomed else { return }

        let horizontal = abs(value.translation.width)
        let vertical = value.translation.height

        guard vertical > 0, vertical > horizontal else { return }
        state = vertical
      }
      .onEnded { value in
        guard !selectedPageIsZoomed else { return }

        let horizontal = abs(value.translation.width)
        let vertical = value.translation.height

        guard vertical > 0, vertical > horizontal else { return }

        if vertical >= galleryDismissThreshold {
          onDismiss()
        }
      }
  }

  private func saveSelectedImage(_ image: UIImage) {
    let attachmentID = selectedAttachmentID

    guard savingAttachmentID != attachmentID else {
      return
    }

    savingAttachmentID = attachmentID

    Task {
      let didSave = await onSaveImage(image)

      await MainActor.run {
        if didSave {
          withAnimation(.snappy(duration: 0.18)) {
            _ = savedAttachmentIDs.insert(attachmentID)
          }
        }

        if savingAttachmentID == attachmentID {
          savingAttachmentID = nil
        }
      }
    }
  }
}

struct FriendsChatImageGalleryUnavailableOverlay: View {
  let onDismiss: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 30))
          .foregroundStyle(Color.white.opacity(0.88))
          .frame(width: 44, height: 44)
          .background(
            Circle()
              .fill(Color.black.opacity(0.32))
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.commonDismiss))
      .padding(.top, Spacing.mlg)
      .padding(.horizontal, Spacing.mlg)
    }
    .task {
      await MainActor.run {
        onDismiss()
      }
    }
    .statusBarHidden()
  }
}

private struct FriendsChatImageGalleryPage: View {
  let attachment: FriendMessageAttachment
  let isSelected: Bool
  let onImageLoaded: (UIImage) -> Void
  let onZoomStateChanged: (Bool) -> Void

  @State private var loader: FriendsChatImageLoader

  init(
    attachment: FriendMessageAttachment,
    isSelected: Bool,
    onImageLoaded: @escaping (UIImage) -> Void,
    onZoomStateChanged: @escaping (Bool) -> Void
  ) {
    self.attachment = attachment
    self.isSelected = isSelected
    self.onImageLoaded = onImageLoaded
    self.onZoomStateChanged = onZoomStateChanged
    let cacheURL = FriendsChatImageLoader.cacheURL(for: attachment.storagePath)
    let initialImage = ImageCache.shared.get(for: cacheURL, policy: .messageAttachment)
    _loader = State(
      wrappedValue: FriendsChatImageLoader(initialImage: initialImage, variant: .original)
    )
  }

  var body: some View {
    ZStack {
      if let image = loader.image {
        FriendsChatZoomableImageView(
          image: image,
          isActive: isSelected,
          onZoomStateChanged: onZoomStateChanged
        )
        .accessibilityLabel(Text(.friendsChatPreviewImage))
        .accessibilityAddTraits(.isImage)
      } else if loader.isLoading {
        ProgressView()
          .tint(.white.opacity(0.8))
      } else {
        Image(systemName: "photo")
          .font(.system(size: 28, weight: .medium))
          .foregroundStyle(Color.white.opacity(0.6))
          .accessibilityLabel(Text(.friendsChatPreviewImage))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .task(id: attachment.id) {
      await loader.loadIfNeeded(attachment: attachment)
      if let image = loader.image {
        onImageLoaded(image)
      }
    }
    .onChange(of: loader.image) { _, newImage in
      guard let newImage else { return }
      onImageLoaded(newImage)
    }
    .onChange(of: isSelected) { _, newValue in
      if !newValue {
        onZoomStateChanged(false)
      }
    }
  }
}

private struct FriendsChatZoomableImageView: UIViewRepresentable {
  let image: UIImage
  let isActive: Bool
  let onZoomStateChanged: (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onZoomStateChanged: onZoomStateChanged)
  }

  func makeUIView(context: Context) -> UIScrollView {
    let scrollView = ZoomScrollView()
    scrollView.delegate = context.coordinator
    scrollView.backgroundColor = .clear
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.bouncesZoom = true
    scrollView.decelerationRate = .fast
    scrollView.minimumZoomScale = 1
    scrollView.maximumZoomScale = 4
    scrollView.panGestureRecognizer.isEnabled = false

    let imageView = context.coordinator.imageView
    imageView.image = image
    imageView.contentMode = .scaleToFill
    scrollView.addSubview(imageView)

    let doubleTapRecognizer = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleDoubleTap(_:))
    )
    doubleTapRecognizer.numberOfTapsRequired = 2
    scrollView.addGestureRecognizer(doubleTapRecognizer)
    scrollView.onLayout = { [weak coordinator = context.coordinator] scrollView in
      coordinator?.layoutIfNeeded(in: scrollView)
    }
    context.coordinator.configure(image: image, in: scrollView, forceReset: true)

    return scrollView
  }

  func updateUIView(_ scrollView: UIScrollView, context: Context) {
    context.coordinator.onZoomStateChanged = onZoomStateChanged
    context.coordinator.configure(image: image, in: scrollView, forceReset: !isActive)

    if !isActive, scrollView.zoomScale > scrollView.minimumZoomScale {
      context.coordinator.resetZoom(in: scrollView)
    }
  }

  private final class ZoomScrollView: UIScrollView {
    var onLayout: ((UIScrollView) -> Void)?

    override func layoutSubviews() {
      super.layoutSubviews()
      onLayout?(self)
    }
  }

  final class Coordinator: NSObject, UIScrollViewDelegate {
    let imageView = UIImageView()
    var onZoomStateChanged: (Bool) -> Void
    private let minimumZoomEpsilon: CGFloat = 0.01
    private let minimumZoomSnapThreshold: CGFloat = 0.06
    private var currentImageIdentifier: ObjectIdentifier?
    private var lastBoundsSize: CGSize = .zero
    private var fittedImageSize: CGSize = .zero
    private var reportedIsZoomed = false
    private var isResettingZoom = false
    private var pendingImage: UIImage?

    init(onZoomStateChanged: @escaping (Bool) -> Void) {
      self.onZoomStateChanged = onZoomStateChanged
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
      imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      let isZoomed = isZoomed(scrollView)
      scrollView.isScrollEnabled = isZoomed
      scrollView.panGestureRecognizer.isEnabled = isZoomed
      centerImage(in: scrollView)
      guard !isResettingZoom else { return }
      setZoomState(isZoomed)
    }

    func scrollViewDidEndZooming(
      _ scrollView: UIScrollView,
      with _: UIView?,
      atScale scale: CGFloat
    ) {
      if scale <= scrollView.minimumZoomScale + minimumZoomSnapThreshold {
        resetZoom(in: scrollView)
        return
      }

      let isZoomed = scale > scrollView.minimumZoomScale + minimumZoomEpsilon
      scrollView.isScrollEnabled = isZoomed
      scrollView.panGestureRecognizer.isEnabled = isZoomed
      centerImage(in: scrollView)
      setZoomState(isZoomed)
    }

    @objc
    func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
      guard let scrollView = recognizer.view as? UIScrollView else { return }

      if isZoomed(scrollView) {
        resetZoom(in: scrollView)
        return
      }

      let tapPoint = recognizer.location(in: imageView)
      let zoomScale = min(scrollView.maximumZoomScale, 2)
      let width = scrollView.bounds.size.width / zoomScale
      let height = scrollView.bounds.size.height / zoomScale
      let zoomRect = CGRect(
        x: tapPoint.x - (width / 2),
        y: tapPoint.y - (height / 2),
        width: width,
        height: height
      )
      scrollView.zoom(to: zoomRect, animated: true)
      scrollView.isScrollEnabled = true
      scrollView.panGestureRecognizer.isEnabled = true
      setZoomState(true)
    }

    func configure(image: UIImage, in scrollView: UIScrollView, forceReset: Bool) {
      pendingImage = image
      let imageIdentifier = ObjectIdentifier(image)
      let boundsSize = scrollView.bounds.size

      guard boundsSize.width > 0, boundsSize.height > 0 else {
        imageView.image = image
        return
      }

      let imageChanged = imageIdentifier != currentImageIdentifier
      let boundsChanged = boundsSize != lastBoundsSize

      guard imageChanged || boundsChanged || forceReset else {
        centerImage(in: scrollView)
        return
      }

      currentImageIdentifier = imageIdentifier
      lastBoundsSize = boundsSize
      imageView.image = image
      fittedImageSize = Self.fittedSize(for: image.size, in: boundsSize)

      if imageChanged || forceReset || !isZoomed(scrollView) {
        resetZoom(in: scrollView)
        return
      }

      imageView.frame = CGRect(origin: .zero, size: fittedImageSize)
      scrollView.contentSize = fittedImageSize
      centerImage(in: scrollView)
    }

    func layoutIfNeeded(in scrollView: UIScrollView) {
      guard let pendingImage else { return }
      configure(image: pendingImage, in: scrollView, forceReset: false)
    }

    func resetZoom(in scrollView: UIScrollView) {
      guard fittedImageSize.width > 0, fittedImageSize.height > 0 else { return }

      isResettingZoom = true
      defer { isResettingZoom = false }

      scrollView.contentInset = .zero
      scrollView.contentOffset = .zero
      scrollView.minimumZoomScale = 1
      scrollView.maximumZoomScale = 4
      scrollView.zoomScale = scrollView.minimumZoomScale
      imageView.transform = .identity
      imageView.frame = CGRect(origin: .zero, size: fittedImageSize)
      scrollView.contentSize = fittedImageSize
      centerImage(in: scrollView)
      scrollView.isScrollEnabled = false
      scrollView.panGestureRecognizer.isEnabled = false
      setZoomState(false)
    }

    private func centerImage(in scrollView: UIScrollView) {
      let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
      let verticalInset = max((scrollView.bounds.height - scrollView.contentSize.height) / 2, 0)
      imageView.center = CGPoint(
        x: scrollView.contentSize.width / 2 + horizontalInset,
        y: scrollView.contentSize.height / 2 + verticalInset
      )
    }

    private func isZoomed(_ scrollView: UIScrollView) -> Bool {
      scrollView.zoomScale > scrollView.minimumZoomScale + minimumZoomEpsilon
    }

    private func setZoomState(_ isZoomed: Bool) {
      guard reportedIsZoomed != isZoomed else { return }
      reportedIsZoomed = isZoomed
      onZoomStateChanged(isZoomed)
    }

    private static func fittedSize(for imageSize: CGSize, in boundsSize: CGSize) -> CGSize {
      guard imageSize.width > 0, imageSize.height > 0,
        boundsSize.width > 0, boundsSize.height > 0
      else {
        return boundsSize
      }

      let scale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
      return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
  }
}