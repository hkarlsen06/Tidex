import SwiftUI

/// Locale switcher for the login screen footer
struct LocaleSwitcherView: View {
    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 16) {
            ForEach(LocalizationManager.AppLocale.allCases, id: \.rawValue) { locale in
                Button(action: {
                    localization.setLocale(locale)
                }) {
                    Text(locale.displayName)
                        .font(.system(size: 14))
                        .foregroundColor(
                            localization.currentLocale == locale
                                ? .tidexTextPrimary
                                : .tidexTextMuted
                        )
                        .underline(localization.currentLocale == locale)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    LocaleSwitcherView()
        .environment(\.localization, LocalizationManager.shared)
        .padding()
        .background(Color.tidexDarkBackground)
}
