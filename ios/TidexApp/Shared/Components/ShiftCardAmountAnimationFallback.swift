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
