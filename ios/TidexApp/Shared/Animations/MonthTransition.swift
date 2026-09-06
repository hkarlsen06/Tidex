// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image accessibility_trait_for_button closure_body_length conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_name file_types_order no_magic_numbers prefer_self_in_static_references
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable type_body_length type_contents_order
import SwiftUI

// MonthNavigationDirection is defined in MonthSwipeGesture.swift
// This file provides animation utilities for month transitions

// MARK: - Animation State Environment

/// Environment key for tracking whether a month transition animation is in progress
/// Child views can read this to buffer data changes during animation
private struct MonthAnimatingKey: EnvironmentKey {
  static let defaultValue: Bool = false
}

extension EnvironmentValues {
  /// Whether a month transition animation is currently in progress
  /// Use this to defer data updates until animation completes
  var isMonthAnimating: Bool {
    get { self[MonthAnimatingKey.self] }
    set { self[MonthAnimatingKey.self] = newValue }
  }
}

// MARK: - Layout Constants

/// Layout constants for the floating MonthPicker above the tab bar
enum MonthPickerLayout {
  private static let cornerRadiusDivisor: CGFloat = 2

  internal static let enabledOpacity: Double = 1
  internal static let disabledOpacity: Double = 0.6
  internal static let progressIndicatorScale: CGFloat = 0.9

  /// Horizontal padding for the MonthPicker pill
  /// This value is calculated so the edges of the MonthPicker align with
  /// where a 30pt corner radius "flattens out" on a full-width element
  internal static let horizontalPadding: CGFloat = 40

  /// Aligns the floating month controls with the native iPhone tab bar capsule.
  internal static let tabBarAlignedHorizontalPadding: CGFloat = 24

  /// Bottom padding between MonthPicker and tab bar
  internal static let bottomPadding: CGFloat = 8

  /// Height of the native iPhone tab bar.
  internal static let iPhoneTabBarHeight: CGFloat = 49

  /// Height of the MonthPicker pill
  internal static let height: CGFloat = 50

  /// Corner radius for the glass effect
  internal static let cornerRadius: CGFloat = height / cornerRadiusDivisor

  /// Total inset needed to keep content above the floating month picker
  internal static let totalBottomInset: CGFloat = height + bottomPadding
}

// MARK: - Month Transition Configuration

/// Configuration for month transition animations
struct MonthTransitionConfig {
  /// Duration of the transition (in seconds)
  let duration: Double
  /// Spring response for the animation
  let springResponse: Double
  /// Spring damping fraction
  let dampingFraction: Double
  /// Horizontal offset for slide transitions
  let slideOffset: CGFloat
  /// Vertical offset for text transitions
  let textOffset: CGFloat
  /// Stagger delay between cards
  let staggerDelay: Double
  /// Whether to use compact vertical layout for month/year
  let isCompact: Bool

  static let `default` = Self(
    duration: 0.35,
    springResponse: 0.35,
    dampingFraction: 0.85,
    slideOffset: 60,
    textOffset: 20,
    staggerDelay: 0.05,
    isCompact: false
  )

  static let fast = Self(
    duration: 0.25,
    springResponse: 0.25,
    dampingFraction: 0.9,
    slideOffset: 40,
    textOffset: 15,
    staggerDelay: 0.03,
    isCompact: false
  )

  static let compact = Self(
    duration: 0.3,
    springResponse: 0.3,
    dampingFraction: 0.85,
    slideOffset: 40,
    textOffset: 15,
    staggerDelay: 0.03,
    isCompact: true
  )
}

// MARK: - Month Transition Effect

/// Represents the animation state for month transitions
struct MonthTransitionPhase: Equatable {
  let year: Int
  let month: Int
  let direction: MonthNavigationDirection?

  var id: String { "\(year)-\(month)" }
}

// MARK: - Card Transition Modifier

/// A view modifier that applies slide transition to cards
/// Similar to the Next.js calendar grid animation
/// Uses horizontal left/right animation.
struct CardTransitionModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  let phase: MonthTransitionPhase
  let index: Int
  let config: MonthTransitionConfig

  @State private var isAppearing = false

  func body(content: Content) -> some View {
    content
      .offset(x: visibleOffsetX, y: 0)
      .onAppear {
        guard !reduceMotion else {
          isAppearing = true
          return
        }
        // Stagger the appearance of each card
        let delay = Double(index) * config.staggerDelay
        withAnimation(
          .spring(response: config.springResponse, dampingFraction: config.dampingFraction)
            .delay(delay)
        ) {
          isAppearing = true
        }
      }
      .onChange(of: phase.id) { _, _ in
        // Reset and re-animate on month change
        isAppearing = false
        guard !reduceMotion else {
          isAppearing = true
          return
        }
        let delay = Double(index) * config.staggerDelay
        withAnimation(
          .spring(response: config.springResponse, dampingFraction: config.dampingFraction)
            .delay(delay)
        ) {
          isAppearing = true
        }
      }
  }

  private var slideOffset: CGFloat {
    guard let direction = phase.direction else { return 0 }
    let base = direction == .next ? config.slideOffset : -config.slideOffset
    if layoutDirection == .rightToLeft {
      return -base
    }
    return base
  }

  private var visibleOffsetX: CGFloat {
    guard !reduceMotion else { return 0 }
    return isAppearing ? 0 : slideOffset
  }
}

// MARK: - Text Transition Modifier

/// A view modifier that applies slide transition to text (month/year labels)
/// Text slides horizontally in the direction of navigation.
struct TextTransitionModifier: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  let phase: MonthTransitionPhase
  let config: MonthTransitionConfig

  func body(content: Content) -> some View {
    content
      .id(phase.id)
      .transition(textTransition)
      .animation(
        reduceMotion
          ? nil : .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
        value: phase.id
      )
  }

  private var textTransition: AnyTransition {
    if reduceMotion { return .identity }
    let direction = phase.direction
    let base = direction == .next ? config.textOffset : -config.textOffset
    let offset = layoutDirection == .rightToLeft ? -base : base

    return .asymmetric(
      insertion: .offset(x: offset),
      removal: .offset(x: -offset)
    )
  }
}

// MARK: - Staggered Cards Container

/// A container wrapper for calendar content that applies slide animations
/// when navigating between months.
struct StaggeredCardsContainer<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  let phase: MonthTransitionPhase
  let config: MonthTransitionConfig
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .id(phase.id)
      .transition(slideTransition)
      .animation(
        reduceMotion
          ? nil : .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
        value: phase.id
      )
  }

  /// Asymmetric transition: new content slides in from direction of navigation,
  /// old content slides out in the opposite direction
  private var slideTransition: AnyTransition {
    guard !reduceMotion else { return .identity }
    let base = phase.direction == .next ? config.slideOffset : -config.slideOffset
    let offset = layoutDirection == .rightToLeft ? -base : base

    return .asymmetric(
      insertion: .offset(x: offset),
      removal: .offset(x: -offset)
    )
  }
}

// MARK: - Month Year Picker Sheet

/// A sheet with wheel pickers for selecting month and year
struct MonthYearPickerSheet: View {
  @Binding var isPresented: Bool
  let currentYear: Int
  let currentMonth: Int
  let onSelect: (Int, Int) -> Void

  @State private var selectedYear: Int
  @State private var selectedMonth: Int

  // Year range: 5 years back to 5 years forward
  private var yearRange: [Int] {
    let currentCalendarYear = Calendar.current.component(.year, from: Date())
    return Array((currentCalendarYear - 5)...(currentCalendarYear + 5))
  }

  // Month names (localized)
  private var monthNames: [String] {
    FormatterCache.monthNameFormatter(locale: .appLocale)
      .monthSymbols
      .map { $0.sentenceCased() }
  }

  /// Current real month/year for the "This month" button
  private var realMonth: (year: Int, month: Int) {
    Date.currentYearMonth()
  }

  /// Whether the picker is already showing the current month
  private var isShowingCurrentMonth: Bool {
    selectedYear == realMonth.year && selectedMonth == realMonth.month
  }

  private var selectedMonthName: String {
    monthNames[selectedMonth - 1]
  }

  init(
    isPresented: Binding<Bool>, currentYear: Int, currentMonth: Int,
    onSelect: @escaping (Int, Int) -> Void
  ) {
    self._isPresented = isPresented
    self.currentYear = currentYear
    self.currentMonth = currentMonth
    self.onSelect = onSelect
    self._selectedYear = State(initialValue: currentYear)
    self._selectedMonth = State(initialValue: currentMonth)
  }

  var body: some View {
    VStack(spacing: Spacing.md) {
      sheetActions
      selectedPeriodHeader
      pickerWheels
    }
    .padding(.horizontal, Spacing.md)
    .padding(.top, Spacing.xl)
    .padding(.bottom, Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Color.tidexBackground)
    .presentationBackground(Color.tidexBackground)
    .presentationDetents([.height(342)])
    .presentationDragIndicator(.visible)
  }

  private var sheetActions: some View {
    HStack(spacing: Spacing.sm) {
      Button {
        isPresented = false
      } label: {
        Text(.commonCancel)
      }
      .buttonStyle(MonthPickerActionButtonStyle())

      Spacer(minLength: Spacing.xxs)

      Button {
        onSelect(realMonth.year, realMonth.month)
        isPresented = false
      } label: {
        Text(.commonThisMonth)
      }
      .buttonStyle(MonthPickerCurrentButtonStyle(isSelected: isShowingCurrentMonth))
      .disabled(isShowingCurrentMonth)

      Spacer(minLength: Spacing.xxs)

      Button {
        onSelect(selectedYear, selectedMonth)
        isPresented = false
      } label: {
        Text(.commonDone)
      }
      .buttonStyle(MonthPickerActionButtonStyle(isProminent: true))
    }
  }

  private var selectedPeriodHeader: some View {
    HStack(spacing: Spacing.xs) {
      Text(selectedMonthName)
      Text(String(selectedYear))
    }
    .font(.title3.weight(.semibold))
    .foregroundColor(.tidexTextPrimary)
    .frame(maxWidth: .infinity)
    .padding(.top, Spacing.xxs)
  }

  private var pickerWheels: some View {
    VStack(spacing: 0) {
      Divider()
        .background(Color.tidexSeparator)

      HStack(spacing: 0) {
        Picker("Month", selection: $selectedMonth) {
          ForEach(1...12, id: \.self) { month in
            Text(monthNames[month - 1])
              .tag(month)
          }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()

        Picker("Year", selection: $selectedYear) {
          ForEach(yearRange, id: \.self) { year in
            Text(String(year))
              .tag(year)
          }
        }
        .pickerStyle(.wheel)
        .frame(width: 112)
        .clipped()
      }
      .frame(height: 174)

      Divider()
        .background(Color.tidexSeparator)
    }
  }
}

private struct MonthPickerActionButtonStyle: ButtonStyle {
  var isProminent = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(isProminent ? .semibold : .regular))
      .foregroundColor(.tidexBlue)
      .lineLimit(1)
      .minimumScaleFactor(0.82)
      .frame(minWidth: 72, minHeight: 44)
      .padding(.horizontal, Spacing.xs)
      .background(Color.tidexSurfacePrimary, in: Capsule())
      .overlay(
        Capsule()
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

private struct MonthPickerCurrentButtonStyle: ButtonStyle {
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.body.weight(.medium))
      .foregroundColor(isSelected ? .tidexTextSecondary : .tidexBlue)
      .lineLimit(1)
      .minimumScaleFactor(0.82)
      .frame(minWidth: 104, minHeight: 44)
      .padding(.horizontal, Spacing.xs)
      .background(
        isSelected ? Color.tidexSurfaceSecondary : Color.tidexBlue.opacity(0.08),
        in: Capsule()
      )
      .overlay(
        Capsule()
          .stroke(
            isSelected ? Color.tidexBorderSubtle : Color.tidexBlue.opacity(0.16), lineWidth: 1)
      )
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

// MARK: - Animated Month Header

/// An animated header showing month and year with horizontal text transitions
/// Supports swipe gestures for month navigation and tap to open month/year picker
/// "Return to current month" functionality is in the MonthYearPickerSheet
struct AnimatedMonthHeader: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.layoutDirection) private var layoutDirection
  let monthName: String
  let year: Int
  let phase: MonthTransitionPhase
  let config: MonthTransitionConfig
  let onPrevious: () -> Void
  let onNext: () -> Void
  let onNavigateToMonth: ((Int, Int) -> Void)?
  let isLoading: Bool

  @State private var monthScale: CGFloat = 1.0
  @State private var showingMonthPicker = false
  @ScaledMetric(relativeTo: .body) private var navPillVisualSize: CGFloat = 36
  @ScaledMetric(relativeTo: .body) private var navTapTargetSize: CGFloat = 44
  @ScaledMetric(relativeTo: .body) private var navTextSafeInset: CGFloat = 24
  @ScaledMetric(relativeTo: .body) private var navIconSize: CGFloat = 16

  // Haptic feedback for swipe, tap, and long press
  private let swipeHaptic = UIImpactFeedbackGenerator(style: .medium)
  private let tapHaptic = UIImpactFeedbackGenerator(style: .light)
  private let longPressHaptic = UIImpactFeedbackGenerator(style: .heavy)

  /// Current real month/year for long press "jump to current month"
  private var currentMonth: (year: Int, month: Int) {
    Date.currentYearMonth()
  }

  /// Whether we're already on the current month
  private var isOnCurrentMonth: Bool {
    phase.year == currentMonth.year && phase.month == currentMonth.month
  }

  /// Short year format (2 digits) - e.g., "26" for 2026
  private var shortYear: String {
    String(format: "%02d", year % 100)
  }

  private var previousIcon: String {
    layoutDirection == .rightToLeft ? "chevron.right" : "chevron.left"
  }

  private var nextIcon: String {
    layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right"
  }

  var body: some View {
    Group {
      if config.isCompact {
        compactLayout
      } else {
        defaultLayout
      }
    }
    .sheet(isPresented: $showingMonthPicker) {
      MonthYearPickerSheet(
        isPresented: $showingMonthPicker,
        currentYear: phase.year,
        currentMonth: phase.month
      ) { selectedYear, selectedMonth in
        onNavigateToMonth?(selectedYear, selectedMonth)
      }
    }
  }

  // MARK: - Compact Layout (for Add tab)

  private var compactLayout: some View {
    HStack(spacing: Spacing.xs) {
      // Previous button
      pillNavigationButton(icon: previousIcon, action: onPrevious)

      // Month and Year - vertically stacked, centered, takes available space
      // Shows full year when space allows, truncates to 2 digits if needed
      ViewThatFits(in: .horizontal) {
        // Try full year first
        compactMonthYearLabel(yearText: String(year))
        // Fall back to short year if needed
        compactMonthYearLabel(yearText: shortYear)
      }
      .frame(maxWidth: .infinity)
      .id("month-\(phase.id)")
      .transition(textTransition)
      .scaleEffect(monthScale)
      .animation(
        reduceMotion
          ? nil : .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
        value: phase.id
      )
      .highPriorityGesture(
        LongPressGesture(minimumDuration: 0.35)
          .onEnded { _ in
            longPressHaptic.impactOccurred()
            jumpToCurrentMonth()
          }
      )
      .onTapGesture {
        tapHaptic.impactOccurred()
        showMonthPicker()
      }

      // Next button
      pillNavigationButton(icon: nextIcon, action: onNext)
    }
    .contentShape(Rectangle())
    .gesture(swipeGesture)
    .onAppear {
      swipeHaptic.prepare()
      tapHaptic.prepare()
      longPressHaptic.prepare()
    }
  }

  // MARK: - Default Layout (for Dashboard/Shifts)

  private var defaultLayout: some View {
    ZStack {
      // Center section: Month and Year (fills available space, text centered)
      ViewThatFits(in: .horizontal) {
        // Try full year first
        monthYearLabel(yearText: String(year))
        // Fall back to short year if needed
        monthYearLabel(yearText: shortYear)
      }
      .frame(maxWidth: .infinity)
      .padding(.horizontal, navTextSafeInset)
      .id("month-\(phase.id)")
      .transition(textTransition)
      .scaleEffect(monthScale)
      .animation(
        reduceMotion
          ? nil : .spring(response: config.springResponse, dampingFraction: config.dampingFraction),
        value: phase.id
      )
      .highPriorityGesture(
        LongPressGesture(minimumDuration: 0.35)
          .onEnded { _ in
            longPressHaptic.impactOccurred()
            jumpToCurrentMonth()
          }
      )
      .onTapGesture {
        tapHaptic.impactOccurred()
        showMonthPicker()
      }
    }
    .frame(maxWidth: .infinity)
    .overlay(alignment: .leading) {
      edgeNavigationButton(icon: previousIcon, action: onPrevious)
    }
    .overlay(alignment: .trailing) {
      edgeNavigationButton(icon: nextIcon, action: onNext)
    }
    .padding(.horizontal, Spacing.xsm)
    .padding(.vertical, Spacing.sm)
    .contentShape(Rectangle())
    .gesture(swipeGesture)
    .onAppear {
      swipeHaptic.prepare()
      tapHaptic.prepare()
      longPressHaptic.prepare()
    }
  }

  // MARK: - Shared Helpers

  /// Reusable month/year label for ViewThatFits (default layout - horizontal)
  @ViewBuilder
  private func monthYearLabel(yearText: String) -> some View {
    HStack(spacing: Spacing.xxxs) {
      Text(monthName.sentenceCased())
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)

      Text(yearText)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  /// Reusable month/year label for ViewThatFits (compact layout - vertical)
  @ViewBuilder
  private func compactMonthYearLabel(yearText: String) -> some View {
    VStack(spacing: 0) {
      Text(monthName.sentenceCased())
        .font(.tidexBodyMedium)
        .foregroundColor(.tidexTextPrimary)
        .lineLimit(1)

      Text(yearText)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  private func showMonthPicker() {
    guard !reduceMotion else {
      monthScale = 1.0
      showingMonthPicker = true
      return
    }
    // Bounce animation on tap
    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
      monthScale = 0.95
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
        monthScale = 1.0
      }
      // Show picker after bounce completes
      showingMonthPicker = true
    }
  }

  /// Jump to the current month on long press
  private func jumpToCurrentMonth() {
    // Only navigate if not already on current month
    guard !isOnCurrentMonth else { return }

    guard !reduceMotion else {
      monthScale = 1.0
      onNavigateToMonth?(currentMonth.year, currentMonth.month)
      return
    }

    // Bounce animation
    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
      monthScale = 0.95
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
        monthScale = 1.0
      }
      onNavigateToMonth?(currentMonth.year, currentMonth.month)
    }
  }

  private var swipeGesture: some Gesture {
    DragGesture(minimumDistance: 30)
      .onEnded { value in
        let horizontal = value.translation.width
        let vertical = abs(value.translation.height)

        guard abs(horizontal) > vertical else { return }

        swipeHaptic.impactOccurred()

        if horizontal > 0 {
          onPrevious()
        } else {
          onNext()
        }
      }
  }

  // MARK: - Subviews

  @ViewBuilder
  private func pillNavigationButton(icon: String, action: @escaping () -> Void) -> some View {
    Button {
      swipeHaptic.impactOccurred()
      action()
    } label: {
      Image(systemName: icon)
        .font(.system(size: navIconSize, weight: .semibold))
        .foregroundColor(.tidexBlue)
        .frame(width: navPillVisualSize, height: navPillVisualSize)
        .background(Color.tidexBlue.opacity(0.1))
        .clipShape(Circle())
        .frame(width: navTapTargetSize, height: navTapTargetSize)
        .contentShape(Rectangle())
    }
    // Navigation is always enabled - data loading happens in background
    // Visual feedback via subtle opacity when loading
    .opacity(isLoading ? 0.7 : 1.0)
    .buttonRepeatBehavior(.enabled)
  }

  @ViewBuilder
  private func edgeNavigationButton(icon: String, action: @escaping () -> Void) -> some View {
    Button {
      swipeHaptic.impactOccurred()
      action()
    } label: {
      Image(systemName: icon)
        .font(.system(size: navIconSize, weight: .semibold))
        .foregroundColor(.tidexBlue)
        .frame(width: navTapTargetSize, height: navTapTargetSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isLoading ? 0.7 : 1.0)
    .buttonRepeatBehavior(.enabled)
  }

  // MARK: - Transitions

  private var textTransition: AnyTransition {
    if reduceMotion {
      return .opacity
    }
    let direction = phase.direction
    let base: CGFloat = direction == .next ? config.textOffset : -config.textOffset
    let offset: CGFloat = layoutDirection == .rightToLeft ? -base : base

    return .asymmetric(
      insertion: .offset(x: offset).combined(with: .opacity),
      removal: .offset(x: -offset).combined(with: .opacity)
    )
  }
}

// MARK: - View Extensions

extension View {
  /// Applies a card transition animation for month changes
  /// - Parameters:
  ///   - phase: The current month transition phase
  ///   - index: The card index (for staggered animation)
  ///   - config: Animation configuration
  func cardTransition(
    phase: MonthTransitionPhase,
    index: Int = 0,
    config: MonthTransitionConfig = .default
  ) -> some View {
    modifier(CardTransitionModifier(phase: phase, index: index, config: config))
  }

  /// Applies a text transition animation for month changes
  func textTransition(
    phase: MonthTransitionPhase,
    config: MonthTransitionConfig = .default
  ) -> some View {
    modifier(TextTransitionModifier(phase: phase, config: config))
  }
}

// Preview disabled - requires full app context with MonthNavigationDirection
// See MainTabView.swift for usage examples
