// MARK: - Factory from SharerShiftPreview

extension StoredFriendShift {
  /// Create from a SharerShiftPreview
  /// - Parameters:
  ///   - preview: The shift preview from the API
  ///   - currencySymbol: The user's currency symbol
  /// - Returns: A StoredFriendShift, or nil if the preview has no shift
  static func from(
    preview: SharerShiftPreview,
    currencySymbol: String?
  ) -> StoredFriendShift? {
    guard let shift = preview.shift else { return nil }

    return StoredFriendShift(
      sharerId: preview.sharerId,
      shiftId: shift.id,
      shiftDate: shift.shift_date,
      startTime: shift.start_time,
      endTime: shift.end_time,
      gross: shift.computed.gross,
      currencySymbol: currencySymbol,
      showEarnings: preview.showEarnings,
      status: preview.status?.rawValue ?? "upcoming"
    )
  }
}
