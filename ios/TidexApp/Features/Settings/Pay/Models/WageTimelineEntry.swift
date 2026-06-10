import Foundation

// MARK: - Wage Timeline Entry

/// Processed timeline entry for display in the wage history timeline
/// Wraps a WageSnapshot with computed metadata for visual presentation
struct WageTimelineEntry: Identifiable {
  let id: String
  let snapshot: WageSnapshot
  let type: EntryType
  let dateRange: String
  let endDate: String?
  let changes: [WageChange]

  /// Type of timeline entry based on temporal position
  enum EntryType {
    case future  // from_date is in the future
    case current  // from_date is in the past and this is the most recent
    case past  // from_date is in the past but superseded by a newer snapshot
  }
}

// MARK: - Wage Change

/// Describes a change between consecutive snapshots
struct WageChange: Identifiable {
  let id = UUID()
  let description: String
  let type: ChangeType

  enum ChangeType {
    case wage
    case tariffLevel
    case tax
    case breaks
    case supplements
  }
}

// MARK: - Timeline Processing

/// Processes raw snapshots into timeline entries with change detection
enum WageTimelineProcessor {

  /// Process snapshots into timeline entries for display
  /// - Parameters:
  ///   - snapshots: Raw snapshots ordered by from_date DESC (most recent first)
  ///   - locale: Locale for date formatting
  /// - Returns: Timeline entries ready for display
  static func processSnapshots(
    _ snapshots: [WageSnapshot],
    locale: Locale,
    currency: String
  ) -> [WageTimelineEntry] {
    guard !snapshots.isEmpty else { return [] }

    let today = ISO8601DateFormatter.dateOnlyString(from: Date())
    var entries: [WageTimelineEntry] = []

    // Find the current entry (first snapshot where from_date <= today or baseline)
    var foundCurrent = false

    for (index, snapshot) in snapshots.enumerated() {
      let previousSnapshot = index > 0 ? snapshots[index - 1] : nil
      let nextSnapshot = index < snapshots.count - 1 ? snapshots[index + 1] : nil

      // Determine entry type
      let entryType: WageTimelineEntry.EntryType
      if let fromDate = snapshot.from_date {
        if fromDate > today {
          entryType = .future
        } else if !foundCurrent {
          entryType = .current
          foundCurrent = true
        } else {
          entryType = .past
        }
      } else {
        // Baseline (nil from_date)
        entryType = foundCurrent ? .past : .current
        if entryType == .current {
          foundCurrent = true
        }
      }

      // Calculate end date (previous snapshot's from_date - 1 day)
      let endDate = calculateEndDate(for: snapshot, previousSnapshot: previousSnapshot)

      // Format date range
      let dateRange = formatDateRange(
        fromDate: snapshot.from_date,
        endDate: endDate,
        isCurrent: entryType == .current,
        isPast: entryType == .past,
        locale: locale
      )

      // Detect changes from the next snapshot (chronologically earlier)
      let changes = detectChanges(
        current: snapshot,
        previous: nextSnapshot,
        locale: locale,
        currency: currency
      )

      entries.append(
        WageTimelineEntry(
          id: snapshot.id,
          snapshot: snapshot,
          type: entryType,
          dateRange: dateRange,
          endDate: endDate,
          changes: changes
        ))
    }

    return entries
  }

  // MARK: - Private Helpers

  /// Calculate the end date for a snapshot (one day before the next snapshot starts)
  private static func calculateEndDate(
    for _: WageSnapshot,
    previousSnapshot: WageSnapshot?
  ) -> String? {
    guard let previousFromDate = previousSnapshot?.from_date else { return nil }

    // Parse the date and subtract one day
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    guard let date = formatter.date(from: previousFromDate),
      let oneDayBefore = Calendar.current.date(byAdding: .day, value: -1, to: date)
    else {
      return nil
    }

    return formatter.string(from: oneDayBefore)
  }

  /// Format date range for display
  private static func formatDateRange(
    fromDate: String?,
    endDate: String?,
    isCurrent: Bool,
    isPast: Bool,
    locale: Locale
  ) -> String {
    let nowText = String(localized: .commonNow)

    // Baseline with no date
    guard let fromDate else {
      // If baseline has an end date and is past, show "- {endDate}"
      if let endDate, isPast {
        let formattedEnd = formatDate(endDate, locale: locale)
        return "- \(formattedEnd)"
      }
      // Otherwise show "- nå" (it's the only entry or current)
      return "- \(nowText)"
    }

    let formattedFrom = formatDate(fromDate, locale: locale)

    if isCurrent {
      return "\(formattedFrom) - \(nowText)"
    }
    if let endDate {
      let formattedEnd = formatDate(endDate, locale: locale)
      return "\(formattedFrom) - \(formattedEnd)"
    }
    return formattedFrom
  }

  /// Format a single date, hiding year if it's the current year
  private static func formatDate(_ isoDate: String, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    guard let date = formatter.date(from: isoDate) else { return isoDate }

    let calendar = Calendar.current
    let isCurrentYear =
      calendar.component(.year, from: date) == calendar.component(.year, from: Date())

    let displayFormatter = DateFormatter()
    displayFormatter.locale = locale

    // Use locale-appropriate date format
    if isCurrentYear {
      displayFormatter.setLocalizedDateFormatFromTemplate("d MMM")
    } else {
      displayFormatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
    }

    return displayFormatter.string(from: date)
  }

  /// Detect what changed between two consecutive snapshots
  private static func detectChanges(  // swiftlint:disable:this cyclomatic_complexity function_body_length
    current: WageSnapshot,
    previous: WageSnapshot?,
    locale: Locale,
    currency: String
  ) -> [WageChange] {
    guard let previous else { return [] }  // swiftlint:disable:this conditional_returns_on_newline

    var changes: [WageChange] = []

    // Wage change
    if current.hourly_wage != previous.hourly_wage {
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = 2
      formatter.maximumFractionDigits = 2
      formatter.locale = Locale(identifier: locale.identifier)

      let oldWage =
        formatter.string(from: NSNumber(value: previous.hourly_wage)) ?? "\(previous.hourly_wage)"
      let newWage =
        formatter.string(from: NSNumber(value: current.hourly_wage)) ?? "\(current.hourly_wage)"

      changes.append(
        WageChange(
          description:
            "\(formatHourlyAmount(oldWage, currency: currency)) \u{2192} \(formatHourlyAmount(newWage, currency: currency))",
          type: .wage
        ))
    }

    // Tariff level change
    if current.wage_level != previous.wage_level {
      if current.wage_level == nil, previous.wage_level != nil {
        changes.append(
          WageChange(
            description: String(localized: .timelineSwitchedToCustom),
            type: .tariffLevel
          ))
      } else if current.wage_level != nil, previous.wage_level == nil {
        changes.append(
          WageChange(
            description: String(localized: .timelineSwitchedToTariff),
            type: .tariffLevel
          ))
      } else if let currentLevel = current.wage_level, let previousLevel = previous.wage_level {
        changes.append(
          WageChange(
            description: String(
              localized: .timelineLevelChange(Int32(previousLevel), Int32(currentLevel))),
            type: .tariffLevel
          ))
      }
    }

    // Tax change
    if current.effectiveTaxEnabled != previous.effectiveTaxEnabled {
      changes.append(
        WageChange(
          description: current.effectiveTaxEnabled
            ? String(localized: .timelineTaxEnabled)
            : String(localized: .timelineTaxDisabled),
          type: .tax
        ))
    } else if current.effectiveTaxEnabled,
      current.effectiveTaxPercentage != previous.effectiveTaxPercentage
    {
      changes.append(
        WageChange(
          description: String(
            localized: .timelineTaxChange(
              FormatterCache.percentagePoints(previous.effectiveTaxPercentage),
              FormatterCache.percentagePoints(current.effectiveTaxPercentage))),
          type: .tax
        ))
    }

    // Break change
    if current.effectiveBreakEnabled != previous.effectiveBreakEnabled {
      changes.append(
        WageChange(
          description: current.effectiveBreakEnabled
            ? String(localized: .timelineBreakEnabled)
            : String(localized: .timelineBreakDisabled),
          type: .breaks
        ))
    } else if current.effectiveBreakEnabled, current.breakMethod != previous.breakMethod {
      changes.append(
        WageChange(
          description: String(localized: .timelineBreakMethodChanged),
          type: .breaks
        ))
    }

    // Supplements change
    if current.supplements.rules.count != previous.supplements.rules.count {
      let diff = current.supplements.rules.count - previous.supplements.rules.count
      if diff > 0 {
        changes.append(
          WageChange(
            description: String(localized: .timelineSupplementsAdded(Int32(diff))),
            type: .supplements
          ))
      } else {
        changes.append(
          WageChange(
            description: String(localized: .timelineSupplementsRemoved(Int32(abs(diff)))),
            type: .supplements
          ))
      }
    }

    return changes
  }

  private static func formatHourlyAmount(_ amount: String, currency: String) -> String {
    let currencyConfig = CurrencyConfig.get(currency)
    let perHour = String(localized: .commonPerHourShort)

    switch currencyConfig.display {
    case .prefix:
      return "\(currency)\(amount)\(perHour)"

    case .suffix:
      return "\(amount) \(currency)\(perHour)"
    }
  }
}

// MARK: - ISO8601 Date Helper

extension ISO8601DateFormatter {
  /// Format date as YYYY-MM-DD (date only, no time)
  static func dateOnlyString(from date: Date) -> String {
    date.toISODateString()
  }

  /// Parse YYYY-MM-DD string to Date
  static func dateFromDateOnlyString(_ string: String) -> Date? {
    Date.fromISODateString(string)
  }
}
