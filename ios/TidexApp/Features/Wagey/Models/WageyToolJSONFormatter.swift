import Foundation

enum WageyToolJSONFormatter {
  static func format(_ string: String) -> String {
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
    case let number as NSNumber:
      return renderNumber(number)
    case _ as NSNull:
      return "null"
    default:
      return quotedString(String(describing: value))
    }
  }

  private static func renderDictionary(_ dictionary: [String: Any], level: Int) -> String {
    guard !dictionary.isEmpty else { return "{}" }

    let childIndent = indent(level + 1)
    let currentIndent = indent(level)
    let entries = dictionary.keys.sorted().map { key in
      "\(childIndent)\(quotedString(key)) : \(render(dictionary[key] as Any, level: level + 1))"
    }

    return "{\n\(entries.joined(separator: ",\n"))\n\(currentIndent)}"
  }

  private static func renderArray(_ array: [Any], level: Int) -> String {
    guard !array.isEmpty else { return "[]" }

    let childIndent = indent(level + 1)
    let currentIndent = indent(level)
    let entries = array.map { value in
      "\(childIndent)\(render(value, level: level + 1))"
    }

    return "[\n\(entries.joined(separator: ",\n"))\n\(currentIndent)]"
  }

  private static func renderNumber(_ number: NSNumber) -> String {
    if CFGetTypeID(number) == CFBooleanGetTypeID() {
      return number.boolValue ? "true" : "false"
    }

    let doubleValue = number.doubleValue
    guard doubleValue.isFinite else { return "null" }

    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 6
    formatter.roundingMode = .halfUp

    return formatter.string(from: NSNumber(value: doubleValue)) ?? number.stringValue
  }

  private static func quotedString(_ string: String) -> String {
    guard
      let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
      let encoded = String(data: data, encoding: .utf8),
      encoded.count >= 2
    else {
      return "\"\(string)\""
    }

    return String(encoded.dropFirst().dropLast())
  }

  private static func indent(_ level: Int) -> String {
    String(repeating: "  ", count: level)
  }
}
