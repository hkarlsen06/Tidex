import Foundation
import SwiftUI

// MARK: - Month Limit Paywall

/// Paywall presented when free tier users try to add shifts to a new month
/// Offers two options: start Pro, or delete shifts in other months.
struct MonthLimitSheet: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var viewModel = PaywallViewModel()

  /// Existing months that have shifts (for display and deletion)
  let existingMonths: Set<DateComponents>

  /// Target month the user is trying to add shifts to
  let targetMonth: DateComponents

  /// Callback when user chooses to delete shifts in other months
  let onDeleteShifts: () async -> Bool

  /// Callback when deletion completes successfully and user wants to proceed
  let onDeleteComplete: () -> Void

  /// Callback when user upgrades successfully - auto-retry the action
  let onUpgradeComplete: () -> Void

  @State private var showDeleteSection = false
  @State private var showConfirmDelete = false
  @State private var isDeleting = false
  @State private var error: String?

  var body: some View {
    TrialPaywallScaffold(
      viewModel: viewModel,
      isAlternativeBusy: isDeleting,
      onStartSubscription: { product in
        Task {
          await viewModel.purchase(product)
        }
      }
    ) {
      deleteSection
    }
    .task {
      await viewModel.loadProducts()
    }
    .onChange(of: viewModel.purchaseSucceeded) { _, succeeded in
      if succeeded {
        dismiss()
        onUpgradeComplete()
      }
    }
  }

  // MARK: - Delete Section

  @ViewBuilder
  private var deleteSection: some View {
    if !showDeleteSection {
      // Collapsed state - subtle text button
      Button(action: {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showDeleteSection = true }
      }) {
        HStack(spacing: Spacing.xxxs) {
          Text(.monthLimitDeleteShiftsLink)
            .font(.tidexLabel)

          Image(systemName: "chevron.down")
            .font(.tidexCaptionStrong)
        }
        .foregroundStyle(Color.tidexTextMuted)
      }
      .disabled(isDeleting)
    } else {
      // Expanded delete section
      VStack(spacing: Spacing.md) {
        // Header with collapse button
        HStack(alignment: .top, spacing: Spacing.sm) {
          ZStack {
            Circle()
              .fill(Color.tidexTextMuted.opacity(0.1))
              .frame(width: 40, height: 40)

            Image(systemName: "trash")
              .font(.tidexBodyMedium)
              .foregroundStyle(Color.tidexTextMuted)
          }

          VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(.monthLimitDeleteTitle)
              .font(.tidexLabelStrong)
              .foregroundStyle(Color.tidexTextPrimary)

            Text(deleteExplanationText)
              .font(.tidexFootnote)
              .foregroundStyle(Color.tidexTextSecondary)
              .lineSpacing(2)
          }

          Spacer()

          // Collapse button
          Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
              showDeleteSection = false
              showConfirmDelete = false
            }
          }) {
            Image(systemName: "chevron.up")
              .font(.tidexCaptionStrong)
              .foregroundStyle(Color.tidexTextMuted)
              .frame(width: 28, height: 28)
              .background(Color.tidexTextMuted.opacity(0.1))
              .clipShape(Circle())
              .contentShape(Rectangle())
              .frame(minWidth: 44, minHeight: 44)
          }
        }

        if !showConfirmDelete {
          // Initial delete button
          Button(action: { withAnimation(.spring(response: 0.3)) { showConfirmDelete = true } }) {
            HStack(spacing: Spacing.xxxs) {
              Image(systemName: "trash")
                .font(.tidexLabel)

              Text(.monthLimitDeleteButton)
                .font(.tidexLabel)
            }
            .frame(maxWidth: .infinity)
          }
          .frame(height: 48)
          .foregroundStyle(Color.tidexError)
          .background(Color.tidexError.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
              .strokeBorder(Color.tidexError.opacity(0.2), lineWidth: 1)
          )
          .disabled(isDeleting)
        } else {
          // Confirmation state
          confirmDeleteSection
        }

        // Error display
        if let error {
          HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.tidexSubheadline)
              .foregroundStyle(Color.tidexError)

            Text(error)
              .font(.tidexFootnoteMedium)
              .foregroundStyle(Color.tidexError)
          }
          .padding(Spacing.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.tidexError.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        }
      }
      .padding(Spacing.md)
      .background(Color.tidexSurfaceSecondary.opacity(0.4))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
          .strokeBorder(Color.tidexBorder.opacity(0.5), lineWidth: 1)
      )
    }
  }

  // MARK: - Confirm Delete Section

  private var confirmDeleteSection: some View {
    VStack(spacing: Spacing.sm) {
      // Warning message
      HStack(alignment: .top, spacing: Spacing.xs) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.tidexSubheadline)
          .foregroundStyle(Color.tidexError)

        Text(confirmDeleteMessage)
          .font(.tidexFootnoteMedium)
          .foregroundStyle(Color.tidexError)
          .lineSpacing(2)
      }
      .padding(Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.tidexError.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

      // Action buttons
      HStack(spacing: Spacing.xs) {
        // Cancel
        Button(action: { withAnimation(.spring(response: 0.3)) { showConfirmDelete = false } }) {
          Text(.monthLimitCancelDelete)
            .font(.tidexLabelStrong)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 44)
        .foregroundStyle(Color.tidexTextSecondary)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .disabled(isDeleting)

        // Confirm delete
        Button(action: handleDeleteConfirm) {
          if isDeleting {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnDanger))
              .frame(maxWidth: .infinity)
          } else {
            Text(confirmDeleteButtonText)
              .font(.tidexLabelStrong)
              .frame(maxWidth: .infinity)
          }
        }
        .frame(height: 44)
        .foregroundStyle(Color.tidexTextOnDanger)
        .background(Color.tidexError)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .disabled(isDeleting)
      }
    }
  }

  // MARK: - Computed Properties

  /// Months that will be deleted (existing months minus target month)
  private var monthsToDelete: [DateComponents] {
    existingMonths.filter { $0 != targetMonth }.sorted {
      guard let y1 = $0.year, let m1 = $0.month,
        let y2 = $1.year, let m2 = $1.month
      else { return false }
      return (y1, m1) < (y2, m2)
    }
  }

  private var deleteCount: Int {
    monthsToDelete.count
  }

  private var formattedTargetMonth: String {
    formatMonth(targetMonth)
  }

  private var formattedOtherMonths: String {
    monthsToDelete.map { formatMonth($0) }.joined(separator: ", ")
  }

  private var deleteExplanationText: String {
    String(localized: .monthLimitDeleteExplanation(formattedTargetMonth, formattedOtherMonths))
  }

  private var confirmDeleteMessage: String {
    String(localized: .monthLimitConfirmDeleteMessage(formattedOtherMonths))
  }

  private var confirmDeleteButtonText: String {
    if deleteCount == 1 {
      return String(localized: .monthLimitConfirmDeleteButton(deleteCount))
    }
    return String(localized: .monthLimitConfirmDeleteButtonPlural(deleteCount))
  }

  // MARK: - Helpers

  private func formatMonth(_ components: DateComponents) -> String {
    guard let year = components.year, let month = components.month else { return "" }

    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"

    var dateComponents = DateComponents()
    dateComponents.year = year
    dateComponents.month = month
    dateComponents.day = 1

    guard let date = Calendar.current.date(from: dateComponents) else { return "" }
    return formatter.string(from: date)
  }

  // MARK: - Actions

  private func handleDeleteConfirm() {
    isDeleting = true
    error = nil

    Task {
      let success = await onDeleteShifts()

      await MainActor.run {
        isDeleting = false

        if success {
          // Dismiss sheet and notify parent
          dismiss()
          onDeleteComplete()
        } else {
          error = String(localized: .monthLimitCouldNotDeleteShifts)
        }
      }
    }
  }
}

// MARK: - Preview

#Preview {
  MonthLimitSheet(
    existingMonths: [
      DateComponents(year: 2_025, month: 1),
      DateComponents(year: 2_025, month: 2),
    ],
    targetMonth: DateComponents(year: 2_025, month: 3),
    onDeleteShifts: { true },
    onDeleteComplete: {},
    onUpgradeComplete: {}
  )
}
