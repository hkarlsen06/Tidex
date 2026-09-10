import CoreGraphics
import Foundation

// Expand the approved SVG's filled, stroked contour into a vector outline.
// Browser SVG masks can rasterize poorly when nested inside a small wordmark.
struct Contour: Decodable {
  let tokens: [String]
  let strokeWidth: CGFloat
  let transform: [CGFloat]
}
enum ContourError: Error {
  case invalidPoint(Int)
  case invalidTransform
  case transformFailed
}
let input = try JSONDecoder().decode(
  Contour.self, from: FileHandle.standardInput.readDataToEndOfFile())
let path = CGMutablePath()
var index = 0
func point() throws -> CGPoint {
  guard index + 1 < input.tokens.count,
    let x = Double(input.tokens[index]), x.isFinite,
    let y = Double(input.tokens[index + 1]), y.isFinite
  else {
    throw ContourError.invalidPoint(index)
  }
  index += 2
  return CGPoint(x: x, y: y)
}
while index < input.tokens.count {
  let command = input.tokens[index]
  index += 1
  switch command {
  case "M": path.move(to: try point())
  case "L": path.addLine(to: try point())
  case "C":
    let first = try point()
    let second = try point()
    let end = try point()
    path.addCurve(to: end, control1: first, control2: second)
  case "Z": path.closeSubpath()
  default: fatalError("Unsupported cutout path command: \(command)")
  }
}
let stroke = path.copy(
  strokingWithWidth: input.strokeWidth, lineCap: .butt, lineJoin: .round, miterLimit: 4)
let components = input.transform
guard components.count == 6, components.allSatisfy(\.isFinite) else {
  throw ContourError.invalidTransform
}
var transform = CGAffineTransform(
  a: components[0], b: components[1], c: components[2], d: components[3],
  tx: components[4], ty: components[5])
guard let outline = path.union(stroke).copy(using: &transform) else {
  throw ContourError.transformFailed
}
func number(_ value: CGFloat) -> String {
  String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
}
func coordinates(_ point: CGPoint) -> String { "\(number(point.x)) \(number(point.y))" }
var commands: [String] = []
outline.applyWithBlock { element in
  let pathElement = element.pointee
  switch pathElement.type {
  case .moveToPoint: commands.append("M \(coordinates(pathElement.points[0]))")
  case .addLineToPoint: commands.append("L \(coordinates(pathElement.points[0]))")
  case .addQuadCurveToPoint:
    commands.append("Q \(coordinates(pathElement.points[0])) \(coordinates(pathElement.points[1]))")
  case .addCurveToPoint:
    let first = coordinates(pathElement.points[0])
    let second = coordinates(pathElement.points[1])
    let end = coordinates(pathElement.points[2])
    commands.append("C \(first) \(second) \(end)")
  case .closeSubpath: commands.append("Z")
  @unknown default: fatalError("Unsupported outline element")
  }
}
try FileHandle.standardOutput.write(contentsOf: Data((commands.joined(separator: " ") + "\n").utf8))
