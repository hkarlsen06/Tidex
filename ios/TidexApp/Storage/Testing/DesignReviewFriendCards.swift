#if DEBUG
  import SwiftUI

  /// Friend cards in their main states, for TIDEX_DESIGN_SCREEN=friends. Set
  /// TIDEX_DESIGN_FRIENDS_VIEW to add-friend or profile for the other Friends screens.
  internal struct DesignReviewFriendCards: View {
    @State private var identifier = "ella@example.com"
    @State private var showEarnings = true
    @State private var isExpanded = true
    @State private var isCollapsed = false
    @State private var addError: String?

    private let view: String =
      ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_VIEW"] ?? "cards"

    internal var body: some View {
      switch view {
      case "add-friend": addFriend
      case "profile": profile
      default: cards
      }
    }

    private var addFriend: some View {
      NavigationStack {
        List {
          Section {
            AddFriendForm(
              isExpanded: $isCollapsed, identifier: .constant(""), showEarnings: .constant(false),
              error: $addError, isLoading: false, isOfflineUnavailable: false,
              onAdd: {}, onCancel: {})
          }
          .listRowInsets(EdgeInsets())
          Section {
            AddFriendForm(
              isExpanded: $isExpanded, identifier: $identifier, showEarnings: $showEarnings,
              error: $addError, isLoading: false, isOfflineUnavailable: false,
              onAdd: {}, onCancel: {})
          }
          .listRowInsets(EdgeInsets())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .sharingSeeFriends))
        .navigationBarTitleDisplayMode(.inline)
      }
    }

    private var profile: some View {
      let friend = Friend(
        id: "ella", email: "ella@example.com", phone: nil, username: nil, firstName: "Ella",
        profilePictureUrl: nil, oauthAvatarUrl: nil,
        sharesWithMe: Friend.SharesWithMe(
          hidden: false, showEarningsToMe: true, sharedAt: "2026-01-01",
          notificationFrequency: .instant),
        iShareWith: Friend.IShareWith(showEarningsToThem: false, sharedAt: "2026-01-01"))
      return FriendProfileView(
        sharedUser: SharedUser(
          id: "ella", email: "ella@example.com", phone: nil, firstName: "Ella",
          profilePictureUrl: nil, oauthAvatarUrl: nil, sharedAt: "2026-01-01",
          showEarnings: true, hidden: false),
        onMessageTapped: {},
        initialSnapshot: FriendsManagementSnapshot(
          friends: [friend], blockedFriends: []))
    }

    private var cards: some View {
      NavigationStack {
        ScrollView {
          VStack(spacing: Spacing.sm) {
            ScreenshotNotificationBubble(
              notifiedName: "Ella", showNotifiedIcon: true, bellShakeTrigger: false)
            card("Henrik", minutesAgo: 30, shift: (Self.minutesUntilTomorrow(atHour: 22), 480))
            card("Ella", minutesAgo: 12, state: .incomingUnread, unread: 2, shift: (-120, 180))
            card("Jonas Berg", minutesAgo: 90, state: .outgoingOpened, shift: (1_200, 480))
            card("Maja", isTyping: true, shift: (-1_800, 420))
            card("Oskar Lie", isCalendarAvailable: false)
            card("Sofie", minutesAgo: 4, state: .outgoingFailed, isCalendarAvailable: false)
            card("Nora", minutesAgo: 3_000, state: .incomingOpened, shift: (4_320, 360))
            card("Terese Caroline Roysdatter", minutesAgo: 60, state: .outgoingSent)
          }
          .padding(.horizontal, Spacing.md)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .tabsSharing))
      }
      .userCurrency("kr")
    }

    /// `shift` is (start offset from now in minutes, duration in minutes).
    private func card(
      _ name: String,
      minutesAgo: Double? = nil,
      state: FriendCardMessageState = .incomingOpened,
      unread: Int = 0,
      isTyping: Bool = false,
      isCalendarAvailable: Bool = true,
      shift: (Double, Double)? = nil
    ) -> some View {
      let sharer = SharedUser(
        id: name, email: "\(name.lowercased().prefix(4))@example.com", phone: nil,
        firstName: name, profilePictureUrl: nil, oauthAvatarUrl: nil, sharedAt: "2026-01-01",
        showEarnings: true, hidden: false)
      let message = minutesAgo.map {
        FriendCardMessagePreview(
          text: "Can you take my Friday evening shift?",
          timestamp: .now.addingTimeInterval(-$0 * 60), state: state)
      }
      return FriendCard(
        sharer: sharer,
        preview: shift.map { Self.preview(for: name, startOffset: $0.0, duration: $0.1) },
        messagePreview: message, isTyping: isTyping, isSelected: false, isRefreshing: false,
        onChatTap: {}, onCalendarTap: {}, isCalendarAvailable: isCalendarAvailable,
        unreadMessageCount: unread)
    }

    private static func minutesUntilTomorrow(atHour hour: Int) -> Double {
      let tomorrow =
        Calendar.current.date(
          byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
      let start = Calendar.current.date(byAdding: .hour, value: hour, to: tomorrow) ?? tomorrow
      return start.timeIntervalSinceNow / 60
    }

    private static func preview(for id: String, startOffset: Double, duration: Double)
      -> SharerShiftPreview
    {
      let start = Date.now.addingTimeInterval(startOffset * 60)
      let end = start.addingTimeInterval(duration * 60)
      let time = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute()
        .locale(Locale(identifier: "en_GB"))
      let status: ShiftPreviewStatus = end < .now ? .past : (start > .now ? .upcoming : .active)
      let shift = SharedShiftData(
        id: id, user_id: id, job_id: nil, job_name: nil, job_color: nil,
        shift_date: start.toISODateString(), start_time: start.formatted(time),
        end_time: end.formatted(time),
        computed: SharedShiftComputed(
          id: id, durationHours: duration / 60, paidHours: duration / 60, basePay: 1_200,
          supplementPay: 0, gross: 1_200,
          breakAudit: SharedBreakAudit(
            method: .none, thresholdHours: 0, deductedHours: 0, source: .none,
            appliedPauseWindows: nil, notes: [])),
        tax_enabled: false, tax_percentage: nil, custom_pause_windows: nil,
        custom_supplements: nil, recurring_id: nil, recurring_anchor_weekday: nil)
      return SharerShiftPreview(
        sharerId: id, shift: shift, status: status, showEarnings: true, currency: "kr")
    }
  }
#endif
