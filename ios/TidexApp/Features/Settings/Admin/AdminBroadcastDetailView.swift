import SwiftUI

struct AdminBroadcastDetailView: View {
  let broadcast: AdminBroadcast

  @State private var detail: AdminBroadcastDetail?
  @State private var errorMessage: String?

  var body: some View {
    List {
      Group {
        summarySection
        if let detail {
          messageSection(
            .english, title: detail.title, body: detail.body, deeplink: detail.deeplink)
          messageSection(
            .norwegian, title: detail.titleNo, body: detail.bodyNo, deeplink: detail.deeplinkNo)
          deliverySection(detail.recipients)
        } else if errorMessage == nil {
          ProgressView().frame(maxWidth: .infinity)
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle("Broadcast")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .adminErrorAlert($errorMessage)
  }

  private var summarySection: some View {
    Section {
      LabeledContent("Status") {
        AdminBadge(
          broadcast.status.adminHumanized, color: adminBroadcastStatusColor(broadcast.status))
      }
      LabeledContent("Audience", value: broadcast.target.adminHumanized)
      LabeledContent("Recipients") { Text(broadcast.targetCount, format: .number) }
      if let created = broadcast.created {
        LabeledContent("Sent") {
          Text(created, format: .dateTime.day().month().year().hour().minute())
        }
      }
      if let adminEmail = detail?.adminEmail {
        LabeledContent("Sent by", value: adminEmail)
      }
    }
  }

  /// Broadcasts sent before the Norwegian text was stored only have the English section.
  @ViewBuilder
  private func messageSection(
    _ language: AdminLanguage, title: String?, body: String?, deeplink: String?
  ) -> some View {
    if let title, let body {
      Section(language.title) {
        Text(title).font(.tidexLabelStrong)
        Text(body).textSelection(.enabled)
        if let deeplink {
          LabeledContent("Deep link") {
            Text(deeplink).font(.tidexMonoCaptionRegular).textSelection(.enabled)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func deliverySection(_ recipients: [AdminBroadcastDetail.Recipient]) -> some View {
    if recipients.isEmpty {
      Section("Delivery") {
        Text("Delivery records are deleted 30 days after sending.")
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
      }
    } else {
      Section("Delivery") {
        ForEach(["sent", "failed", "skipped", "pending", "sending"], id: \.self) { status in
          let count: Int = recipients.count(where: { $0.status == status })
          if count > 0 {
            LabeledContent(status.adminHumanized) {
              Text(count, format: .number).foregroundStyle(adminBroadcastStatusColor(status))
            }
          }
        }
      }
      Section("Recipients") {
        ForEach(recipients) { AdminBroadcastRecipientRow(recipient: $0) }
      }
    }
  }

  private func load() async {
    do {
      detail = try await AdminAPI.broadcastDetail(id: broadcast.id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct AdminBroadcastRecipientRow: View {
  let recipient: AdminBroadcastDetail.Recipient

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(alignment: .firstTextBaseline) {
        Text(recipient.displayName)
          .font(.tidexLabel)
          .foregroundStyle(Color.tidexTextPrimary)
          .lineLimit(1)
        Spacer()
        AdminBadge(
          recipient.status.adminHumanized, color: adminBroadcastStatusColor(recipient.status))
      }
      if let error = recipient.errorMessage?.nilIfBlank {
        Text(error)
          .font(.tidexCaptionRegular)
          .foregroundStyle(Color.tidexError)
          .textSelection(.enabled)
      }
      HStack(spacing: Spacing.xxs) {
        Text(recipient.title).lineLimit(1)
        Spacer()
        if recipient.attempts > 1 {
          Text("\(recipient.attempts) attempts")
        }
        AdminRelativeDate(date: recipient.processed)
      }
      .font(.tidexMicro)
      .foregroundStyle(Color.tidexTextMuted)
    }
    .padding(.vertical, Spacing.micro)
  }
}
