import AppIntents

// Siri AI developer preview. This folder compiles only in Debug builds with Xcode 27.3,
// which has the iOS 27.3 SDK. See ios/docs/SIRI_AI_PREVIEW.md.
//
// A tool is an intent Siri's model may call by itself. The intents keep their iOS 26
// availability and gain the conformance here. The message intents follow the messages schema,
// which Siri already handles and which can't also be a tool.

@available(iOS 27.3, *)
extension AddShiftIntent: ToolIntent {}

@available(iOS 27.3, *)
extension MoveShiftIntent: ToolIntent {}

@available(iOS 27.3, *)
extension ExtendShiftIntent: ToolIntent {}

@available(iOS 27.3, *)
extension StopClockIntent: ToolIntent {}

@available(iOS 27.3, *)
extension NextShiftIntent: ToolIntent {}

@available(iOS 27.3, *)
extension EarningsIntent: ToolIntent {}

@available(iOS 27.3, *)
extension HoursWorkedIntent: ToolIntent {}

@available(iOS 27.3, *)
extension EarnedSoFarIntent: ToolIntent {}

@available(iOS 27.3, *)
extension FriendScheduleIntent: ToolIntent {}

@available(iOS 27.3, *)
extension OpenShiftIntent: ToolIntent {}

@available(iOS 27.3, *)
extension OpenJobIntent: ToolIntent {}

// For a tool parameter, Siri finds entities in Spotlight or through allEntities(), never
// through entities(matching:). Friends are not in Spotlight, so Siri reads them here.
extension FriendEntityQuery: EnumerableEntityQuery {
  @MainActor
  func allEntities() throws -> [FriendEntity] {
    try suggestedEntities()
  }
}
