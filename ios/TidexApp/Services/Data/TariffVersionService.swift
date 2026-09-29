import Foundation
import os.log
import Supabase

private let logger = Logger(subsystem: "com.tidex.app", category: "TariffVersionService")

// MARK: - Tariff Version Service

/// Service for fetching tariff types and versions from Supabase
/// Uses RPC functions for efficient server-side date resolution
/// Tariff data is relatively static, so aggressive caching is used.
/// The last successful fetch is also saved to disk, so lists still load offline and after a relaunch.
actor TariffVersionService {
  static let shared = TariffVersionService()

  /// Shape of the JSON file in Application Support.
  private struct DiskCache: Codable {
    var types: [TariffType]?
    var versions: [String: [TariffVersion]] = [:]
  }

  typealias FetchTypes = @Sendable () async throws -> [TariffType]
  typealias FetchVersions = @Sendable (_ tariffType: String) async throws -> [TariffVersion]
  typealias FetchVersionForDate =
    @Sendable (_ tariffType: String, _ date: String) async throws -> TariffVersion

  // MARK: - Cache

  /// Cached tariff types
  private var cachedTypes: [TariffType]?

  /// Cached tariff versions keyed by tariff_type_id
  private var cachedVersions: [String: [TariffVersion]] = [:]

  /// Cache timestamp for types
  private var typesCacheTimestamp: Date?

  /// Cache timestamp for versions (per tariff type)
  private var versionsCacheTimestamp: [String: Date] = [:]

  /// Cache validity duration (24 hours - tariff data rarely changes)
  private let cacheValiditySeconds: TimeInterval = 24 * 60 * 60

  private let cacheURL: URL?
  private let fetchTypes: FetchTypes
  private let fetchVersions: FetchVersions
  private let fetchVersionForDate: FetchVersionForDate

  init(
    cacheURL: URL? = TariffVersionService.defaultCacheURL,
    fetchTypes: @escaping FetchTypes = TariffVersionService.remoteTypes,
    fetchVersions: @escaping FetchVersions = TariffVersionService.remoteVersions,
    fetchVersionForDate: @escaping FetchVersionForDate = TariffVersionService.remoteVersionForDate
  ) {
    self.cacheURL = cacheURL
    self.fetchTypes = fetchTypes
    self.fetchVersions = fetchVersions
    self.fetchVersionForDate = fetchVersionForDate

    // Disk data has no timestamp, so it counts as expired: the next call tries the network
    // first and only falls back to the disk copy when that fails.
    if let cacheURL,
      let data = try? Data(contentsOf: cacheURL),
      let disk = try? JSONDecoder().decode(DiskCache.self, from: data)
    {
      cachedTypes = disk.types
      cachedVersions = disk.versions
    }
  }

  // MARK: - Remote

  nonisolated static let defaultCacheURL: URL? = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
    .appendingPathComponent("TariffCache.json")

  nonisolated static let remoteTypes: FetchTypes = {
    try await supabase.rpc("get_tariff_types").execute().value
  }

  nonisolated static let remoteVersions: FetchVersions = { tariffType in
    try await supabase
      .rpc("get_tariff_versions", params: ["p_tariff_type": tariffType])
      .execute()
      .value
  }

  nonisolated static let remoteVersionForDate: FetchVersionForDate = { tariffType, date in
    // The RPC returns a single row or null
    try await supabase
      .rpc(
        "get_tariff_version_for_date",
        params: ["p_tariff_type": tariffType, "p_target_date": date]
      )
      .single()
      .execute()
      .value
  }

  private func persist() {
    guard let cacheURL else { return }
    do {
      try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(DiskCache(types: cachedTypes, versions: cachedVersions))
      try data.write(to: cacheURL, options: .atomic)
    } catch {
      logger.error("Failed to save tariff cache: \(error.localizedDescription)")
    }
  }

  // MARK: - Public API

  /// Fetch all available tariff types
  /// - Returns: Array of tariff types
  /// - Throws: Error if the RPC call fails
  func getTariffTypes() async throws -> [TariffType] {
    // Check cache
    if let cached = cachedTypes,
      let timestamp = typesCacheTimestamp,
      Date().timeIntervalSince(timestamp) < cacheValiditySeconds
    {
      logger.debug("Returning cached tariff types (\(cached.count) items)")
      return cached
    }

    logger.info("Fetching tariff types from server")

    do {
      let types = try await fetchTypes()

      // Update cache
      cachedTypes = types
      typesCacheTimestamp = Date()
      persist()

      logger.info("Fetched \(types.count) tariff types")
      return types
    } catch {
      logger.error("Failed to fetch tariff types: \(error.localizedDescription)")

      // Return cached data if available, even if expired
      if let cached = cachedTypes {
        logger.warning("Returning stale cached tariff types due to error")
        return cached
      }

      throw error
    }
  }

  /// Fetch all versions for a specific tariff type
  /// - Parameter tariffType: The tariff type ID (e.g., "hk_retail")
  /// - Returns: Array of tariff versions, ordered by effective_date descending
  /// - Throws: Error if the RPC call fails
  func getTariffVersions(tariffType: String) async throws -> [TariffVersion] {
    // Check cache
    if let cached = cachedVersions[tariffType],
      let timestamp = versionsCacheTimestamp[tariffType],
      Date().timeIntervalSince(timestamp) < cacheValiditySeconds
    {
      logger.debug("Returning cached tariff versions for \(tariffType) (\(cached.count) items)")
      return cached
    }

    logger.info("Fetching tariff versions for \(tariffType) from server")

    do {
      let versions = try await fetchVersions(tariffType)

      // Update cache
      cachedVersions[tariffType] = versions
      versionsCacheTimestamp[tariffType] = Date()
      persist()

      logger.info("Fetched \(versions.count) tariff versions for \(tariffType)")
      return versions
    } catch {
      logger.error(
        "Failed to fetch tariff versions for \(tariffType): \(error.localizedDescription)")

      // Return cached data if available, even if expired
      if let cached = cachedVersions[tariffType] {
        logger.warning("Returning stale cached tariff versions for \(tariffType) due to error")
        return cached
      }

      throw error
    }
  }

  /// Fetch the applicable tariff version for a specific date
  /// Uses server-side RPC for efficient date resolution
  /// - Parameters:
  ///   - tariffType: The tariff type ID (e.g., "hk_retail")
  ///   - date: ISO date string (YYYY-MM-DD) to find the version for
  /// - Returns: The applicable tariff version, or nil if none found
  /// - Throws: Error if the RPC call fails
  func getTariffVersionForDate(tariffType: String, date: String) async throws -> TariffVersion? {
    logger.info("Fetching tariff version for \(tariffType) at date \(date)")

    do {
      let version = try await fetchVersionForDate(tariffType, date)

      logger.info(
        "Found tariff version \(version.id) (effective \(version.effective_date)) for date \(date)")

      // Offline lookups resolve the date against the full version list, so make sure it is saved.
      if cachedVersions[tariffType] == nil {
        Task { _ = try? await getTariffVersions(tariffType: tariffType) }
      }
      return version
    } catch {
      // Check if error is "no rows returned" - return nil instead of throwing
      if let postgrestError = error as? PostgrestError,
        postgrestError.code == "PGRST116"
      {
        logger.info("No tariff version found for \(tariffType) at date \(date)")
        return nil
      }

      logger.error("Failed to fetch tariff version for date: \(error.localizedDescription)")

      // Resolve the date from the saved version list. ISO dates compare correctly as strings.
      if let cached = cachedVersions[tariffType] {
        logger.warning("Resolving tariff version for \(date) from saved versions due to error")
        return cached.filter { $0.effective_date <= date }.max { $0.effective_date < $1.effective_date }
      }

      throw error
    }
  }

  /// Get the latest (most recent) tariff version for a tariff type
  /// - Parameter tariffType: The tariff type ID (e.g., "hk_retail")
  /// - Returns: The most recent tariff version, or nil if none found
  /// - Throws: Error if the fetch fails
  func getLatestTariffVersion(tariffType: String) async throws -> TariffVersion? {
    let versions = try await getTariffVersions(tariffType: tariffType)

    // Versions are ordered by effective_date descending, so first is latest
    guard let latest = versions.first else {
      logger.info("No tariff versions found for \(tariffType)")
      return nil
    }

    logger.debug(
      "Latest tariff version for \(tariffType): \(latest.id) (effective \(latest.effective_date))")
    return latest
  }

  /// Get the default tariff type
  /// - Returns: The default tariff type, or nil if none found
  /// - Throws: Error if the fetch fails
  func getDefaultTariffType() async throws -> TariffType? {
    let types = try await getTariffTypes()
    let defaultType: TariffType? = types.first(where: \.is_default)

    if let defaultType {
      logger.debug("Default tariff type: \(defaultType.id)")
    } else {
      logger.warning("No default tariff type found")
    }

    return defaultType
  }

  // MARK: - Cache Management

  /// Clear all cached data
  /// Call this when user logs out or when you need to force a refresh
  func clearCache() {
    cachedTypes = nil
    cachedVersions.removeAll()
    typesCacheTimestamp = nil
    versionsCacheTimestamp.removeAll()
    persist()
    logger.info("Tariff version cache cleared")
  }

  /// Clear cached versions for a specific tariff type
  /// - Parameter tariffType: The tariff type ID to clear cache for
  func clearVersionsCache(for tariffType: String) {
    cachedVersions.removeValue(forKey: tariffType)
    versionsCacheTimestamp.removeValue(forKey: tariffType)
    persist()
    logger.debug("Cleared tariff version cache for \(tariffType)")
  }

  /// Check if the cache is valid for tariff types
  var hasValidTypesCache: Bool {
    guard let timestamp = typesCacheTimestamp else { return false }
    return Date().timeIntervalSince(timestamp) < cacheValiditySeconds
  }

  /// Check if the cache is valid for a specific tariff type's versions
  /// - Parameter tariffType: The tariff type ID to check
  func hasValidVersionsCache(for tariffType: String) -> Bool {
    guard let timestamp = versionsCacheTimestamp[tariffType] else { return false }
    return Date().timeIntervalSince(timestamp) < cacheValiditySeconds
  }
}

// MARK: - Tariff Version Service Errors

enum TariffVersionServiceError: Error, LocalizedError {
  case noVersionsFound(tariffType: String)
  case networkError(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .noVersionsFound:
      return String(localized: .settingsPayErrorNoTariffVersions)

    case .networkError(let error):
      return String(localized: .commonErrorNetwork(error.localizedDescription))
    }
  }
}
