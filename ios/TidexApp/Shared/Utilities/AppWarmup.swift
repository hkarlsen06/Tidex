import SwiftUI

final class AppWarmup {
    static let shared = AppWarmup()

    private var didRun = false

    @MainActor
    func start() {
        guard !didRun else { return }
        didRun = true
        warmupFormatters()
        Task { @MainActor [weak self] in
            // Let the first frame render before prewarming offscreen SwiftUI cards.
            await Task.yield()
            self?.prewarmDashboardCards()
        }
    }

    private func warmupFormatters() {
        let now = Date()
        _ = FormatterCache.isoDateFormatter().string(from: now)
        _ = FormatterCache.iso8601Formatter().string(from: now)
        _ = FormatterCache.iso8601DateOnlyUTCFormatter().string(from: now)
        _ = FormatterCache.numberFormatter(includeDecimals: false, locale: Locale(identifier: "nb_NO")).string(from: 0)
        _ = FormatterCache.numberFormatter(includeDecimals: true, locale: Locale(identifier: "nb_NO")).string(from: 0)
        _ = FormatterCache.dayMonthFormatter(locale: .current).string(from: now)
        _ = FormatterCache.dayFormatter(locale: .current).string(from: now)
        _ = FormatterCache.monthNameFormatter(locale: .current).string(from: now)
    }

    @MainActor
    private func prewarmDashboardCards() {
        let view = DashboardCardPrewarmView()
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        controller.view.isHidden = true
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }
}

private struct DashboardCardPrewarmView: View {
    var body: some View {
        VStack(spacing: 12) {
            PayrollCard(
                payrollDate: Date(),
                label: "",
                gross: 12000,
                net: 10000,
                tax: 2000,
                taxEnabled: true,
                progress: 65,
                isLoading: false,
                prewarm: true
            )
            TotalCard(
                gross: 15000,
                net: 12500,
                completedGross: 9000,
                completedNet: 7500,
                shiftCount: 8,
                plannedCount: 3,
                percentageChange: 10,
                taxEnabled: true,
                isLoading: false,
                prewarm: true
            )
        }
        .padding()
        .userCurrency("kr")
    }
}
