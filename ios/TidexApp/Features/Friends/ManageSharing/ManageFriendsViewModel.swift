import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ManageSharingViewModel")

// MARK: - Manage Sharing View Model

/// ViewModel for the sharing management modal
/// Handles fetching friends, optimistic updates, and management actions
@MainActor
final class ManageSharingViewModel: ObservableObject {

  // MARK: - Dependencies

  private let sharingService: SharingService

  // MARK: - Published State

  /// All friends (optimistic state for immediate UI updates)
  @Published private(set) var friends: [Friend] = []

  /// Share capacity based on subscription tier
  @Published private(set) var capacity: ShareCapacity = ShareCapacity(
    canAdd: true, currentCount: 0, limit: 5)

  /// Loading state for initial data fetch
  @Published private(set) var isLoading = false

  /// ID of friend currently being acted upon (for per-row loading states)
  @Published private(set) var actionInProgress: String?

  /// Error message to display
  @Published var errorMessage: String?

  // MARK: - Add Friend Form State

  @Published var isAddFormExpanded = false
  @Published var addIdentifier = ""
  @Published var addShowEarnings = false
  @Published var isAdding = false
  @Published var addError: String?

  // MARK: - Computed Properties

  /// Friends where both users share with each other
  var mutualFriends: [Friend] {
    friends.filter { $0.isMutual }
  }

  /// Friends where only I share with them
  var outgoingOnlyFriends: [Friend] {
    friends.filter { $0.isOutgoingOnly }
  }

  /// Friends where only they share with me
  var incomingOnlyFriends: [Friend] {
    friends.filter { $0.isIncomingOnly }
  }

  /// Whether user can add more friends
  var canAddMore: Bool {
    capacity.canAdd
  }

  /// Capacity display string (e.g., "2/5 delinger")
  var capacityDisplay: String {
    "\(capacity.currentCount)/\(capacity.limit)"
  }

  // MARK: - Initialization

  init(sharingService: SharingService? = nil) {
    self.sharingService = sharingService ?? SharingService.shared
  }

  // MARK: - Data Loading

  /// Load all friends and capacity
  func loadFriends() async {
    isLoading = true
    errorMessage = nil

    do {
      let result = try await sharingService.fetchAllFriends()
      friends = result.friends
      capacity = result.capacity
      logger.info("Loaded \(result.friends.count) friends")
    } catch is CancellationError {
      // Task was cancelled (e.g., user released pull-to-refresh early)
      // This is not an error, just log and return without showing error message
      logger.info("loadFriends was cancelled")
    } catch let error as SharingServiceError {
      // Check if the underlying error is a cancellation
      if case .networkError(let underlying) = error,
        (underlying as? URLError)?.code == .cancelled
      {
        logger.info("loadFriends network request was cancelled")
      } else {
        logger.error("Failed to load friends (SharingServiceError): \(error)")
        errorMessage = error.localizedDescription
      }
    } catch {
      logger.error("Failed to load friends: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorLoadFriends)
    }

    isLoading = false
  }

  /// Refresh friends data
  func refresh() async {
    await loadFriends()
  }

  // MARK: - Add Friend

  /// Add a new friend by email or phone
  func addFriend() async {
    // Prevent duplicate taps
    guard !isAdding else { return }

    let identifier = addIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !identifier.isEmpty else {
      addError = String(localized: .sharingErrorAddFriendEmpty)
      return
    }

    isAdding = true
    addError = nil

    do {
      try await sharingService.createShare(identifier: identifier, showEarnings: addShowEarnings)

      // Refresh to get the new friend in the list
      await loadFriends()

      // Reset form
      addIdentifier = ""
      addShowEarnings = false
      isAddFormExpanded = false

      logger.info("Added friend: \(identifier)")
    } catch let error as SharingServiceError {
      logger.error("Failed to add friend: \(error.localizedDescription)")
      addError = error.localizedDescription
    } catch {
      logger.error("Failed to add friend: \(error.localizedDescription)")
      addError = String(localized: .sharingErrorAddFriend)
    }

    isAdding = false
  }

  /// Cancel adding a friend
  func cancelAddFriend() {
    addIdentifier = ""
    addShowEarnings = false
    addError = nil
    isAddFormExpanded = false
  }

  // MARK: - Toggle Earnings Visibility

  /// Toggle whether a recipient can see my earnings
  func toggleEarnings(for friend: Friend) async {
    // Prevent duplicate taps
    guard actionInProgress == nil else { return }
    guard let iShareWith = friend.iShareWith else { return }

    let newValue = !iShareWith.showEarningsToThem

    // Optimistic update
    applyOptimisticEarningsUpdate(friendId: friend.id, showEarnings: newValue)
    actionInProgress = friend.id

    do {
      try await sharingService.toggleShareEarnings(recipientId: friend.id, showEarnings: newValue)
      logger.info("Toggled earnings for \(friend.id) to \(newValue)")
      Haptics.play(.selection)
    } catch {
      // Revert on failure
      applyOptimisticEarningsUpdate(friendId: friend.id, showEarnings: !newValue)
      logger.error("Failed to toggle earnings: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorUpdateSettings)
      Haptics.play(.error)
    }

    actionInProgress = nil
  }

  private func applyOptimisticEarningsUpdate(friendId: String, showEarnings: Bool) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }),
      let iShareWith = friends[index].iShareWith
    else { return }

    friends[index] = friends[index].with(
      iShareWith: iShareWith.with(showEarningsToThem: showEarnings))
  }

  // MARK: - Toggle Blocked Status

  /// Toggle whether a sharer is blocked (hidden from my list)
  func toggleBlocked(for friend: Friend) async {
    // Prevent duplicate taps
    guard actionInProgress == nil else { return }
    guard let sharesWithMe = friend.sharesWithMe else { return }

    let newValue = !sharesWithMe.blocked

    // Optimistic update
    applyOptimisticBlockedUpdate(friendId: friend.id, blocked: newValue)
    actionInProgress = friend.id

    do {
      if newValue {
        try await sharingService.blockSharer(ownerId: friend.id)
      } else {
        try await sharingService.unblockSharer(ownerId: friend.id)
      }
      logger.info("Toggled blocked for \(friend.id) to \(newValue)")
      Haptics.play(.selection)
    } catch {
      // Revert on failure
      applyOptimisticBlockedUpdate(friendId: friend.id, blocked: !newValue)
      logger.error("Failed to toggle blocked: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorUpdateSettings)
      Haptics.play(.error)
    }

    actionInProgress = nil
  }

  private func applyOptimisticBlockedUpdate(friendId: String, blocked: Bool) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }),
      let sharesWithMe = friends[index].sharesWithMe
    else { return }

    friends[index] = friends[index].with(sharesWithMe: sharesWithMe.with(blocked: blocked))
  }

  // MARK: - Toggle Muted Status

  /// Toggle whether notifications from a sharer are muted
  func toggleMuted(for friend: Friend) async {
    // Prevent duplicate taps
    guard actionInProgress == nil else { return }
    guard let sharesWithMe = friend.sharesWithMe else { return }

    let newValue = !sharesWithMe.isMuted

    // Optimistic update
    applyOptimisticMutedUpdate(friendId: friend.id, muted: newValue)
    actionInProgress = friend.id

    do {
      try await sharingService.toggleSharerMuted(ownerId: friend.id, muted: newValue)
      logger.info("Toggled muted for \(friend.id) to \(newValue)")
      Haptics.play(.selection)
    } catch {
      // Revert on failure
      applyOptimisticMutedUpdate(friendId: friend.id, muted: !newValue)
      logger.error("Failed to toggle muted: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorUpdateNotifications)
      Haptics.play(.error)
    }

    actionInProgress = nil
  }

  private func applyOptimisticMutedUpdate(friendId: String, muted: Bool) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }),
      let sharesWithMe = friends[index].sharesWithMe
    else { return }

    let newFrequency: NotificationFrequency = muted ? .muted : .instant
    friends[index] = friends[index].with(
      sharesWithMe: sharesWithMe.with(notificationFrequency: newFrequency))
  }

  // MARK: - Toggle Owner Muted Status

  /// Toggle whether the current user sends notifications to a specific viewer about shift changes
  func toggleOwnerMuted(for friend: Friend) async {
    guard actionInProgress == nil else { return }
    guard let iShareWith = friend.iShareWith else { return }

    let newValue = !iShareWith.ownerMuted

    // Optimistic update
    applyOptimisticOwnerMutedUpdate(friendId: friend.id, ownerMuted: newValue)
    actionInProgress = friend.id

    do {
      try await sharingService.toggleOwnerMuted(viewerId: friend.id, ownerMuted: newValue)
      logger.info("Toggled owner_muted for \(friend.id) to \(newValue)")
      Haptics.play(.selection)
    } catch {
      // Revert on failure
      applyOptimisticOwnerMutedUpdate(friendId: friend.id, ownerMuted: !newValue)
      logger.error("Failed to toggle owner_muted: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorUpdateNotifications)
      Haptics.play(.error)
    }

    actionInProgress = nil
  }

  private func applyOptimisticOwnerMutedUpdate(friendId: String, ownerMuted: Bool) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }),
      let iShareWith = friends[index].iShareWith
    else { return }

    friends[index] = friends[index].with(
      iShareWith: iShareWith.with(ownerMuted: ownerMuted))
  }

  // MARK: - Remove Share

  /// Remove my share with someone (revoke their access to my shifts)
  func removeShare(for friend: Friend) async {
    // Prevent duplicate taps
    guard actionInProgress == nil else { return }
    guard friend.iShareWith != nil else { return }

    // Optimistic update: remove iShareWith
    let originalFriend = friend
    applyOptimisticRemoveShare(friendId: friend.id)
    actionInProgress = friend.id

    do {
      try await sharingService.removeShare(recipientId: friend.id)
      logger.info("Removed share with \(friend.id)")
      Haptics.play(.success)
    } catch {
      // Revert on failure
      revertOptimisticRemove(originalFriend: originalFriend)
      logger.error("Failed to remove share: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorRemoveShare)
      Haptics.play(.error)
    }

    actionInProgress = nil
  }

  private func applyOptimisticRemoveShare(friendId: String) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }) else { return }

    let friend = friends[index]

    // If they also share with me, just remove iShareWith
    if friend.sharesWithMe != nil {
      friends[index] = friend.with(iShareWith: nil)
    } else {
      // Otherwise remove the friend entirely
      friends.remove(at: index)
    }
  }

  // MARK: - Remove Sharer

  /// Remove someone from my friends list (delete their share with me)
  func removeSharer(for friend: Friend) async {
    // Prevent duplicate taps
    guard actionInProgress == nil else { return }
    guard friend.sharesWithMe != nil else { return }

    // Optimistic update: remove sharesWithMe
    let originalFriend = friend
    applyOptimisticRemoveSharer(friendId: friend.id)
    actionInProgress = friend.id

    do {
      try await sharingService.removeSharer(ownerId: friend.id)
      logger.info("Removed sharer \(friend.id)")
      Haptics.play(.success)
    } catch {
      // Revert on failure
      revertOptimisticRemove(originalFriend: originalFriend)
      logger.error("Failed to remove sharer: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorRemovePerson)
      Haptics.play(.error)
    }

    actionInProgress = nil
  }

  private func applyOptimisticRemoveSharer(friendId: String) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }) else { return }

    let friend = friends[index]

    // If I also share with them, just remove sharesWithMe
    if friend.iShareWith != nil {
      friends[index] = friend.with(sharesWithMe: nil)
    } else {
      // Otherwise remove the friend entirely
      friends.remove(at: index)
    }
  }

  private func revertOptimisticRemove(originalFriend: Friend) {
    // Check if friend still exists
    if let index = friends.firstIndex(where: { $0.id == originalFriend.id }) {
      friends[index] = originalFriend
    } else {
      // Re-add the friend
      friends.append(originalFriend)
      // Re-sort alphabetically
      friends.sort { a, b in
        let aName = (a.firstName ?? a.email ?? a.phone ?? "").lowercased()
        let bName = (b.firstName ?? b.email ?? b.phone ?? "").lowercased()
        return aName.localizedCompare(bName) == .orderedAscending
      }
    }
  }

  // MARK: - Share Back

  /// Share my shifts back with someone who shares with me
  func shareBack(with friend: Friend) async {
    // Prevent duplicate taps
    guard actionInProgress == nil else { return }
    guard friend.sharesWithMe != nil, friend.iShareWith == nil else { return }

    // Optimistic update: add iShareWith
    let originalFriend = friend
    applyOptimisticShareBack(friendId: friend.id)
    actionInProgress = friend.id

    do {
      try await sharingService.shareBack(recipientId: friend.id)
      logger.info("Shared back with \(friend.id)")
    } catch {
      // Revert on failure
      revertOptimisticShareBack(originalFriend: originalFriend)
      logger.error("Failed to share back: \(error.localizedDescription)")
      errorMessage = String(localized: .sharingErrorShareBack)
    }

    actionInProgress = nil
  }

  private func applyOptimisticShareBack(friendId: String) {
    guard let index = friends.firstIndex(where: { $0.id == friendId }) else { return }

    let newIShareWith = Friend.IShareWith(
      showEarningsToThem: false,
      sharedAt: ISO8601DateFormatter().string(from: Date())
    )

    friends[index] = friends[index].with(iShareWith: newIShareWith)
  }

  private func revertOptimisticShareBack(originalFriend: Friend) {
    guard let index = friends.firstIndex(where: { $0.id == originalFriend.id }) else { return }
    friends[index] = originalFriend
  }

  // MARK: - Callbacks

  /// Callback for when visibility changes (block/unblock) to trigger sharer list refresh
  var onVisibilityChange: (() -> Void)?
}
