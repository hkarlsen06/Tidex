import Supabase
import SwiftUI

enum AdminBroadcastTarget: String, CaseIterable, Identifiable {
  case all
  case active
  case new
  case specific

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "Everyone"
    case .active: return "Active"
    case .new: return "New"
    case .specific: return "Specific"
    }
  }

  var footer: String {
    switch self {
    case .all: return "Every user with a registered device, except you."
    case .active: return "Users with a registered device who used the app in the last 7 days."
    case .new: return "Users with a registered device who signed up in the last 7 days."
    case .specific: return "Only the users you pick. You can pick yourself to test."
    }
  }
}

/// The broadcast form. Norwegian users get the Norwegian text; everyone else gets English.
struct AdminBroadcastDraft {
  var title: String = ""
  var body: String = ""
  var deeplink: String = ""
  var titleNo: String = ""
  var bodyNo: String = ""
  var deeplinkNo: String = ""
  var target: AdminBroadcastTarget = .all
  var recipients: [AdminUser] = []

  /// Server limits from the `admin_broadcasts` check constraints.
  static let titleLimit: Int = 100
  static let bodyLimit: Int = 500

  /// Languages someone in the audience reads. Everyone and Active always include both.
  var requiredLanguages: Set<AdminLanguage> {
    target == .specific ? Set(recipients.map(\.broadcastLanguage)) : Set(AdminLanguage.allCases)
  }

  func isComplete(_ language: AdminLanguage) -> Bool {
    let (title, body): (String, String) =
      language == .english ? (self.title, self.body) : (titleNo, bodyNo)
    return title.nilIfBlank != nil && body.nilIfBlank != nil
  }

  /// Why the draft can't be sent yet, or `nil` when it can.
  var problem: String? {
    if target == .specific, recipients.isEmpty {
      return "Pick at least one recipient."
    }
    let missing: [AdminLanguage] = AdminLanguage.allCases.filter {
      requiredLanguages.contains($0) && !isComplete($0)
    }
    if !missing.isEmpty {
      return "Fill in the \(missing.map(\.title).joined(separator: " and ")) title and message."
    }
    func length(_ text: String) -> Int {
      text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
    if max(length(title), length(titleNo)) > Self.titleLimit {
      return "Titles can be at most \(Self.titleLimit) characters."
    }
    if max(length(body), length(bodyNo)) > Self.bodyLimit {
      return "Messages can be at most \(Self.bodyLimit) characters."
    }
    return nil
  }

  var rpcParams: [String: AnyJSON] {
    func text(_ value: String) -> AnyJSON {
      value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank.map(AnyJSON.string) ?? .null
    }
    return [
      "p_title": text(title),
      "p_title_no": text(titleNo),
      "p_body": text(body),
      "p_body_no": text(bodyNo),
      "p_target": .string(target.rawValue),
      "p_deeplink": text(deeplink),
      "p_deeplink_no": text(deeplinkNo),
      "p_specific_user_ids": target == .specific
        ? .array(recipients.map { .string($0.id) }) : .null,
      "p_include_self": false,
    ]
  }
}

struct AdminBroadcastView: View {
  @State private var draft: AdminBroadcastDraft
  @State private var audienceSize: Int?
  @State private var history: [AdminBroadcast] = []
  @State private var isSending = false
  @State private var confirmSend = false
  @State private var errorMessage: String?

  /// Starts a Specific broadcast to `recipient` when set, for example from a user's detail screen.
  init(recipient: AdminUser? = nil) {
    var draft: AdminBroadcastDraft = AdminBroadcastDraft()
    if let recipient {
      draft.target = .specific
      draft.recipients = [recipient]
    }
    _draft = State(initialValue: draft)
  }

  private var recipientCount: Int? {
    draft.target == .specific ? draft.recipients.count : audienceSize
  }

  var body: some View {
    Form {
      Group {
        audienceSection
        if draft.target == .specific {
          recipientsSection
        }
        messageSection(.english, title: $draft.title, body: $draft.body, deeplink: $draft.deeplink)
        messageSection(
          .norwegian, title: $draft.titleNo, body: $draft.bodyNo, deeplink: $draft.deeplinkNo)
        sendSection
        if !history.isEmpty {
          Section("Recent") {
            ForEach(history) { broadcast in
              NavigationLink {
                AdminBroadcastDetailView(broadcast: broadcast)
              } label: {
                AdminBroadcastRow(broadcast: broadcast)
              }
            }
          }
        }
      }
      .listRowBackground(Color.tidexSurfacePrimary)
    }
    .tidexListBackground()
    .navigationTitle("Broadcast")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: draft.target) {
      guard draft.target != .specific else { return }
      audienceSize = nil
      audienceSize = try? await AdminAPI.audienceSize(for: draft.target)
    }
    .task { await loadHistory() }
    .refreshable { await loadHistory() }
    .confirmationDialog(
      "Send to \(recipientCount ?? 0) users?", isPresented: $confirmSend, titleVisibility: .visible
    ) {
      Button("Send now", action: send)
    } message: {
      Text("Push notifications can't be recalled once they go out.")
    }
    .adminErrorAlert($errorMessage)
  }

  private var audienceSection: some View {
    Section {
      Picker("Audience", selection: $draft.target) {
        ForEach(AdminBroadcastTarget.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      LabeledContent("Recipients") {
        if let recipientCount {
          Text(recipientCount, format: .number).contentTransition(.numericText())
        } else {
          ProgressView().controlSize(.small)
        }
      }
    } footer: {
      Text(draft.target.footer)
    }
  }

  private var recipientsSection: some View {
    Section("Recipients") {
      ForEach(draft.recipients) { user in
        HStack {
          AdminUserLabel(user: user)
          Spacer()
          AdminBadge(user.broadcastLanguage.code, color: .tidexTextSecondary)
        }
      }
      .onDelete { draft.recipients.remove(atOffsets: $0) }
      AdminUserSearchRows(excluding: Set(draft.recipients.map(\.id))) {
        draft.recipients.append($0)
      }
    }
  }

  private func messageSection(
    _ language: AdminLanguage, title: Binding<String>, body: Binding<String>,
    deeplink: Binding<String>
  ) -> some View {
    let isRequired: Bool = draft.requiredLanguages.contains(language)
    return Section {
      TextField("Title", text: title)
      TextField("Message", text: body, axis: .vertical)
        .lineLimit(2...6)
      TextField("Deep link, e.g. tidex://shifts (optional)", text: deeplink)
        .font(.tidexMonoCaptionRegular)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .keyboardType(.URL)
    } header: {
      Text(isRequired ? "\(language.title) *" : language.title)
    } footer: {
      if !isRequired, !draft.recipients.isEmpty {
        Text("Optional. None of the recipients get \(language.title) text.")
      }
    }
  }

  private var sendSection: some View {
    Section {
      Button {
        confirmSend = true
      } label: {
        HStack {
          Spacer()
          if isSending {
            ProgressView()
          } else {
            Label("Send broadcast", systemImage: "paperplane.fill").font(.tidexButton)
          }
          Spacer()
        }
      }
      .disabled(draft.problem != nil || isSending || recipientCount == 0)
    } footer: {
      if let problem = draft.problem {
        Text(problem)
      } else {
        Text("The form stays filled in after sending, so you can test on yourself first.")
      }
    }
  }

  private func loadHistory() async {
    do {
      history = try await AdminAPI.broadcasts()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func send() {
    Task {
      isSending = true
      defer { isSending = false }
      do {
        try await AdminAPI.sendBroadcast(draft)
        Haptics.play(.success)
        await loadHistory()
      } catch {
        Haptics.play(.error)
        errorMessage = error.localizedDescription
      }
    }
  }
}

/// Colors for `admin_broadcasts.status` and `notifications_outbox.status`.
func adminBroadcastStatusColor(_ status: String) -> Color {
  switch status {
  case "complete", "sent": return .tidexSuccess
  case "failed", "partial_failure": return .tidexError
  case "skipped": return .tidexTextMuted
  default: return .tidexWarning
  }
}

private struct AdminBroadcastRow: View {
  let broadcast: AdminBroadcast

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      HStack(alignment: .firstTextBaseline) {
        Text(broadcast.title)
          .font(.tidexLabelStrong)
          .foregroundStyle(Color.tidexTextPrimary)
          .lineLimit(1)
        Spacer()
        AdminBadge(
          broadcast.status.adminHumanized, color: adminBroadcastStatusColor(broadcast.status))
      }
      Text(broadcast.body)
        .font(.tidexFootnote)
        .foregroundStyle(Color.tidexTextSecondary)
        .lineLimit(2)
      ProgressView(value: Double(broadcast.sentCount), total: Double(max(broadcast.targetCount, 1)))
        .tint(broadcast.failedCount > 0 ? Color.tidexWarning : Color.tidexSuccess)
      HStack {
        Text("\(broadcast.sentCount) of \(broadcast.targetCount) sent")
        if broadcast.failedCount > 0 {
          Text("· \(broadcast.failedCount) failed").foregroundStyle(Color.tidexError)
        }
        if broadcast.pendingCount > 0 {
          Text("· \(broadcast.pendingCount) pending")
        }
        Spacer()
        Text(broadcast.target.adminHumanized)
        AdminRelativeDate(date: broadcast.created)
      }
      .font(.tidexMicro)
      .foregroundStyle(Color.tidexTextMuted)
    }
    .padding(.vertical, Spacing.xxs)
  }
}
