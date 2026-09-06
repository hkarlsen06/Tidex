import XCTest

@testable import Tidex

@MainActor
final class StatsServiceUserIsolationTests: XCTestCase {
  private enum ResolutionError: Error {
    case oldAccount
    case newAccount
  }

  func testClearingCacheInvalidatesAnUnfinishedAccountResolution() async throws {
    let started = expectation(description: "Account resolution started")
    var resolution: CheckedContinuation<String, Error>?
    let service = StatsService(userIdProvider: {
      try await withCheckedThrowingContinuation {
        resolution = $0
        started.fulfill()
      }
    })
    let load = Task { try await service.computeStats(year: 2_026, month: 9) }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertTrue(service.isLoading)

    service.clearCache()
    XCTAssertFalse(service.isLoading)
    try XCTUnwrap(resolution).resume(returning: "previous-account")

    do {
      _ = try await load.value
      XCTFail("A cleared account must not finish its stats request")
    } catch is CancellationError {
      // Clearing the cache invalidates work even when its caller was not cancelled.
    }
    XCTAssertNil(service.stats)
    XCTAssertNil(service.statsUserId)
    XCTAssertNil(service.error)
  }

  func testOlderRequestCannotFinishLoadingOrPublishAnErrorForANewerRequest() async throws {
    let oldStarted = expectation(description: "Old account resolution started")
    let newStarted = expectation(description: "New account resolution started")
    var resolutions: [CheckedContinuation<String, Error>] = []
    let service = StatsService(userIdProvider: {
      try await withCheckedThrowingContinuation {
        resolutions.append($0)
        if resolutions.count == 1 {
          oldStarted.fulfill()
        } else {
          newStarted.fulfill()
        }
      }
    })
    let oldLoad = Task { try await service.computeStats(year: 2_026, month: 8) }
    await fulfillment(of: [oldStarted], timeout: 2)
    let newLoad = Task { try await service.computeStats(year: 2_026, month: 9) }
    await fulfillment(of: [newStarted], timeout: 2)
    guard resolutions.count == 2 else {
      return XCTFail("Both account resolutions must start before completing either request")
    }

    resolutions[0].resume(throwing: ResolutionError.oldAccount)
    do {
      _ = try await oldLoad.value
      XCTFail("An older request must be invalidated")
    } catch is CancellationError {
      // A stale failure must not replace the current request's state.
    }
    XCTAssertTrue(service.isLoading)
    XCTAssertNil(service.error)

    resolutions[1].resume(throwing: ResolutionError.newAccount)
    do {
      _ = try await newLoad.value
      XCTFail("The current request should report its resolution failure")
    } catch let error as StatsServiceError {
      guard case .computationFailed(let underlying) = error else {
        return XCTFail("Expected the current account resolution error")
      }
      XCTAssertEqual(underlying as? ResolutionError, .newAccount)
    }
    XCTAssertFalse(service.isLoading)
    XCTAssertNotNil(service.error)

    service.clearCache()
    XCTAssertNil(service.error)
  }
}
