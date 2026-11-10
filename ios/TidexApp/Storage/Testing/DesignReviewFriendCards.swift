#if DEBUG
  import SwiftUI

  /// Friend cards in their main states, for TIDEX_DESIGN_SCREEN=friends. Set
  /// TIDEX_DESIGN_FRIENDS_VIEW to add-friend or profile for the other Friends screens.
  internal struct DesignReviewFriendCards: View {
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
      let hidden = Friend(
        id: "jonas", email: "jonas@example.com", phone: nil, username: nil, firstName: "Jonas Berg",
        profilePictureUrl: nil, oauthAvatarUrl: nil,
        sharesWithMe: Friend.SharesWithMe(
          hidden: true, showEarningsToMe: false, sharedAt: "2026-01-01",
          notificationFrequency: .instant),
        iShareWith: nil)
      let blocked = Friend(
        id: "oskar", email: "oskar@example.com", phone: nil, username: nil, firstName: "Oskar Lie",
        profilePictureUrl: nil, oauthAvatarUrl: nil, sharesWithMe: nil, iShareWith: nil)
      return AddFriendSheet(
        initialSnapshot: FriendsManagementSnapshot(friends: [hidden], blockedFriends: [blocked]))
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
          .adaptiveMaxWidth(AdaptiveMaxWidth.tabContent)
        }
        .background(Color.tidexBackground)
        .navigationTitle(String(localized: .tabsSharing))
      }
      .userCurrency("kr")
      .task {
        guard ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_WIDGETS"] == "1" else {
          return
        }
        let names = ["Henrik", "Ella", "Jonas", "Nora", "Maja"]
        let sharers = names.map { name in
          SharedUser(
            id: name, email: "friend@example.com", phone: nil, firstName: name,
            profilePictureUrl: nil, oauthAvatarUrl: nil, sharedAt: "2026-01-01",
            showEarnings: true, hidden: false)
        }
        let previews = names.map { Self.preview(for: $0, startOffset: 0, duration: 480) }
        NativeWidgetStorage.updateFriendWidgetStorage(sharers: sharers, previews: previews)
      }
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
        Calendar.gregorianCurrent.date(
          byAdding: .day, value: 1, to: Calendar.gregorianCurrent.startOfDay(for: .now)) ?? .now
      let start =
        Calendar.gregorianCurrent.date(byAdding: .hour, value: hour, to: tomorrow) ?? tomorrow
      return start.timeIntervalSinceNow / 60
    }

    private static func preview(for id: String, startOffset: Double, duration: Double)
      -> SharerShiftPreview
    {
      let isTimeZoneCheck =
        ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_TIME_ZONE"] == "1"
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = .gmt
      let isWidgetCheck = ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_WIDGETS"] == "1"
      let start =
        isTimeZoneCheck
        ? utc.startOfDay(for: .now).addingTimeInterval((isWidgetCheck ? 23.5 : 5) * 3_600)
        : Date.now.addingTimeInterval(startOffset * 60)
      let end = start.addingTimeInterval(duration * 60)
      let sourceZone =
        isTimeZoneCheck
        ? (TimeZone.current.secondsFromGMT(for: start) == 0
          ? TimeZone(identifier: "Asia/Tokyo") : TimeZone(identifier: "Europe/London"))
        : TimeZone.current
      let time = DateFormatter()
      time.locale = Locale(identifier: "en_US_POSIX")
      time.calendar = Calendar(identifier: .gregorian)
      time.timeZone = sourceZone ?? .current
      time.dateFormat = "HH:mm"
      let status: ShiftPreviewStatus = end < .now ? .past : (start > .now ? .upcoming : .active)
      let shift = SharedShiftData(
        id: id, user_id: id, job_id: nil, job_name: nil, job_color: nil,
        shift_date: start.toISODateString(in: sourceZone ?? .current),
        start_time: time.string(from: start),
        end_time: time.string(from: end),
        computed: SharedShiftComputed(
          id: id, durationHours: duration / 60, paidHours: duration / 60, basePay: 1_200,
          supplementPay: 0, gross: 1_200,
          breakAudit: SharedBreakAudit(
            method: .none, thresholdHours: 0, deductedHours: 0, source: .none,
            appliedPauseWindows: nil, notes: [])),
        tax_enabled: false, tax_percentage: nil, custom_pause_windows: nil,
        custom_supplements: nil, recurring_id: nil, recurring_anchor_weekday: nil,
        ownerTimeZone: sourceZone?.identifier)
      return SharerShiftPreview(
        sharerId: id, shift: shift, status: status, showEarnings: true, currency: "kr")
    }
  }
#endif
