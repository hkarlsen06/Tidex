// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline discouraged_optional_boolean explicit_acl explicit_top_level_acl
enum ShiftCardAmountAnimationFallback {
  static func animateFrom(
    previousAmount: Double?,
    previousHasTrailingBottomContent: Bool?,
    currentHasTrailingBottomContent: Bool
  ) -> Double? {
    guard let previousHasTrailingBottomContent else { return nil }
    guard previousHasTrailingBottomContent != currentHasTrailingBottomContent else { return nil }
    return previousAmount
  }
}
