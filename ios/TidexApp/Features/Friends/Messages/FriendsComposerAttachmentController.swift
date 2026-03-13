import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FriendsComposerRecentPhoto: Identifiable {
  let id: String
  let thumbnail: UIImage
}

enum FriendsComposerPhotoAuthorizationState: Equatable {
  case notDetermined
  case authorized
  case limited
  case denied
  case restricted
}

enum FriendsComposerRecentPhotosState: Equatable {
  case idle
  case loading
  case loaded
  case empty
  case denied
  case failed

  var canReuseWithoutReload: Bool {
    switch self {
    case .loaded, .empty:
      return true
    case .idle, .loading, .denied, .failed:
      return false
    }
  }
}

protocol FriendsComposerRecentPhotoProviding: AnyObject {
  func authorizationState() -> FriendsComposerPhotoAuthorizationState
  func requestAuthorization() async -> FriendsComposerPhotoAuthorizationState
  func loadRecentPhotos(limit: Int, targetSize: CGSize) async -> [FriendsComposerRecentPhoto]
  func loadImageData(localIdentifier: String) async -> Data?
}

final class FriendsComposerRecentPhotoProvider: FriendsComposerRecentPhotoProviding {
  static let shared = FriendsComposerRecentPhotoProvider()

  private let imageManager = PHCachingImageManager()

  func authorizationState() -> FriendsComposerPhotoAuthorizationState {
    Self.authorizationState(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  func requestAuthorization() async -> FriendsComposerPhotoAuthorizationState {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return Self.authorizationState(from: status)
  }

  func loadRecentPhotos(limit: Int, targetSize: CGSize) async -> [FriendsComposerRecentPhoto] {
    await Task.detached(priority: .userInitiated) { [imageManager] in
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.fetchLimit = limit
      options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

      let assets = PHAsset.fetchAssets(with: options)
      guard assets.firstObject != nil else { return [] }

      var photos: [FriendsComposerRecentPhoto] = []
      photos.reserveCapacity(min(limit, assets.count))

      let assetCount = min(limit, assets.count)
      for index in 0..<assetCount {
        let asset = assets.object(at: index)
        guard
          let thumbnail = await Self.loadThumbnail(
            for: asset,
            targetSize: targetSize,
            imageManager: imageManager
          )
        else {
          continue
        }

        photos.append(FriendsComposerRecentPhoto(id: asset.localIdentifier, thumbnail: thumbnail))
      }

      return photos
    }.value
  }

  func loadImageData(localIdentifier: String) async -> Data? {
    await Task.detached(priority: .userInitiated) { [imageManager] in
      let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
      guard let asset = fetchResult.firstObject else { return nil }

      let requestOptions = PHImageRequestOptions()
      requestOptions.deliveryMode = .highQualityFormat
      requestOptions.resizeMode = .none
      requestOptions.isNetworkAccessAllowed = true
      requestOptions.version = .current

      return await withCheckedContinuation { continuation in
        imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) {
          data, _, _, _ in
          continuation.resume(returning: data)
        }
      }
    }.value
  }

  private static func authorizationState(from status: PHAuthorizationStatus)
    -> FriendsComposerPhotoAuthorizationState
  {
    switch status {
    case .notDetermined:
      return .notDetermined
    case .authorized:
      return .authorized
    case .limited:
      return .limited
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    @unknown default:
      return .denied
    }
  }

  private static func loadThumbnail(
    for asset: PHAsset,
    targetSize: CGSize,
    imageManager: PHCachingImageManager
  ) async -> UIImage? {
    let requestOptions = PHImageRequestOptions()
    requestOptions.deliveryMode = .highQualityFormat
    requestOptions.resizeMode = .exact
    requestOptions.isNetworkAccessAllowed = false

    return await withCheckedContinuation { continuation in
      var didResume = false
      var degradedFallbackImage: UIImage?

      imageManager.requestImage(
        for: asset,
        targetSize: targetSize,
        contentMode: .aspectFit,
        options: requestOptions
      ) { image, info in
        guard !didResume else { return }

        let wasCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
        if wasCancelled {
          didResume = true
          continuation.resume(returning: degradedFallbackImage)
          return
        }

        if let error = info?[PHImageErrorKey] as? Error {
          debugPrint("FriendsComposerRecentPhotoProvider thumbnail load failed:", error)
          didResume = true
          continuation.resume(returning: degradedFallbackImage)
          return
        }

        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

        if let image {
          if isDegraded {
            degradedFallbackImage = degradedFallbackImage ?? image
            return
          }

          didResume = true
          continuation.resume(returning: image)
          return
        }

        if !isDegraded {
          didResume = true
          continuation.resume(returning: degradedFallbackImage)
        }
      }
    }
  }
}

@MainActor
final class FriendsComposerAttachmentController: ObservableObject {
  @Published var isDrawerOpen = false
  @Published var isShowingPhotoLibrary = false
  @Published var isShowingCamera = false
  @Published var isShowingShiftCalendar = false
  @Published private(set) var recentPhotosState: FriendsComposerRecentPhotosState = .idle
  @Published private(set) var recentPhotos: [FriendsComposerRecentPhoto] = []
  @Published private(set) var isProcessingAttachment = false

  private let recentPhotoProvider: any FriendsComposerRecentPhotoProviding
  private let recentPhotoLimit = 12
  private let thumbnailDisplaySize = CGSize(width: 280, height: 500)

  init(
    recentPhotoProvider: any FriendsComposerRecentPhotoProviding =
      FriendsComposerRecentPhotoProvider.shared
  ) {
    self.recentPhotoProvider = recentPhotoProvider
  }

  func toggleDrawer() async {
    if isDrawerOpen {
      closeDrawer()
    } else {
      isDrawerOpen = true

      guard !recentPhotosState.canReuseWithoutReload, recentPhotosState != .loading else {
        return
      }

      await loadRecentPhotosIfNeeded()
    }
  }

  func closeDrawer() {
    isDrawerOpen = false
  }

  func openShiftCalendar() {
    isShowingShiftCalendar = true
  }

  func beginProcessingAttachment() -> Bool {
    guard !isProcessingAttachment else { return false }
    isProcessingAttachment = true
    return true
  }

  func finishProcessingAttachment() {
    isProcessingAttachment = false
  }

  func loadRecentPhotosIfNeeded(forceRefresh: Bool = false) async {
    await loadRecentPhotosIfNeeded(
      forceRefresh: forceRefresh,
      requestAuthorizationIfNeeded: true
    )
  }

  func preloadRecentPhotosIfPossible() async {
    await loadRecentPhotosIfNeeded(forceRefresh: false, requestAuthorizationIfNeeded: false)
  }

  private func loadRecentPhotosIfNeeded(
    forceRefresh: Bool,
    requestAuthorizationIfNeeded: Bool
  ) async {
    if !forceRefresh, recentPhotosState.canReuseWithoutReload || recentPhotosState == .loading {
      return
    }

    let authState = await resolvedAuthorizationState(
      requestingIfNeeded: requestAuthorizationIfNeeded
    )
    guard authState == .authorized || authState == .limited else {
      if authState == .notDetermined, !requestAuthorizationIfNeeded {
        return
      }

      recentPhotos = []
      recentPhotosState = .denied
      return
    }

    recentPhotosState = .loading
    let photos = await recentPhotoProvider.loadRecentPhotos(
      limit: recentPhotoLimit,
      targetSize: thumbnailTargetSize
    )
    recentPhotos = photos
    recentPhotosState = photos.isEmpty ? .empty : .loaded
  }

  func makeImageAttachment(from photoItem: PhotosPickerItem?) async -> ImageAttachment? {
    guard let photoItem else { return nil }
    return await processAttachment {
      guard let data = try? await photoItem.loadTransferable(type: Data.self) else { return nil }
      return await Self.compressedImageAttachment(from: data)
    }
  }

  func makeImageAttachment(from pickerResult: PHPickerResult) async -> ImageAttachment? {
    await processAttachment {
      let itemProvider = pickerResult.itemProvider
      guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
        return nil
      }

      let data = await withCheckedContinuation { continuation in
        itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
          continuation.resume(returning: data)
        }
      }

      guard let data else { return nil }
      return await Self.compressedImageAttachment(from: data)
    }
  }

  func makeImageAttachment(from recentPhoto: FriendsComposerRecentPhoto) async -> ImageAttachment? {
    await processAttachment {
      guard let data = await self.recentPhotoProvider.loadImageData(localIdentifier: recentPhoto.id)
      else {
        return nil
      }
      return await Self.compressedImageAttachment(from: data)
    }
  }

  func makeImageAttachment(from capturedImage: UIImage) async -> ImageAttachment? {
    await processAttachment {
      await Task.detached(priority: .userInitiated) {
        guard let compressed = ImageCompressor.compress(capturedImage) else { return nil }
        return ImageAttachment(data: compressed.data, mediaType: compressed.mediaType)
      }.value
    }
  }

  func completeAttachmentSelection() {
    isShowingShiftCalendar = false
    closeDrawer()
  }

  private func resolvedAuthorizationState(requestingIfNeeded: Bool)
    async -> FriendsComposerPhotoAuthorizationState
  {
    let currentStatus = recentPhotoProvider.authorizationState()
    guard currentStatus == .notDetermined else { return currentStatus }
    guard requestingIfNeeded else { return currentStatus }
    return await recentPhotoProvider.requestAuthorization()
  }

  private func processAttachment(_ loader: @escaping () async -> ImageAttachment?) async
    -> ImageAttachment?
  {
    guard beginProcessingAttachment() else { return nil }
    defer { finishProcessingAttachment() }
    return await loader()
  }

  private static func compressedImageAttachment(from data: Data) async -> ImageAttachment? {
    await Task.detached(priority: .userInitiated) {
      guard let compressed = ImageCompressor.compress(data) else { return nil }
      return ImageAttachment(data: compressed.data, mediaType: compressed.mediaType)
    }.value
  }

  private var thumbnailTargetSize: CGSize {
    let scale = max(UITraitCollection.current.displayScale, 1)
    return CGSize(
      width: thumbnailDisplaySize.width * scale,
      height: thumbnailDisplaySize.height * scale
    )
  }
}
