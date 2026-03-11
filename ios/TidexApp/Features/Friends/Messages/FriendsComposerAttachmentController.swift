import Photos
import PhotosUI
import SwiftUI
import UIKit

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

      let requestOptions = PHImageRequestOptions()
      requestOptions.deliveryMode = .highQualityFormat
      requestOptions.resizeMode = .exact
      requestOptions.isNetworkAccessAllowed = true
      requestOptions.isSynchronous = true

      var photos: [FriendsComposerRecentPhoto] = []
      photos.reserveCapacity(min(limit, assets.count))

      assets.enumerateObjects { asset, _, stop in
        var thumbnail: UIImage?
        imageManager.requestImage(
          for: asset,
          targetSize: targetSize,
          contentMode: .aspectFill,
          options: requestOptions
        ) { image, _ in
          thumbnail = image
        }

        if let thumbnail {
          photos.append(FriendsComposerRecentPhoto(id: asset.localIdentifier, thumbnail: thumbnail))
        }

        if photos.count >= limit {
          stop.pointee = true
        }
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
}

@MainActor
final class FriendsComposerAttachmentController: ObservableObject {
  @Published var isDrawerOpen = false
  @Published var isShowingPhotoLibrary = false
  @Published var isShowingCamera = false
  @Published var isShowingShiftCalendar = false
  @Published private(set) var isPreparingDrawer = false
  @Published private(set) var recentPhotosState: FriendsComposerRecentPhotosState = .idle
  @Published private(set) var recentPhotos: [FriendsComposerRecentPhoto] = []
  @Published private(set) var isProcessingAttachment = false

  private let recentPhotoProvider: any FriendsComposerRecentPhotoProviding
  private let recentPhotoLimit = 18
  private let thumbnailDisplaySize = CGSize(width: 144, height: 192)

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
      guard !isPreparingDrawer else { return }
      let hasCachedRecentPhotos =
        recentPhotosState == .loaded || recentPhotosState == .empty
        || recentPhotosState == .failed
      guard hasCachedRecentPhotos else {
        isPreparingDrawer = true
        defer { isPreparingDrawer = false }
        await loadRecentPhotosIfNeeded()
        isDrawerOpen = true
        return
      }
      isDrawerOpen = true
    }
  }

  func closeDrawer() {
    isDrawerOpen = false
  }

  func openShiftCalendar() {
    isShowingShiftCalendar = true
  }

  func loadRecentPhotosIfNeeded(forceRefresh: Bool = false) async {
    let hasCachedRecentPhotos = recentPhotosState == .loaded || recentPhotosState == .empty
    if !forceRefresh, hasCachedRecentPhotos {
      return
    }

    recentPhotosState = .loading

    let authState = await resolvedAuthorizationState()
    guard authState == .authorized || authState == .limited else {
      recentPhotos = []
      recentPhotosState = .denied
      return
    }

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

  private func resolvedAuthorizationState() async -> FriendsComposerPhotoAuthorizationState {
    let currentStatus = recentPhotoProvider.authorizationState()
    guard currentStatus == .notDetermined else { return currentStatus }
    return await recentPhotoProvider.requestAuthorization()
  }

  private func processAttachment(_ loader: @escaping () async -> ImageAttachment?) async
    -> ImageAttachment?
  {
    guard !isProcessingAttachment else { return nil }
    isProcessingAttachment = true
    defer { isProcessingAttachment = false }
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
