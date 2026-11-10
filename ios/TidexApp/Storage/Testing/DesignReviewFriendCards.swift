#if DEBUG
  import SwiftUI

  /// Friend cards in their main states, for TIDEX_DESIGN_SCREEN=friends. Set
  /// TIDEX_DESIGN_FRIENDS_VIEW to add-friend, profile, schedule or chat-header for the others.
  /// TIDEX_DESIGN_FRIENDS_TIME_ZONE=1 puts the friends in another time zone, except Nora's card,
  /// and =unknown leaves the schedule without one. TIDEX_DESIGN_FRIENDS_NAME renames the schedule's
  /// friend.
  internal struct DesignReviewFriendCards: View {
    private let view: String =
      ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_VIEW"] ?? "cards"
    @State private var isSuperimposing = false

    internal var body: some View {
      switch view {
      case "add-friend": addFriend
      case "profile": profile
      case "schedule": schedule
      case "chat-header":
        CompactFriendShiftPreviewHeader(
          preview: Self.preview(for: "Ella", startOffset: 180, duration: 480), friendName: "Ella"
        )
        .padding(Spacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.tidexBackground)
        .userCurrency("kr")
      default: cards
      }
    }

    /// A friend's September 2026 with shifts around midnight and both month edges. One shift is
    /// recorded on the day before the first visible day.
    private var schedule: some View {
      let sharer = SharedUser(
        id: "ella", email: "ella@example.com", phone: nil,
        firstName: ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_NAME"] ?? "Ella",
        profilePictureUrl: nil, oauthAvatarUrl: nil, sharedAt: "2026-01-01",
        showEarnings: ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_EARNINGS"] != "0",
        hidden: false)
      let shifts = Self.scheduleShifts
      let ownShifts = [
        ("08", "12:00", "20:00"), ("15", "06:00", "10:00"), ("22", "09:00", "17:00"),
      ]
      .map { day, start, end in
        ShiftRow(
          id: "own-\(day)", user_id: nil, shift_date: "2026-09-\(day)", start_time: start,
          end_time: end, custom_supplements: nil)
      }
      return NavigationStack {
        SharedShiftsListView(
          sharer: sharer,
          shifts: shifts.filter { $0.shiftDate >= "2026-08-31" },
          boundaryShifts: shifts.filter { $0.shiftDate < "2026-08-31" },
          jobs: [], year: SharedMonthContext.shared.displayYear,
          month: SharedMonthContext.shared.displayMonth,
          phase: nil, isLoading: false, isContentReady: true,
          ownerTimeZone: Self.scheduleZone?.identifier,
          isSuperimposing: isSuperimposing,
          userHoursByDate: Dictionary(
            uniqueKeysWithValues: ownShifts.map { row in
              (
                row.shift_date,
                HoursData(start: row.start_time, end: row.end_time, crossesMidnight: false)
              )
            }),
          userShiftsByDate: Dictionary(grouping: ownShifts, by: \.shift_date)
        )
        .overlay(alignment: .bottom) {
          MonthPickerControls(showsViewModeToggle: true, showsAddButton: false, onAddShift: {})
        }
        .task { SharedMonthContext.shared.navigateTo(year: 2_026, month: 9) }
        .navigationTitle(sharer.firstNameOnly)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          Toggle(String(localized: .sharingSuperimposeLegendBoth), isOn: $isSuperimposing)
        }
      }
      .frame(
        maxWidth: ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_WIDTH"]
          .flatMap(Double.init).map { CGFloat($0) } ?? .infinity
      )
      .userCurrency("kr")
      .environment(AppCoordinator.shared)
    }

    private static var scheduleZone: TimeZone? {
      switch ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_TIME_ZONE"] {
      case "1":
        // London, or Tokyo for a viewer on London's clock when the fixture shifts happen.
        let reference = Date.fromISODateString("2026-09-10") ?? .now
        return ["Europe/London", "Asia/Tokyo"].compactMap { TimeZone(identifier: $0) }.first {
          $0.secondsFromGMT(for: reference) != TimeZone.current.secondsFromGMT(for: reference)
        }

      case "unknown":
        return nil

      default:
        return TimeZone.current
      }
    }

    private static var scheduleShifts: [ShiftWithComputations] {
      let snapshot = WageSnapshot(
        id: "design-wage", user_id: "ella", from_date: nil, hourly_wage: 250, wage_level: nil,
        tariff_type_id: nil, supplements: SupplementRulesSnapshot(rules: []),
        tax_enabled: false, tax_percentage: 0, break_enabled: false,
        break_method: BreakMethod.proportional.rawValue, break_threshold_hours: 5.5,
        break_deduction_minutes: 30, created_at: nil)
      return [
        ("2026-08-30", "23:30", "07:30"), ("2026-09-08", "09:00", "17:00"),
        ("2026-09-10", "05:00", "13:00"), ("2026-09-14", "23:30", "07:30"),
        ("2026-09-19", "14:00", "22:00"), ("2026-09-24", "16:00", "23:30"),
        ("2026-09-30", "23:15", "06:00"),
      ].map { date, start, end in
        let row = ShiftRow(
          id: "ella-\(date)", user_id: "ella", shift_date: date, start_time: start,
          end_time: end, custom_supplements: nil)
        return ShiftWithComputations(
          shift: row, computed: PayrollCalculator.computeShift(row, snapshot: snapshot),
          taxEnabled: false, taxPercentage: 0)
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
            card(
              "Henrik", minutesAgo: 30, shift: (Self.minutesUntilTomorrow(atHour: 22), 480),
              convertedAtUTCHour: 21)
            card("Ella", minutesAgo: 12, state: .incomingUnread, unread: 2, shift: (-120, 180))
            card("Jonas Berg", minutesAgo: 90, state: .outgoingOpened, shift: (1_200, 480))
            card("Maja", isTyping: true, shift: (-1_800, 420))
            card("Oskar Lie", isCalendarAvailable: false)
            card("Sofie", minutesAgo: 4, state: .outgoingFailed, isCalendarAvailable: false)
            card(
              "Nora", minutesAgo: 3_000, state: .incomingOpened, shift: (4_320, 360),
              convertedAtUTCHour: nil)
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

    /// `shift` is (start offset from now in minutes, duration in minutes). In the time zone check
    /// the shift starts at `convertedAtUTCHour` today instead, or keeps the viewer's zone when nil.
    private func card(
      _ name: String,
      minutesAgo: Double? = nil,
      state: FriendCardMessageState = .incomingOpened,
      unread: Int = 0,
      isTyping: Bool = false,
      isCalendarAvailable: Bool = true,
      shift: (Double, Double)? = nil,
      convertedAtUTCHour: Double? = 5
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
        preview: shift.map {
          Self.preview(
            for: name, startOffset: $0.0, duration: $0.1, convertedAtUTCHour: convertedAtUTCHour)
        },
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
  }

  extension DesignReviewFriendCards {
    private static func preview(
      for id: String, startOffset: Double, duration: Double, convertedAtUTCHour: Double? = 5
    ) -> SharerShiftPreview {
      let isTimeZoneCheck =
        ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_TIME_ZONE"] == "1"
      var utc = Calendar(identifier: .gregorian)
      utc.timeZone = .gmt
      let isWidgetCheck = ProcessInfo.processInfo.environment["TIDEX_DESIGN_FRIENDS_WIDGETS"] == "1"
      let convertedHour = isTimeZoneCheck ? (isWidgetCheck ? 23.5 : convertedAtUTCHour) : nil
      let start =
        convertedHour.map { utc.startOfDay(for: .now).addingTimeInterval($0 * 3_600) }
        ?? Date.now.addingTimeInterval(startOffset * 60)
      let end = start.addingTimeInterval(duration * 60)
      let sourceZone =
        convertedHour == nil
        ? TimeZone.current
        : (TimeZone.current.secondsFromGMT(for: start) == 0
          ? TimeZone(identifier: "Asia/Tokyo") : TimeZone(identifier: "Europe/London"))
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
