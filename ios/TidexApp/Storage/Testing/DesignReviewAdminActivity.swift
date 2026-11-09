#if DEBUG
  import SwiftUI

  struct DesignReviewAdminActivity: View {
    @State private var activeUsersQuery: AdminUserQuery?

    var body: some View {
      NavigationStack {
        List {
          AdminActiveUsersCharts(
            chart: AdminActiveUsersChart(
              hours: [.init(start: "2026-11-09T17:00:00Z", date: nil, users: 3)],
              days: [.init(start: nil, date: "2026-10-11", users: 8)])
          ) {
            activeUsersQuery = $0
          }
        }
        .navigationTitle("Admin")
        .navigationDestination(item: $activeUsersQuery) { query in
          AdminUsersView(query: query)
        }
      }
    }
  }
#endif
