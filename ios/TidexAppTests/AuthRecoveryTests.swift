import Supabase
import XCTest

@testable import Tidex

internal final class AuthRecoveryTests: XCTestCase {
  // MARK: - Attachment upload errors

  internal func testDuplicateAttachmentUploadIsTreatedAsUploaded() {
    let duplicate = StorageError(
      statusCode: "409",
      message: "The resource already exists",
      error: "Duplicate"
    )

    XCTAssertNil(FriendsMessagingService.attachmentUploadFailure(duplicate))
  }
}
