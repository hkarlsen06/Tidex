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
    private let localization = LocalizationManager.shared

    // MARK: - Published State

    /// All friends (optimistic state for immediate UI updates)
    @Published private(set) var friends: [Friend] = []

    /// Share capacity based on subscription tier
    @Published private(set) var capacity: ShareCapacity = ShareCapacity(canAdd: true, currentCount: 0, limit: 5)

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
        } catch let error as SharingServiceError {
            logger.error("Failed to load friends (SharingServiceError): \(error)")
            // Use specific error message from service if available
            errorMessage = error.localizedDescription
        } catch {
            logger.error("Failed to load friends: \(error.localizedDescription)")
            errorMessage = localization.string("sharing.error.loadFriends")
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
        let identifier = addIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else {
            addError = localization.string("sharing.error.addFriendEmpty")
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
            addError = localization.string("sharing.error.addFriend")
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
        guard let iShareWith = friend.iShareWith else { return }

        let newValue = !iShareWith.showEarningsToThem

        // Optimistic update
        applyOptimisticEarningsUpdate(friendId: friend.id, showEarnings: newValue)
        actionInProgress = friend.id

        do {
            try await sharingService.toggleShareEarnings(recipientId: friend.id, showEarnings: newValue)
            logger.info("Toggled earnings for \(friend.id) to \(newValue)")
        } catch {
            // Revert on failure
            applyOptimisticEarningsUpdate(friendId: friend.id, showEarnings: !newValue)
            logger.error("Failed to toggle earnings: \(error.localizedDescription)")
            errorMessage = localization.string("sharing.error.updateSettings")
        }

        actionInProgress = nil
    }

    private func applyOptimisticEarningsUpdate(friendId: String, showEarnings: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == friendId }),
              let iShareWith = friends[index].iShareWith else { return }

        let updatedIShareWith = Friend.IShareWith(
            showEarningsToThem: showEarnings,
            sharedAt: iShareWith.sharedAt
        )

        friends[index] = Friend(
            id: friends[index].id,
            email: friends[index].email,
            phone: friends[index].phone,
            firstName: friends[index].firstName,
            profilePictureUrl: friends[index].profilePictureUrl,
            oauthAvatarUrl: friends[index].oauthAvatarUrl,
            sharesWithMe: friends[index].sharesWithMe,
            iShareWith: updatedIShareWith
        )
    }

    // MARK: - Toggle Blocked Status

    /// Toggle whether a sharer is blocked (hidden from my list)
    func toggleBlocked(for friend: Friend) async {
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
        } catch {
            // Revert on failure
            applyOptimisticBlockedUpdate(friendId: friend.id, blocked: !newValue)
            logger.error("Failed to toggle blocked: \(error.localizedDescription)")
            errorMessage = localization.string("sharing.error.updateSettings")
        }

        actionInProgress = nil
    }

    private func applyOptimisticBlockedUpdate(friendId: String, blocked: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == friendId }),
              let sharesWithMe = friends[index].sharesWithMe else { return }

        let updatedSharesWithMe = Friend.SharesWithMe(
            blocked: blocked,
            showEarningsToMe: sharesWithMe.showEarningsToMe,
            sharedAt: sharesWithMe.sharedAt,
            notificationFrequency: sharesWithMe.notificationFrequency
        )

        friends[index] = Friend(
            id: friends[index].id,
            email: friends[index].email,
            phone: friends[index].phone,
            firstName: friends[index].firstName,
            profilePictureUrl: friends[index].profilePictureUrl,
            oauthAvatarUrl: friends[index].oauthAvatarUrl,
            sharesWithMe: updatedSharesWithMe,
            iShareWith: friends[index].iShareWith
        )
    }

    // MARK: - Toggle Muted Status

    /// Toggle whether notifications from a sharer are muted
    func toggleMuted(for friend: Friend) async {
        guard let sharesWithMe = friend.sharesWithMe else { return }

        let newValue = !sharesWithMe.isMuted

        // Optimistic update
        applyOptimisticMutedUpdate(friendId: friend.id, muted: newValue)
        actionInProgress = friend.id

        do {
            try await sharingService.toggleSharerMuted(ownerId: friend.id, muted: newValue)
            logger.info("Toggled muted for \(friend.id) to \(newValue)")
        } catch {
            // Revert on failure
            applyOptimisticMutedUpdate(friendId: friend.id, muted: !newValue)
            logger.error("Failed to toggle muted: \(error.localizedDescription)")
            errorMessage = localization.string("sharing.error.updateNotifications")
        }

        actionInProgress = nil
    }

    private func applyOptimisticMutedUpdate(friendId: String, muted: Bool) {
        guard let index = friends.firstIndex(where: { $0.id == friendId }),
              let sharesWithMe = friends[index].sharesWithMe else { return }

        let newFrequency = muted ? "muted" : "instant"
        let updatedSharesWithMe = Friend.SharesWithMe(
            blocked: sharesWithMe.blocked,
            showEarningsToMe: sharesWithMe.showEarningsToMe,
            sharedAt: sharesWithMe.sharedAt,
            notificationFrequency: newFrequency
        )

        friends[index] = Friend(
            id: friends[index].id,
            email: friends[index].email,
            phone: friends[index].phone,
            firstName: friends[index].firstName,
            profilePictureUrl: friends[index].profilePictureUrl,
            oauthAvatarUrl: friends[index].oauthAvatarUrl,
            sharesWithMe: updatedSharesWithMe,
            iShareWith: friends[index].iShareWith
        )
    }

    // MARK: - Remove Share

    /// Remove my share with someone (revoke their access to my shifts)
    func removeShare(for friend: Friend) async {
        guard friend.iShareWith != nil else { return }

        // Optimistic update: remove iShareWith
        let originalFriend = friend
        applyOptimisticRemoveShare(friendId: friend.id)
        actionInProgress = friend.id

        do {
            try await sharingService.removeShare(recipientId: friend.id)
            logger.info("Removed share with \(friend.id)")
        } catch {
            // Revert on failure
            revertOptimisticRemove(originalFriend: originalFriend)
            logger.error("Failed to remove share: \(error.localizedDescription)")
            errorMessage = localization.string("sharing.error.removeShare")
        }

        actionInProgress = nil
    }

    private func applyOptimisticRemoveShare(friendId: String) {
        guard let index = friends.firstIndex(where: { $0.id == friendId }) else { return }

        let friend = friends[index]

        // If they also share with me, just remove iShareWith
        if friend.sharesWithMe != nil {
            friends[index] = Friend(
                id: friend.id,
                email: friend.email,
                phone: friend.phone,
                firstName: friend.firstName,
                profilePictureUrl: friend.profilePictureUrl,
                oauthAvatarUrl: friend.oauthAvatarUrl,
                sharesWithMe: friend.sharesWithMe,
                iShareWith: nil
            )
        } else {
            // Otherwise remove the friend entirely
            friends.remove(at: index)
        }
    }

    // MARK: - Remove Sharer

    /// Remove someone from my friends list (delete their share with me)
    func removeSharer(for friend: Friend) async {
        guard friend.sharesWithMe != nil else { return }

        // Optimistic update: remove sharesWithMe
        let originalFriend = friend
        applyOptimisticRemoveSharer(friendId: friend.id)
        actionInProgress = friend.id

        do {
            try await sharingService.removeSharer(ownerId: friend.id)
            logger.info("Removed sharer \(friend.id)")
        } catch {
            // Revert on failure
            revertOptimisticRemove(originalFriend: originalFriend)
            logger.error("Failed to remove sharer: \(error.localizedDescription)")
            errorMessage = localization.string("sharing.error.removePerson")
        }

        actionInProgress = nil
    }

    private func applyOptimisticRemoveSharer(friendId: String) {
        guard let index = friends.firstIndex(where: { $0.id == friendId }) else { return }

        let friend = friends[index]

        // If I also share with them, just remove sharesWithMe
        if friend.iShareWith != nil {
            friends[index] = Friend(
                id: friend.id,
                email: friend.email,
                phone: friend.phone,
                firstName: friend.firstName,
                profilePictureUrl: friend.profilePictureUrl,
                oauthAvatarUrl: friend.oauthAvatarUrl,
                sharesWithMe: nil,
                iShareWith: friend.iShareWith
            )
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
            errorMessage = localization.string("sharing.error.shareBack")
        }

        actionInProgress = nil
    }

    private func applyOptimisticShareBack(friendId: String) {
        guard let index = friends.firstIndex(where: { $0.id == friendId }) else { return }

        let friend = friends[index]
        let newIShareWith = Friend.IShareWith(
            showEarningsToThem: false,
            sharedAt: ISO8601DateFormatter().string(from: Date())
        )

        friends[index] = Friend(
            id: friend.id,
            email: friend.email,
            phone: friend.phone,
            firstName: friend.firstName,
            profilePictureUrl: friend.profilePictureUrl,
            oauthAvatarUrl: friend.oauthAvatarUrl,
            sharesWithMe: friend.sharesWithMe,
            iShareWith: newIShareWith
        )
    }

    private func revertOptimisticShareBack(originalFriend: Friend) {
        guard let index = friends.firstIndex(where: { $0.id == originalFriend.id }) else { return }
        friends[index] = originalFriend
    }

    // MARK: - Callbacks

    /// Callback for when visibility changes (block/unblock) to trigger sharer list refresh
    var onVisibilityChange: (() -> Void)?
}
