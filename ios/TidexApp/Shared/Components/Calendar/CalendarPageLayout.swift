import SwiftUI

/// Places a month and its controls above the floating month picker in both calendars.
struct CalendarPageLayout<Content: View, EmptyContent: View>: View {
  let pinsControlsToBottom: Bool
  var onRefresh: (() async -> Void)?
  let onSwipeLeft: () -> Void
  let onSwipeRight: () -> Void
  @ViewBuilder let content: (Bool) -> Content
  @ViewBuilder let emptyContent: () -> EmptyContent

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    GeometryReader { geometry in
      let isWide = geometry.size.width >= 700
      let pinsControls = !isWide && pinsControlsToBottom
      let calendarWidth =
        isWide
        ? min(AdaptiveMaxWidth.tabContent, max(350, geometry.size.height * 0.7))
        : AdaptiveMaxWidth.tabContent

      let page = ScrollView {
        self.page(isWide: isWide, pinsControls: pinsControls, calendarWidth: calendarWidth)
          .frame(minHeight: geometry.size.height + (onRefresh == nil ? 0 : 1))
          // Inside the scroll view, the swipe attaches to it and sees a drag anywhere on the page.
          .monthSwipeGesture(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
      }
      .scrollBounceBehavior(onRefresh == nil ? .basedOnSize : .always, axes: .vertical)
      .scrollIndicators(.hidden)

      if let onRefresh {
        page.refreshable { await onRefresh() }
      } else {
        page
      }
    }
  }

  private func page(isWide: Bool, pinsControls: Bool, calendarWidth: CGFloat) -> some View {
    VStack {
      if isWide { Spacer() }
      content(pinsControls)
        .frame(maxWidth: calendarWidth)
        .padding(.horizontal, horizontalSizeClass == .regular ? Spacing.md : Spacing.xs)
        .padding(.top, isWide ? 0 : CalendarGridHelper.phoneMonthTopPadding)
      emptyContent()
      if !pinsControls { Spacer() }
    }
    .frame(maxWidth: .infinity)
    .padding(.bottom, MonthPickerLayout.totalBottomInset)
  }
}

/// One or more calendar controls share the same width, spacing and bottom placement.
struct CalendarControlStack<Controls: View, Hint: View>: View {
  let isPinned: Bool
  @ViewBuilder let controls: () -> Controls
  @ViewBuilder let hint: (Bool) -> Hint

  var body: some View {
    if isPinned {
      Spacer(minLength: Spacing.sm)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { hint(true) }
    } else {
      hint(false)
    }

    VStack(spacing: Spacing.xs) {
      controls()
    }
    .padding(
      .horizontal, isPinned ? MonthPickerLayout.tabBarAlignedHorizontalPadding - Spacing.xs : 0
    )
    .padding(.top, isPinned ? 0 : Spacing.sm)
    .padding(.bottom, isPinned ? MonthPickerLayout.bottomPadding : 0)
  }
}
