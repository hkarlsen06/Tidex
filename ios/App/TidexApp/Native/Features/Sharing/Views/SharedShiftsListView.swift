import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SharedShiftsListView")

/// List of shared shifts from a specific sharer for the selected month
struct SharedShiftsListView: View {
    let sharer: SharedUser
    let shifts: [ShiftWithComputations]
    let year: Int
    let month: Int
    let isLoading: Bool

    /// Dates to highlight from notification deeplink
    var highlightDates: Set<String> = []

    /// Shift IDs to highlight from notification deeplink (more precise than dates)
    var highlightShiftIds: Set<String> = []

        @Environment(\.userCurrency) private var currency

    // Sheet state for shift details (using item-based presentation to fix first-tap bug)
    @State private var selectedShift: ShiftWithComputations?

    // Screenshot bubble state
    @State private var showScreenshotBubble = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if isLoading && shifts.isEmpty {
                    loadingState
                } else {
                    // Center the calendar vertically like in ShiftsView
                    VStack {
                        Spacer()
                        SharedShiftsCalendarView(
                            shifts: shifts,
                            year: year,
                            month: month,
                            currency: currency,
                            showEarnings: sharer.showEarnings,
                            highlightDates: highlightDates,
                            highlightShiftIds: highlightShiftIds,
                            onShiftTapped: { shift in
                                selectedShift = shift
                            }
                        )
                        Spacer()
                    }
                }

                // Screenshot bubble overlay
                if showScreenshotBubble {
                    VStack {
                        screenshotBubble
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                        Spacer()
                    }
                    .padding(.top, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Using .sheet(item:) guarantees data availability when sheet presents
        .sheet(item: $selectedShift) { shift in
            ShiftDetailsSheet(shift: shift, onDelete: nil)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Detect screenshots and notify the sharer
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            Task {
                await reportScreenshot()
            }
        }
    }

    // MARK: - Screenshot Detection

    /// Reports to the sharer that their shifts were screenshotted
    private func reportScreenshot() async {
        logger.info("Screenshot detected while viewing \(sharer.firstName ?? "friend")'s shifts")

        // Show the bubble immediately
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showScreenshotBubble = true
        }

        // Auto-hide after 2 seconds
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) {
                showScreenshotBubble = false
            }
        }

        do {
            try await ScreenshotNotificationService.shared.reportScreenshot(sharerId: sharer.id)
            logger.info("Screenshot notification sent successfully")
        } catch {
            // Silently fail - don't interrupt user experience for notification failures
            logger.error("Failed to report screenshot: \(error.localizedDescription)")
        }
    }

    /// Screenshot notification bubble (matches SyncStatusIndicator styling)
    private var screenshotBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            Text(.sharingScreenshotTaken)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(.sharingLoadingShifts)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
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
        year: 2025,
        month: 1,
        isLoading: false
    )
    .background(Color.tidexBackground)
    .environment(\.userCurrency, "kr")
}
