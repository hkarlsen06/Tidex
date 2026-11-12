import SwiftUI

struct StatsEmploymentInfoButton: View {
  let fullTimeHoursPerWeek: Double

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showPopover: Bool = false

  private var usesCompactPresentation: Bool {
    horizontalSizeClass == .compact
  }

  private var popoverBinding: Binding<Bool> {
    Binding(
      get: { showPopover && !usesCompactPresentation },
      set: { if !$0 { showPopover = false } }
    )
  }

  private var alertBinding: Binding<Bool> {
    Binding(
      get: { showPopover && usesCompactPresentation },
      set: { if !$0 { showPopover = false } }
    )
  }

  private var message: String {
    String(
      localized: .statsChartsEmploymentInfo(
        fullTimeHoursPerWeek.formatted(
          .number.precision(.fractionLength(2)).locale(Locale.appLocale))))
  }

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      Image(systemName: "info.circle")
        .font(.tidexBody)
        .foregroundStyle(Color.tidexTextMuted)
        // 44pt hit area that doesn't add height to the caption.
        .padding(Spacing.md)
        .contentShape(Rectangle())
        .padding(-Spacing.md)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(.statsAccessibilityEmploymentInfo))
    .popover(isPresented: popoverBinding) {
      Text(message)
        .font(.tidexSubheadline)
        .foregroundStyle(Color.tidexTextSecondary)
        .multilineTextAlignment(.leading)
        .lineLimit(nil)
        .minimumScaleFactor(1)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(maxWidth: 280)
    }
    .alert(Text(.statsChartsEmploymentTitle), isPresented: alertBinding) {
      Button(String(localized: .commonDone), role: .cancel) {}
    } message: {
      Text(message)
    }
  }
}
