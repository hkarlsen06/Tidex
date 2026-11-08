import AppIntents
import SwiftUI

// MARK: - Share Options Sheet

/// Bottom sheet for selecting share options
struct ShareOptionsSheet: View {
  let earningsImage: UIImage?
  let hiddenEarningsImage: UIImage?

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.mlg) {
        // Title
        Text(.shiftsShareTitle)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
          .padding(.top, Spacing.md)

        VStack(spacing: Spacing.sm) {
          shareLinkRow(image: earningsImage, systemImage: "eye", label: .shiftsShareShowEarnings)
          shareLinkRow(
            image: hiddenEarningsImage, systemImage: "eye.slash", label: .shiftsShareHideEarnings)
        }
        .padding(.horizontal, Spacing.mlg)
      }
      .frame(maxWidth: .infinity)
    }
    .background(Color.tidexBackground)
  }

  @ViewBuilder
  private func shareLinkRow(
    image: UIImage?, systemImage: String, label: LocalizedStringResource
  ) -> some View {
    if let image, let pngData = image.pngData() {
      ShareLink(
        item: TransferablePNGImage(data: pngData),
        preview: SharePreview(Text(label), image: Image(uiImage: image))
      ) {
        HStack(spacing: Spacing.msm) {
          Image(systemName: systemImage)
            .font(.tidexTitle2)
            .foregroundStyle(Color.tidexTextSecondary)
            .frame(minWidth: 28)
            .accessibilityHidden(true)
          Text(label)
            .font(.tidexBodyMedium)
            .foregroundStyle(Color.tidexTextPrimary)
          Spacer()
        }
        .padding(.horizontal, Spacing.mlg)
        .padding(.vertical, 18)
        .background(
          RoundedRectangle(cornerRadius: CornerRadius.xl)
            .fill(Color.tidexSurfacePrimary)
        )
      }
      .buttonStyle(.plain)
    }
  }
}

struct ShareDestinationSheet: View {
  let title: LocalizedStringResource
  let onShareAsImage: () -> Void
  let onShareInChat: () -> Void

  init(
    title: LocalizedStringResource = .shiftsShareTitle,
    onShareAsImage: @escaping () -> Void,
    onShareInChat: @escaping () -> Void
  ) {
    self.title = title
    self.onShareAsImage = onShareAsImage
    self.onShareInChat = onShareInChat
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.mlg) {
        Text(title)
          .font(.tidexHeadline)
          .foregroundStyle(Color.tidexTextPrimary)
          .padding(.top, Spacing.md)

        VStack(spacing: Spacing.sm) {
          Button(action: onShareInChat) {
            HStack(spacing: Spacing.msm) {
              Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.tidexTitle2)
                .foregroundStyle(Color.tidexTextSecondary)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
              Text(.friendsChatSendToChat)
                .font(.tidexBodyMedium)
                .foregroundStyle(Color.tidexTextPrimary)
              Spacer()
            }
            .padding(.horizontal, Spacing.mlg)
            .padding(.vertical, 18)
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.tidexSurfacePrimary)
            )
          }
          .buttonStyle(.plain)

          Button(action: onShareAsImage) {
            HStack(spacing: Spacing.msm) {
              Image(systemName: "photo.on.rectangle")
                .font(.tidexTitle2)
                .foregroundStyle(Color.tidexTextSecondary)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
              Text(.shiftsShareAsImage)
                .font(.tidexBodyMedium)
                .foregroundStyle(Color.tidexTextPrimary)
              Spacer()
            }
            .padding(.horizontal, Spacing.mlg)
            .padding(.vertical, 18)
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.xl)
                .fill(Color.tidexSurfacePrimary)
            )
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.mlg)
      }
      .frame(maxWidth: .infinity)
    }
    .background(Color.tidexBackground)
  }
}