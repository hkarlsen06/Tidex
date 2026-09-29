import SwiftUI
import UIKit

extension AddJobSheet {
  func colorSelectionRow(selectedColor: Binding<Color>) -> some View {
    WorkplaceColorCarousel(selectedHex: normalizedHex(from: selectedColor.wrappedValue)) { hex in
      selectedColor.wrappedValue = colorFromHex(hex)
    }
  }

  func normalizedHex(from color: Color) -> String? {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return nil
    }

    return String(
      format: "#%02X%02X%02X",
      Int(red * 255),
      Int(green * 255),
      Int(blue * 255)
    )
  }

  func colorFromHex(_ hex: String) -> Color {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
      value.removeFirst()
    }
    guard value.count == 6, let intValue = Int(value, radix: 16) else {
      return Color.tidexBlue
    }

    let red = Double((intValue >> 16) & 0xFF) / 255.0
    let green = Double((intValue >> 8) & 0xFF) / 255.0
    let blue = Double(intValue & 0xFF) / 255.0
    return Color(red: red, green: green, blue: blue)
  }
}
