import Foundation

struct ImageAttachment: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  /// Compressed image data
  let data: Data  // swiftlint:disable:this explicit_acl
  /// MIME type of the image (e.g., "image/jpeg")
  let mediaType: String  // swiftlint:disable:this explicit_acl

  init(id: String = UUID().uuidString, data: Data, mediaType: String = "image/jpeg") {  // swiftlint:disable:this explicit_acl function_default_parameter_at_end line_length type_contents_order
    self.id = id
    self.data = data
    self.mediaType = mediaType
  }
}

extension Array where Element == ImageAttachment {  // swiftlint:disable:this file_types_order
  func uniquePayloads() -> [ImageAttachment] {  // swiftlint:disable:this explicit_acl
    reduce(into: []) { result, attachment in
      guard
        !result.contains(where: {
          $0.mediaType == attachment.mediaType && $0.data == attachment.data
        })
      else { return }  // swiftlint:disable:this conditional_returns_on_newline
      result.append(attachment)
    }
  }
}
