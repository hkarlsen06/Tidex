import Foundation

/// Any JSON value. It has the cases and helpers of the Supabase type the app used before
/// N+1, so payload and diagnostics code kept its shape when Supabase went away.
enum AnyJSON: Codable, Hashable, Sendable {
  case null
  case bool(Bool)
  case integer(Int)
  case double(Double)
  case string(String)
  case object([String: AnyJSON])
  case array([AnyJSON])

  static let decoder = JSONDecoder()
  static let encoder = JSONEncoder()

  /// Encodes `value` and reads it back as JSON.
  init(_ value: some Encodable) throws {
    if let json = value as? AnyJSON {
      self = json
      return
    }
    self = try Self.decoder.decode(AnyJSON.self, from: Self.encoder.encode(value))
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([AnyJSON].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: AnyJSON].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    }
  }

  /// Decodes this value as `T`.
  func decode<T: Decodable>(as _: T.Type = T.self) throws -> T {
    try Self.decoder.decode(T.self, from: Self.encoder.encode(self))
  }

  /// The value as Foundation types: `NSNull`, `Bool`, `Int`, `Double`, `String`,
  /// `[String: Any]` or `[Any]`.
  var value: Any {
    switch self {
    case .null: NSNull()
    case .bool(let value): value
    case .integer(let value): value
    case .double(let value): value
    case .string(let value): value
    case .object(let value): value.mapValues(\.value)
    case .array(let value): value.map(\.value)
    }
  }

  var isNil: Bool { self == .null }

  var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  /// Whole doubles count too, since Convex sends every number as a double.
  var intValue: Int? {
    switch self {
    case .integer(let value): value
    case .double(let value): Int(exactly: value)
    default: nil
    }
  }

  var doubleValue: Double? {
    switch self {
    case .integer(let value): Double(value)
    case .double(let value): value
    default: nil
    }
  }

  var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var objectValue: [String: AnyJSON]? {
    if case .object(let value) = self { return value }
    return nil
  }

  var arrayValue: [AnyJSON]? {
    if case .array(let value) = self { return value }
    return nil
  }
}

extension AnyJSON: CustomStringConvertible {
  /// The value as JSON text.
  var description: String {
    guard let data = try? Self.encoder.encode(self) else { return "" }
    return String(decoding: data, as: UTF8.self)
  }
}

typealias JSONObject = [String: AnyJSON]

extension AnyJSON: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByStringLiteral,
  ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
  init(nilLiteral _: ()) { self = .null }
  init(booleanLiteral value: Bool) { self = .bool(value) }
  init(integerLiteral value: Int) { self = .integer(value) }
  init(floatLiteral value: Double) { self = .double(value) }
  init(stringLiteral value: String) { self = .string(value) }
  init(arrayLiteral elements: AnyJSON...) { self = .array(elements) }
  init(dictionaryLiteral elements: (String, AnyJSON)...) {
    self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
  }
}
