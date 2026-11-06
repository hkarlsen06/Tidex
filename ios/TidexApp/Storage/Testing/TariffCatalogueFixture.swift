#if DEBUG
  import Foundation

  enum TariffCatalogueFixture {
    struct Catalogue: Decodable {
      let types: [TariffType]
      let versions: [TariffVersion]
    }

    static var enabled: Bool {
      ProcessInfo.processInfo.arguments.contains("-ui-testing")
        && ProcessInfo.processInfo.environment["TIDEX_TEST_TARIFFS"] == "1"
    }

    static func load() throws -> Catalogue {
      guard let url = Bundle.main.url(forResource: "TariffCatalogueFixture", withExtension: "json")
      else {
        throw CocoaError(.fileNoSuchFile)
      }
      return try JSONDecoder().decode(Catalogue.self, from: Data(contentsOf: url))
    }
  }
#endif
