import Foundation

/// Numbers for the Stats screen from `admin_get_stats_api`. The server picks the sections and
/// their items, and the app draws each item by its kind.
struct AdminStats: Decodable, Sendable {
  let sections: [Section]

  struct Section: Decodable, Identifiable, Sendable {
    let title: String
    let items: [Item]

    var id: String { title }
  }

  struct Item: Decodable, Sendable {
    let title: String?
    /// Shown as a row that expands, for numbers that are only sometimes interesting.
    let isCollapsed: Bool
    let content: Content

    enum Content: Sendable {
      /// Headline numbers in a row.
      case tiles([Tile])
      /// Weekly counts, oldest first.
      case series([Point])
      /// A breakdown. Without a total each row is a share of the sum. With a total, rows can
      /// overlap and each is a share of the total.
      case bars([Row], total: Int?)
      /// Steps in order, each a share of the first.
      case funnel([Row])
      case list([ListRow])
      /// Sign-up months, oldest first.
      case cohorts([Cohort])
      /// A kind this build doesn't know, from a newer server.
      case unknown
    }

    private enum CodingKeys: String, CodingKey {
      case kind, title, collapsed, tiles, points, rows, total
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      title = try container.decodeIfPresent(String.self, forKey: .title)
      isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
      switch try container.decode(String.self, forKey: .kind) {
      case "tiles":
        content = .tiles(try container.decode([Tile].self, forKey: .tiles))

      case "series":
        content = .series(try container.decode([Point].self, forKey: .points))

      case "bars":
        content = .bars(
          try container.decode([Row].self, forKey: .rows),
          total: try container.decodeIfPresent(Int.self, forKey: .total))

      case "funnel":
        content = .funnel(try container.decode([Row].self, forKey: .rows))

      case "list":
        content = .list(try container.decode([ListRow].self, forKey: .rows))

      case "cohorts":
        content = .cohorts(try container.decode([Cohort].self, forKey: .rows))

      default:
        content = .unknown
      }
    }
  }

  struct Tile: Decodable, Identifiable, Sendable {
    let label: String
    let value: String
    let caption: String?
    /// From 0 to 1 when the value is a share, drawn as a ring.
    let progress: Double?

    var id: String { label }
  }

  struct Point: Decodable, Identifiable, Sendable {
    /// The Monday that starts the week, a Postgres date.
    let date: String
    let value: Int

    var id: String { date }
    var week: Date? { adminDay(date) }
  }

  struct Row: Decodable, Identifiable, Sendable {
    let label: String
    let value: Int

    var id: String { label }
  }

  struct ListRow: Decodable, Identifiable, Sendable {
    let label: String
    let value: String
    let detail: String?

    var id: String { label }
  }

  /// Accounts made in one month, and how many of them logged a shift and are active now.
  struct Cohort: Decodable, Identifiable, Sendable {
    let label: String
    let total: Int
    let logged: Int
    let active: Int

    var id: String { label }
  }
}
