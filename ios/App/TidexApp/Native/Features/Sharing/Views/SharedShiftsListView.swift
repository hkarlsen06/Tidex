import SwiftUI

/// List of shared shifts from a specific sharer for the selected month
struct SharedShiftsListView: View {
    let sharer: SharedUser
    let shifts: [ShiftWithComputations]
    let totalHours: Double
    let shiftCount: Int
    let year: Int
    let month: Int
    let isLoading: Bool
    let lastCacheTime: Date?

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    // Sheet state for shift details
    @State private var selectedShift: ShiftWithComputations?
    @State private var showingShiftDetails = false

    // Timer for updating relative time
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var today: String {
        todayISO()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary card
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                // Calendar view
                if isLoading && shifts.isEmpty {
                    loadingState
                } else {
                    SharedShiftsCalendarView(
                        shifts: shifts,
                        year: year,
                        month: month,
                        currency: currency,
                        showEarnings: sharer.showEarnings,
                        onShiftTapped: { shift in
                            selectedShift = shift
                            showingShiftDetails = true
                        }
                    )
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showingShiftDetails) {
            if let shift = selectedShift {
                ShiftDetailsSheet(shift: shift, onDelete: nil)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        HStack(spacing: 20) {
            // Shift count
            statItem(
                value: "\(shiftCount)",
                label: localization.string("sharing.shifts")
            )

            Divider()
                .frame(height: 32)

            // Total hours
            statItem(
                value: formatHours(totalHours),
                label: localization.string("sharing.hours")
            )

            Divider()
                .frame(height: 32)

            // Last synced
            syncStatusItem
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tidexSurfacePrimary)
        )
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.tidexTextPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    /// Sync status item showing time since last sync
    private var syncStatusItem: some View {
        VStack(spacing: 2) {
            if let cacheTime = lastCacheTime {
                // Calculate time since sync using currentTime for live updates
                let timeSinceSync = formatTimeSinceSync(from: cacheTime, to: currentTime)
                Text(timeSinceSync)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.tidexTextMuted)
            }
            Text(localization.string("sharing.synced"))
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(localization.string("sharing.loadingShifts"))
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Formatting

    private func formatHours(_ hours: Double) -> String {
        let hoursLabel = localization.currentLocale == .norwegian ? "t" : "h"
        if hours == floor(hours) {
            return String(format: "%.0f %@", hours, hoursLabel)
        }
        return String(format: "%.1f %@", hours, hoursLabel)
    }

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }

    /// Format time since sync in a compact way
    /// Shows: "Nå" (< 5s), "Xs" (< 60s), "Xm" (< 60m), "Xt" (hours)
    private func formatTimeSinceSync(from startDate: Date, to endDate: Date) -> String {
        let seconds = Int(endDate.timeIntervalSince(startDate))

        if seconds < 5 {
            return localization.currentLocale == .norwegian ? "Nå" : "Now"
        } else if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m"
        } else {
            let hours = seconds / 3600
            let hoursLabel = localization.currentLocale == .norwegian ? "t" : "h"
            return "\(hours)\(hoursLabel)"
        }
    }
}

#Preview {
    SharedShiftsListView(
        sharer: SharedUser(
            id: "1",
            email: "john@example.com",
            phone: nil,
            firstName: "John Doe",
            profilePictureUrl: nil,
            oauthAvatarUrl: nil,
            sharedAt: "2025-01-01",
            showEarnings: true,
            blocked: false
        ),
        shifts: [],
        totalHours: 32.5,
        shiftCount: 5,
        year: 2025,
        month: 1,
        isLoading: false,
        lastCacheTime: Date().addingTimeInterval(-125)  // 2 minutes ago
    )
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
    .environment(\.userCurrency, "kr")
}
