import Foundation

enum WageyToolJSONFormatter {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  static func format(_ string: String) -> String {  // swiftlint:disable:this explicit_acl
    guard let data = string.data(using: .utf8),
      let jsonObject = try? JSONSerialization.jsonObject(with: data)
    else {
      return string
    }

    return render(jsonObject, level: 0)
  }

  private static func render(_ value: Any, level: Int) -> String {
    switch value {
    case let dictionary as [String: Any]:
      return renderDictionary(dictionary, level: level)

    case let array as [Any]:
      return renderArray(array, level: level)

    case let string as String:
      return quotedString(string)

    case let number as NSNumber:  // swiftlint:disable:this legacy_objc_type
      return renderNumber(number)

    case _ as NSNull:
      return "null"

    default:
      return quotedString(String(describing: value))
    }
  }

  private static func renderDictionary(_ dictionary: [String: Any], level: Int) -> String {
    guard !dictionary.isEmpty else { return "{}" }  // swiftlint:disable:this conditional_returns_on_newline

    let childIndent = indent(level + 1)  // swiftlint:disable:this explicit_type_interface
    let currentIndent = indent(level)  // swiftlint:disable:this explicit_type_interface
    let entries = dictionary.keys.sorted().map { key in  // swiftlint:disable:this explicit_type_interface
      "\(childIndent)\(quotedString(key)) : \(render(dictionary[key] as Any, level: level + 1))"
    }

    return "{\n\(entries.joined(separator: ",\n"))\n\(currentIndent)}"
  }

  private static func renderArray(_ array: [Any], level: Int) -> String {
    guard !array.isEmpty else { return "[]" }  // swiftlint:disable:this conditional_returns_on_newline

    let childIndent = indent(level + 1)  // swiftlint:disable:this explicit_type_interface
    let currentIndent = indent(level)  // swiftlint:disable:this explicit_type_interface
    let entries = array.map { value in  // swiftlint:disable:this explicit_type_interface
      "\(childIndent)\(render(value, level: level + 1))"
    }

    return "[\n\(entries.joined(separator: ",\n"))\n\(currentIndent)]"
  }

  private static func renderNumber(_ number: NSNumber) -> String {  // swiftlint:disable:this legacy_objc_type
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
      return number.boolValue ? "true" : "false"
    }

    let doubleValue = number.doubleValue  // swiftlint:disable:this explicit_type_interface
    guard doubleValue.isFinite else { return "null" }  // swiftlint:disable:this conditional_returns_on_newline

    let formatter = NumberFormatter()  // swiftlint:disable:this explicit_type_interface
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 6  // swiftlint:disable:this no_magic_numbers
    formatter.roundingMode = .halfUp

    return formatter.string(from: NSNumber(value: doubleValue)) ?? number.stringValue  // swiftlint:disable:this legacy_objc_type line_length
  }

  private static func quotedString(_ string: String) -> String {
    guard
      let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
      let encoded = String(data: data, encoding: .utf8),
      encoded.count >= 2  // swiftlint:disable:this no_magic_numbers
    else {
      return "\"\(string)\""
    }

    return String(encoded.dropFirst().dropLast())
  }

  private static func indent(_ level: Int) -> String {
    String(repeating: "  ", count: level)
  }
}
