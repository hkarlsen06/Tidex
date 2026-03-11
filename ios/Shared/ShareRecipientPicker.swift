import SwiftUI

#if os(iOS)

  struct ShareRecipientSelectionState: Equatable {
    var selectedRecipientID: String?

    mutating func toggleSelection(recipientID: String) {
      if selectedRecipientID == recipientID {
        selectedRecipientID = nil
      } else {
        selectedRecipientID = recipientID
      }
    }

    func selectedRecipient(in recipients: [ShareRecipient]) -> ShareRecipient? {
      recipients.first(where: { $0.id == selectedRecipientID })
    }
  }

  struct ShareRecipientPickerList: View {
    let recipients: [ShareRecipient]
    @Binding var selectionState: ShareRecipientSelectionState

    var body: some View {
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(recipients) { recipient in
            ShareRecipientCard(
              recipient: recipient,
              isSelected: selectionState.selectedRecipientID == recipient.id
            )
            .onTapGesture {
              withAnimation(.easeInOut(duration: 0.16)) {
                selectionState.toggleSelection(recipientID: recipient.id)
              }
            }
          }
        }
        .padding(.bottom, 12)
      }
    }
  }

  struct ShareRecipientCard: View {
    let recipient: ShareRecipient
    let isSelected: Bool

    var body: some View {
      HStack(spacing: 12) {
        avatarView

        VStack(alignment: .leading, spacing: 4) {
          Text(recipient.displayName)
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)

          if let statusText = recipient.statusText {
            Text(statusText)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(.secondarySystemGroupedBackground))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(
            isSelected ? Color.accentColor.opacity(0.85) : Color(.separator).opacity(0.35),
            lineWidth: 1
          )
      )
    }

    @ViewBuilder
    private var avatarView: some View {
      if let avatarURL = recipient.avatarURL {
        AsyncImage(url: avatarURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
          default:
            initialsAvatar
          }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      } else {
        initialsAvatar
          .frame(width: 48, height: 48)
      }
    }

    private var initialsAvatar: some View {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color.accentColor.opacity(0.16))

        Text(initials(from: recipient.displayName))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Color.accentColor)
      }
    }

    private func initials(from name: String) -> String {
      let components = name.split(separator: " ")
      if components.count >= 2 {
        return components[0].prefix(1).uppercased() + components[1].prefix(1).uppercased()
      }

      return String(name.prefix(2)).uppercased()
    }
  }

#endif
