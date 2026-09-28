import SwiftUI

struct AdminFeedbackView: View {
  private enum Filter: String, CaseIterable, Identifiable {
    case unanswered = "Unanswered"
    case answered = "Answered"
    case all = "All"

    var id: String { rawValue }
  }

  @State private var items: [AdminFeedback]?
  @State private var filter: Filter = .unanswered
  @State private var errorMessage: String?

  private var visibleItems: [AdminFeedback] {
    (items ?? []).filter { item in
      switch filter {
      case .unanswered: return !item.isAnswered
      case .answered: return item.isAnswered
      case .all: return true
      }
    }
  }

  var body: some View {
    List {
      Section {
        Picker("Show", selection: $filter) {
          ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section {
        ForEach(visibleItems) { item in
          NavigationLink {
            AdminFeedbackDetailView(item: item) { await load() }
          } label: {
            AdminFeedbackRow(item: item)
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .overlay {
      if items == nil {
        ProgressView()
      } else if visibleItems.isEmpty {
        ContentUnavailableView(
          filter == .unanswered ? "All caught up" : "No feedback",
          systemImage: filter == .unanswered ? "checkmark.bubble" : "bubble.left.and.bubble.right"
        )
      }
    }
    .navigationTitle("Feedback")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
    .adminErrorAlert($errorMessage)
  }

  private func load() async {
    do {
      items = try await AdminAPI.feedback()
    } catch {
      items = items ?? []
      errorMessage = error.localizedDescription
    }
  }
}

private struct AdminFeedbackRow: View {
  let item: AdminFeedback

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.sm) {
      AvatarView(
        url: item.userProfilePicture,
        initials: String(item.senderName.prefix(1)).uppercased(),
        size: AvatarView.Size.medium
      )
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.senderName)
            .font(.tidexLabelStrong)
            .foregroundStyle(Color.tidexTextPrimary)
            .lineLimit(1)
          Spacer()
          AdminRelativeDate(date: item.created)
            .font(.tidexMicro)
            .foregroundStyle(Color.tidexTextMuted)
        }
        Text(item.message)
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexTextSecondary)
          .lineLimit(3)
        if item.isAnswered {
          Label("Replied", systemImage: "arrowshape.turn.up.left.fill")
            .font(.tidexCaption)
            .foregroundStyle(Color.tidexSuccess)
        }
      }
    }
    .padding(.vertical, Spacing.xxs)
  }
}

private struct AdminFeedbackDetailView: View {
  let item: AdminFeedback
  let onSent: () async -> Void

  @State private var reply: String
  @State private var isSending = false
  @State private var errorMessage: String?
  @Environment(\.dismiss) private var dismiss

  init(item: AdminFeedback, onSent: @escaping () async -> Void) {
    self.item = item
    self.onSent = onSent
    _reply = State(initialValue: item.response ?? "")
  }

  private var trimmedReply: String { reply.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    List {
      Group {
        messageSection
        replySection
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle("Feedback")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSending {
          ProgressView()
        } else {
          Button("Send", systemImage: "paperplane.fill", action: send)
            .disabled(trimmedReply.isEmpty || trimmedReply == item.response)
        }
      }
    }
    .adminErrorAlert($errorMessage)
  }

  private var messageSection: some View {
    Section {
      VStack(alignment: .leading, spacing: Spacing.xs) {
        HStack {
          Text(item.senderName).font(.tidexLabelStrong)
          Spacer()
          if let created = item.created {
            Text(created, format: .dateTime.day().month().hour().minute())
              .font(.tidexCaptionRegular)
              .foregroundStyle(Color.tidexTextMuted)
          }
        }
        Text(item.message)
          .font(.tidexBody)
          .foregroundStyle(Color.tidexTextPrimary)
          .textSelection(.enabled)
      }
      .padding(.vertical, Spacing.xxs)
    } footer: {
      Text(item.userEmail).textSelection(.enabled)
    }
  }

  private var replySection: some View {
    Section {
      TextField("Write a reply", text: $reply, axis: .vertical)
        .lineLimit(4...12)
    } header: {
      Text(item.isAnswered ? "Your reply" : "Reply")
    } footer: {
      if let responded = item.responded {
        let when: String = responded.formatted(.relative(presentation: .named))
        Text("Replied \(when). Sending again replaces it without a new notification.")
      } else {
        Text("The user gets a push notification with your reply.")
      }
    }
  }

  private func send() {
    Task {
      isSending = true
      defer { isSending = false }
      do {
        try await AdminAPI.respond(toFeedback: item.id, with: trimmedReply)
        Haptics.play(.success)
        await onSent()
        dismiss()
      } catch {
        Haptics.play(.error)
        errorMessage = error.localizedDescription
      }
    }
  }
}
