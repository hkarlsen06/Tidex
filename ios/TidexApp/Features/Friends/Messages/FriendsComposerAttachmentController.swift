import Observation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
@Observable
final class FriendsComposerAttachmentController {
  var isDrawerOpen = false
  var isShowingPhotoLibrary = false
  var isShowingCamera = false
  var isShowingShiftCalendar = false
  private(set) var isProcessingAttachment = false

  func toggleDrawer() {
    isDrawerOpen.toggle()
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

  func makeImageAttachment(from photoItem: PhotosPickerItem?) async -> ImageAttachment? {
    guard let photoItem else { return nil }
    return await processAttachment {
      guard let data = try? await photoItem.loadTransferable(type: Data.self) else { return nil }
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

  // swiftlint:disable:next type_contents_order
  private func processAttachment(_ loader: () async -> ImageAttachment?) async
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
}
