import AppIntents
import Foundation

struct OpenShiftIntent: OpenIntent {
  static let title: LocalizedStringResource = "assistant.openShift.title"
  static let description = IntentDescription("assistant.openShift.description")

  @Parameter(title: "assistant.shift.type", description: "assistant.openShift.target.description")
  var target: ShiftEntity

  @MainActor
  func perform() throws -> some IntentResult {
    _ = try AssistantAccess.current.requireUserId()
    AppCoordinator.shared.pendingDeepLink = .shifts(
      dates: [target.start.toISODateString()],
      shiftIds: [target.id],
      action: target.isRecurring ? .highlight : .open
    )
    return .result()
  }
}

struct OpenJobIntent: OpenIntent {
  static let title: LocalizedStringResource = "assistant.openJob.title"
  static let description = IntentDescription("assistant.openJob.description")

  @Parameter(title: "assistant.job.type", description: "assistant.openJob.target.description")
  var target: JobEntity

  @MainActor
  func perform() throws -> some IntentResult {
    _ = try AssistantAccess.current.requireUserId()
    AppCoordinator.shared.pendingDeepLink = .settings(destination: .pay(jobId: target.id))
    return .result()
  }
}
