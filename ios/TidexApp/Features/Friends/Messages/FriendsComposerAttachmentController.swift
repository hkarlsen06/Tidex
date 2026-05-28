import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FriendsComposerRecentPhoto: Identifiable {
  let id: String
  let thumbnail: UIImage
}

struct FriendsComposerRecentPhotoPage {
  let photos: [FriendsComposerRecentPhoto]
  let hasMore: Bool
  let nextOffset: Int
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
  func loadRecentPhotos(limit: Int, offset: Int, targetSize: CGSize) async
    -> FriendsComposerRecentPhotoPage
  func loadImageData(localIdentifier: String) async -> Data?
}

final class FriendsComposerRecentPhotoProvider: FriendsComposerRecentPhotoProviding {
  static let shared = FriendsComposerRecentPhotoProvider()

  private enum PhotoKitErrorCode {
    static let unknown = -1
    static let resourceUnavailable = 3164
  }

  private let imageManager = PHCachingImageManager()

  func authorizationState() -> FriendsComposerPhotoAuthorizationState {
    Self.authorizationState(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
  }

  func requestAuthorization() async -> FriendsComposerPhotoAuthorizationState {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return Self.authorizationState(from: status)
  }

  func loadRecentPhotos(limit: Int, offset: Int, targetSize: CGSize) async
    -> FriendsComposerRecentPhotoPage
  {
    await Task.detached(priority: .userInitiated) { [imageManager] in
      let options = PHFetchOptions()
      options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
      options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

      let assets = PHAsset.fetchAssets(with: options)
      guard assets.firstObject != nil else {
        return FriendsComposerRecentPhotoPage(photos: [], hasMore: false, nextOffset: 0)
      }

      var photos: [FriendsComposerRecentPhoto] = []
      let startIndex = min(max(offset, 0), assets.count)
      photos.reserveCapacity(limit)

      guard startIndex < assets.count else {
        return FriendsComposerRecentPhotoPage(
          photos: [],
          hasMore: false,
          nextOffset: startIndex
        )
      }

      let maxAssetsToInspect = max(limit * 4, limit)
      let endIndex = min(assets.count, startIndex + maxAssetsToInspect)

      var nextOffset = startIndex
      while nextOffset < endIndex, photos.count < limit {
        let index = nextOffset
        nextOffset += 1
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

      return FriendsComposerRecentPhotoPage(
        photos: photos,
        hasMore: nextOffset < assets.count,
        nextOffset: nextOffset
      )
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
      let lock = NSLock()
      var didResume = false
      var degradedFallbackImage: UIImage?

      func resumeOnce(returning image: UIImage?) {
        lock.lock()
        guard !didResume else {
          lock.unlock()
          return
        }
        didResume = true
        lock.unlock()

        continuation.resume(returning: image)
      }

      func storeDegradedFallbackIfNeeded(_ image: UIImage) {
        lock.lock()
        if !didResume, degradedFallbackImage == nil {
          degradedFallbackImage = image
        }
        lock.unlock()
      }

      func currentDegradedFallback() -> UIImage? {
        lock.lock()
        let image = degradedFallbackImage
        lock.unlock()
        return image
      }

      imageManager.requestImage(
        for: asset,
        targetSize: targetSize,
        contentMode: .aspectFit,
        options: requestOptions
      ) { image, info in
        let wasCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
        if wasCancelled {
          resumeOnce(returning: currentDegradedFallback())
          return
        }

        if let error = info?[PHImageErrorKey] as? Error {
          if !Self.shouldSuppressThumbnailErrorLog(error) {
            debugPrint("FriendsComposerRecentPhotoProvider thumbnail load failed:", error)
          }
          resumeOnce(returning: currentDegradedFallback())
          return
        }

        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false

        if let image {
          if isDegraded {
            storeDegradedFallbackIfNeeded(image)
            return
          }

          resumeOnce(returning: image)
          return
        }

        if !isDegraded {
          resumeOnce(returning: currentDegradedFallback())
        }
      }
    }
  }

  private static func shouldSuppressThumbnailErrorLog(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == PHPhotosErrorDomain else { return false }

    return nsError.code == PhotoKitErrorCode.unknown
      || nsError.code == PhotoKitErrorCode.resourceUnavailable
  }
}

@MainActor
final class FriendsComposerAttachmentController: ObservableObject {
  private enum Pagination {
    static let pageSize = 12
    static let loadMoreThreshold = 4
  }

  @Published var isDrawerOpen = false
  @Published var isShowingPhotoLibrary = false
  @Published var isShowingCamera = false
  @Published var isShowingShiftCalendar = false
  @Published private(set) var recentPhotosState: FriendsComposerRecentPhotosState = .idle
  @Published private(set) var recentPhotos: [FriendsComposerRecentPhoto] = []
  @Published private(set) var isLoadingMoreRecentPhotos = false
  @Published private(set) var isProcessingAttachment = false

  private let recentPhotoProvider: any FriendsComposerRecentPhotoProviding
  private let thumbnailDisplaySize = CGSize(width: 144, height: 192)
  private var hasMoreRecentPhotos = false
  private var nextRecentPhotoOffset = 0

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

  func loadMoreRecentPhotosIfNeeded(currentPhotoID: String) async {
    guard recentPhotosState == .loaded, hasMoreRecentPhotos, !isLoadingMoreRecentPhotos else {
      return
    }

    guard let currentIndex = recentPhotos.firstIndex(where: { $0.id == currentPhotoID }) else {
      return
    }

    let remainingPhotoCount = recentPhotos.count - currentIndex - 1
    guard remainingPhotoCount <= Pagination.loadMoreThreshold else { return }

    await loadNextRecentPhotosPage()
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

      nextRecentPhotoOffset = 0
      hasMoreRecentPhotos = false
      isLoadingMoreRecentPhotos = false
      recentPhotos = []
      recentPhotosState = .denied
      return
    }

    recentPhotosState = .loading
    isLoadingMoreRecentPhotos = false
    let page = await recentPhotoProvider.loadRecentPhotos(
      limit: Pagination.pageSize,
      offset: 0,
      targetSize: thumbnailTargetSize
    )
    recentPhotos = page.photos
    nextRecentPhotoOffset = page.nextOffset
    hasMoreRecentPhotos = page.hasMore
    recentPhotosState = page.photos.isEmpty ? .empty : .loaded
  }

  private func loadNextRecentPhotosPage() async {
    guard recentPhotosState == .loaded, hasMoreRecentPhotos, !isLoadingMoreRecentPhotos else {
      return
    }

    isLoadingMoreRecentPhotos = true

    let page = await recentPhotoProvider.loadRecentPhotos(
      limit: Pagination.pageSize,
      offset: nextRecentPhotoOffset,
      targetSize: thumbnailTargetSize
    )

    let existingIDs = Set(recentPhotos.map(\.id))
    let uniqueNewPhotos = page.photos.filter { !existingIDs.contains($0.id) }
    recentPhotos.append(contentsOf: uniqueNewPhotos)
    nextRecentPhotoOffset = page.nextOffset
    hasMoreRecentPhotos = page.hasMore && !page.photos.isEmpty
    isLoadingMoreRecentPhotos = false
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

  func completeAttachmentSelection(shouldCloseDrawer: Bool = true) {
    isShowingShiftCalendar = false
    if shouldCloseDrawer {
      closeDrawer()
    }
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
