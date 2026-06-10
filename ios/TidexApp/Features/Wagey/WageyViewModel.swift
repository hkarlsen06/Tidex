import Combine
import Foundation
import Observation
import os.log
import Supabase
import UIKit

private let logger = Logger(subsystem: "no.tidex.app", category: "WageyViewModel")  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant

// MARK: - Wagey Invocations

/// Wagey message usage data from the profiles table
struct WageyInvocations: Codable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let count: Int  // swiftlint:disable:this explicit_acl
  let month: String?  // swiftlint:disable:this explicit_acl
  let bonus: Int?  // swiftlint:disable:this explicit_acl

  /// Whether the stored month matches the current month
  /// If not, the count should be considered 0 (will reset on next invocation)
  var isCurrentMonth: Bool {  // swiftlint:disable:this explicit_acl
    guard let month else { return false }  // swiftlint:disable:this conditional_returns_on_newline
    let formatter = DateFormatter()  // swiftlint:disable:this explicit_type_interface
    formatter.dateFormat = "yyyy-MM"
    let currentMonth = formatter.string(from: Date())  // swiftlint:disable:this explicit_type_interface
    return month == currentMonth
  }

  /// Effective count considering month reset
  /// Returns 0 if the month doesn't match current month
  var effectiveCount: Int {  // swiftlint:disable:this explicit_acl
    isCurrentMonth ? count : 0
  }

  /// Effective bonus available
  var effectiveBonus: Int {  // swiftlint:disable:this explicit_acl
    bonus ?? 0
  }
}

/// Profile data from the profiles table
private struct ProfileData: Codable {
  let wagey_invocations: WageyInvocations?  // swiftlint:disable:this identifier_name
}

/// ViewModel for the Wagey AI chat feature
/// Manages conversation state, streaming, persistence, and user interactions
@MainActor
@Observable
final class WageyViewModel {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length required_deinit type_body_length
  // MARK: - Shared Instance

  /// Shared instance that persists across view presentations within the same session
  /// This ensures the current conversation is retained when dismissing and reopening Wagey
  static let shared = WageyViewModel()  // swiftlint:disable:this explicit_acl explicit_type_interface

  // MARK: - Constants

  /// Message limits per tier
  private static let messageLimits: [SubscriptionTier: Int] = [
    .free: 3,  // swiftlint:disable:this no_magic_numbers
    .pro: 40,  // swiftlint:disable:this no_magic_numbers
    .max: 90,  // swiftlint:disable:this no_magic_numbers
  ]

  /// Character count threshold at which the "conversation is getting long" warning appears
  private static let conversationWarningCharacters = 24_000  // swiftlint:disable:this explicit_type_interface

  /// Character count threshold at which older messages are truncated before sending to the API
  private static let conversationMaxCharacters = 32_000  // swiftlint:disable:this explicit_type_interface

  /// Character budget for the recent raw messages kept alongside a compaction summary
  private static let conversationCompactionTargetCharacters = 12_000  // swiftlint:disable:this explicit_type_interface

  /// Maximum number of older messages to include in the deterministic summary
  private static let compactionMessageLimit = 12  // swiftlint:disable:this explicit_type_interface

  /// Coalescing window for streamed chunks before mutating UI state.
  private static let streamFlushInterval: TimeInterval = 0.016

  /// Maximum body length for Wagey completion notifications.
  private static let responseNotificationBodyMaxLength = 180  // swiftlint:disable:this explicit_type_interface

  // MARK: - Published State

  /// All conversations for the current user
  private(set) var conversations: [LocalConversation] = []  // swiftlint:disable:this explicit_acl

  /// Current conversation ID (nil for new unsaved conversation)
  private(set) var currentConversationId: String?  // swiftlint:disable:this explicit_acl

  /// Conversation history for the current conversation
  private(set) var messages: [ChatMessage] = []  // swiftlint:disable:this explicit_acl

  /// Content blocks being streamed from the assistant (in chronological order)
  private(set) var activeContentBlocks: [ContentBlock] = []  // swiftlint:disable:this explicit_acl

  /// Assistant message segments already completed during the current stream.
  private(set) var streamingMessages: [ChatMessage] = []  // swiftlint:disable:this explicit_acl

  /// Whether the next incoming text chunk should begin a new text block.
  private var shouldStartNewStreamingTextBlock = true  // swiftlint:disable:this explicit_type_interface

  /// Sources associated with the currently streaming assistant response
  private(set) var activeSources: [MessageSource] = []  // swiftlint:disable:this explicit_acl

  /// Whether currently receiving a streaming response
  private(set) var isStreaming: Bool = false  // swiftlint:disable:this explicit_acl

  /// Whether the backend has reported that the model is currently thinking
  private(set) var isModelThinking: Bool = false  // swiftlint:disable:this explicit_acl

  /// Start time for the current visible thinking phase.
  private var currentThinkingStartedAt: Date?

  /// Latest server-authored compaction summary for the active conversation.
  private(set) var currentCompaction: String?  // swiftlint:disable:this explicit_acl

  /// Whether the user has reached their message limit
  private(set) var limitReached: Bool = false  // swiftlint:disable:this explicit_acl

  /// Local count of messages sent this session (used when server data unavailable)
  private(set) var localMessagesSent: Int = 0  // swiftlint:disable:this explicit_acl

  /// Days until limit resets (for showing in limit reached message)
  private(set) var resetDays: Int = 0  // swiftlint:disable:this explicit_acl

  /// Wagey invocations from the profiles table (used to calculate usage)
  private(set) var wageyInvocations: WageyInvocations?  // swiftlint:disable:this explicit_acl

  /// Current error if any
  private(set) var error: Error?  // swiftlint:disable:this explicit_acl

  /// Whether an entitlement sync is in progress (server/StoreKit mismatch detected)
  private(set) var isSyncingEntitlement: Bool = false  // swiftlint:disable:this explicit_acl

  /// Message to show after entitlement sync (success or failure)
  private(set) var entitlementSyncMessage: String?  // swiftlint:disable:this explicit_acl

  /// Whether the user has seen the showcase (per user, stored in UserDefaults)
  private(set) var hasSeenShowcase: Bool = false  // swiftlint:disable:this explicit_acl

  /// Whether the user has consented to AI data sharing (per user, stored in UserDefaults)
  private(set) var hasConsentedToAISharing: Bool = false  // swiftlint:disable:this explicit_acl

  /// Whether the entry flow state has been loaded for the current user context
  private(set) var hasResolvedEntryState: Bool = false  // swiftlint:disable:this explicit_acl

  // MARK: - Computed Properties for Usage

  /// The user's current subscription tier
  var currentTier: SubscriptionTier {  // swiftlint:disable:this explicit_acl
    EntitlementService.shared.effectiveTier
  }

  /// The message limit for the current tier
  var messageLimit: Int {  // swiftlint:disable:this explicit_acl
    Self.messageLimits[currentTier] ?? 3  // swiftlint:disable:this no_magic_numbers
  }

  /// Number of messages used this month
  /// Uses profile data (wagey_invocations) when available, falls back to local session count
  var messagesUsed: Int {  // swiftlint:disable:this explicit_acl
    if let invocations = wageyInvocations {
      // Use profile data - effectiveCount handles month reset
      return invocations.effectiveCount + localMessagesSent
    }
    // Fall back to local session count when profile data unavailable
    return localMessagesSent
  }

  /// Number of messages remaining this month
  var remainingMessagesCount: Int {  // swiftlint:disable:this explicit_acl
    max(0, messageLimit - messagesUsed) + bonusMessages
  }

  /// Number of bonus messages available
  var bonusMessages: Int {  // swiftlint:disable:this explicit_acl
    wageyInvocations?.effectiveBonus ?? 0
  }

  /// Whether to show the showcase (free tier + hasn't seen it)
  var shouldShowShowcase: Bool {  // swiftlint:disable:this explicit_acl
    currentTier == .free && !hasSeenShowcase
  }

  /// Whether to show the consent view (hasn't consented yet)
  var shouldShowConsent: Bool {  // swiftlint:disable:this explicit_acl
    !hasConsentedToAISharing
  }

  /// Estimated total character count across all messages (proxy for token usage)
  var estimatedConversationCharacters: Int {  // swiftlint:disable:this explicit_acl
    messages.reduce(0) { total, message in
      total
        + message.contentBlocks.reduce(0) { blockTotal, block in
          switch block {
          case .text(let text):
            return blockTotal + text.count

          case .toolCall(let toolCall):
            return blockTotal + (toolCall.arguments?.count ?? 0) + (toolCall.result?.count ?? 0)

          case .image:
            return blockTotal

          case .thoughtStatus:
            return blockTotal
          }
        }
    }
  }

  /// Whether the conversation is long enough to show a soft warning
  var isConversationLong: Bool {  // swiftlint:disable:this explicit_acl
    estimatedConversationCharacters >= Self.conversationWarningCharacters
  }

  // MARK: - Computed Properties for Streaming

  /// Current streaming text (concatenated from all text blocks)
  var currentStreamingText: String {  // swiftlint:disable:this explicit_acl
    WageyTextContent.flatten(
      blocks: activeContentBlocks.compactMap { block in
        if case .text(let text) = block { return text }  // swiftlint:disable:this conditional_returns_on_newline
        return nil
      })  // swiftlint:disable:this multiline_arguments_brackets
  }

  /// Active tool calls (extracted from content blocks for UI)
  var activeToolCalls: [ToolCall] {  // swiftlint:disable:this explicit_acl
    activeContentBlocks.compactMap { block in
      if case .toolCall(let toolCall) = block { return toolCall }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return nil
    }
  }

  /// Whether the sidebar is visible
  var isSidebarVisible: Bool = false  // swiftlint:disable:this explicit_acl

  var presentedAlertError: Error? {  // swiftlint:disable:this explicit_acl
    guard shouldPresentAlert(for: error) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return error
  }

  // MARK: - Private State

  /// Whether any tool calls succeeded during the current stream (triggers sync)
  private var hadSuccessfulToolCalls: Bool = false

  /// Tables that need a follow-up sync after successful mutating tool calls.
  private var pendingSyncTables: Set<SyncTable> = []

  /// Current streaming task (for cancellation)
  private var streamTask: Task<Void, Never>?

  /// Background assertion for an active Wagey stream.
  private var streamBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid

  /// Whether the current stream observed the app outside the active foreground state.
  private var currentStreamEnteredBackground = false  // swiftlint:disable:this explicit_type_interface

  /// ID of the message currently being streamed
  private var currentAssistantMessageId: String?

  /// Compaction summary emitted during the current stream, committed on finalize.
  private var pendingCompactionContent: String?

  /// Repository for conversation persistence
  private let conversationsRepository: ConversationsRepository = .shared

  /// Repository for server-synced user settings.
  private let settingsRepository = SettingsRepository.shared  // swiftlint:disable:this explicit_type_interface

  /// Cached user ID for persistence
  private var cachedUserId: String?

  /// Latest in-flight AI consent persistence task.
  private var consentPersistenceTask: Task<Void, Never>?

  /// Subscription for observing tier changes
  private var tierChangeSubscription: AnyCancellable?

  // MARK: - Initialization

  /// Private initializer to enforce singleton pattern
  private init() {  // swiftlint:disable:this type_contents_order
    observeTierChanges()
  }

  /// Observe tier changes to reset limit state when user upgrades
  private func observeTierChanges() {  // swiftlint:disable:this type_contents_order
    tierChangeSubscription = EntitlementService.shared.$effectiveTier
      .dropFirst()  // Skip initial value
      .sink { [weak self] newTier in
        guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline
        // If user upgraded to paid tier, reset the limit reached flag
        if newTier != .free, limitReached {
          limitReached = false
          // Also reset local counter since they have new limits now
          localMessagesSent = 0
          wageyInvocations = nil
        }
      }
  }

  private func beginStreamBackgroundTask() {  // swiftlint:disable:this type_contents_order
    endStreamBackgroundTask()
    currentStreamEnteredBackground = UIApplication.shared.applicationState != .active

    streamBackgroundTaskID = UIApplication.shared.beginBackgroundTask(
      withName: "WageyChatStream"
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline
        logger.warning("Wagey stream background time expired")
        cancelStream()
      }
    }
  }

  private func endStreamBackgroundTask() {  // swiftlint:disable:this type_contents_order
    guard streamBackgroundTaskID != .invalid else { return }  // swiftlint:disable:this conditional_returns_on_newline

    UIApplication.shared.endBackgroundTask(streamBackgroundTaskID)
    streamBackgroundTaskID = .invalid
  }

  private func updateCurrentStreamBackgroundState() {  // swiftlint:disable:this type_contents_order
    if UIApplication.shared.applicationState != .active {
      currentStreamEnteredBackground = true
    }
  }

  // MARK: - Showcase State Management

  /// UserDefaults key for showcase seen state (per user)
  private func showcaseKey(for userId: String) -> String {  // swiftlint:disable:this type_contents_order
    "wagey.hasSeenShowcase.\(userId)"
  }

  /// Load the showcase seen state from UserDefaults
  private func loadShowcaseState() {  // swiftlint:disable:this type_contents_order
    guard let userId = AppCoordinator.shared.userId else {
      hasSeenShowcase = false
      return
    }
    hasSeenShowcase = UserDefaults.standard.bool(forKey: showcaseKey(for: userId))
  }

  /// Mark the showcase as seen and save to UserDefaults
  func markShowcaseSeen() {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = AppCoordinator.shared.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    hasSeenShowcase = true
    hasResolvedEntryState = true
    UserDefaults.standard.set(true, forKey: showcaseKey(for: userId))
  }

  /// Reset the showcase state (for debugging) - clears UserDefaults and cached state
  func resetShowcaseSeen() {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = AppCoordinator.shared.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    hasSeenShowcase = false
    UserDefaults.standard.removeObject(forKey: showcaseKey(for: userId))
  }

  // MARK: - AI Consent State Management

  /// UserDefaults key for AI data sharing consent (per user)
  private func consentKey(for userId: String) -> String {  // swiftlint:disable:this type_contents_order
    "wagey.hasConsentedToAISharing.\(userId)"
  }

  /// Load the consent state from synced settings, with a one-time legacy UserDefaults fallback.
  private func loadConsentState() {  // swiftlint:disable:this type_contents_order
    guard let userId = AppCoordinator.shared.userId else {
      hasConsentedToAISharing = false
      return
    }

    let legacyConsent = UserDefaults.standard.object(forKey: consentKey(for: userId)) as? Bool  // swiftlint:disable:this explicit_type_interface line_length
    let syncedConsent =  // swiftlint:disable:this explicit_type_interface
      settingsRepository.getSettings(for: userId)?.effectiveAIDataSharingEnabled ?? false

    if syncedConsent {
      hasConsentedToAISharing = true
      if legacyConsent != nil {
        UserDefaults.standard.removeObject(forKey: consentKey(for: userId))
      }
      return
    }

    if legacyConsent == true {
      hasConsentedToAISharing = true
      scheduleAIConsentPersistence(true, for: userId, removeLegacyOnSuccess: true)
      return
    }

    if legacyConsent == false, settingsRepository.getSettings(for: userId) != nil {
      UserDefaults.standard.removeObject(forKey: consentKey(for: userId))
    }

    hasConsentedToAISharing = false
  }

  /// Mark that the user has consented to AI data sharing
  func grantAIConsent() {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = AppCoordinator.shared.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    hasConsentedToAISharing = true
    hasResolvedEntryState = true
    UserDefaults.standard.set(true, forKey: consentKey(for: userId))
    scheduleAIConsentPersistence(true, for: userId, removeLegacyOnSuccess: true)
  }

  /// Revoke consent for AI data sharing (called from Settings)
  func revokeAIConsent() {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = AppCoordinator.shared.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    hasConsentedToAISharing = false
    hasResolvedEntryState = true
    UserDefaults.standard.set(false, forKey: consentKey(for: userId))
    scheduleAIConsentPersistence(false, for: userId, removeLegacyOnSuccess: true)
  }

  private func scheduleAIConsentPersistence(  // swiftlint:disable:this type_contents_order
    _ isEnabled: Bool,
    for userId: String,
    removeLegacyOnSuccess: Bool
  ) {
    consentPersistenceTask?.cancel()
    consentPersistenceTask = Task { @MainActor [weak self] in
      await self?.persistAIConsentState(
        isEnabled,
        for: userId,
        removeLegacyOnSuccess: removeLegacyOnSuccess
      )
    }
  }

  private func persistAIConsentState(  // swiftlint:disable:this type_contents_order
    _ isEnabled: Bool,
    for userId: String,
    removeLegacyOnSuccess: Bool
  ) async {
    do {
      _ = try await settingsRepository.getOrCreateSettings(for: userId)
      try Task.checkCancellation()

      _ = try await settingsRepository.updateSettings(
        for: userId,
        aiDataSharingEnabled: isEnabled
      )

      if removeLegacyOnSuccess {
        UserDefaults.standard.removeObject(forKey: consentKey(for: userId))
      }
    } catch is CancellationError {
      return
    } catch {
      logger.error(
        "Failed to persist AI sharing consent for \(userId, privacy: .private): \(error.localizedDescription)"
      )
    }
  }

  /// Reset all in-memory user-scoped state.
  /// Called when signing out or switching authenticated user contexts.
  func resetForUserChange() {  // swiftlint:disable:this explicit_acl type_contents_order
    // Cancel without finalizing/saving partial assistant output to avoid reentrant resets.
    streamTask?.cancel()
    streamTask = nil
    isStreaming = false
    isModelThinking = false
    currentThinkingStartedAt = nil

    conversations = []
    currentConversationId = nil
    messages = []
    streamingMessages = []
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    currentCompaction = nil
    limitReached = false
    localMessagesSent = 0
    resetDays = 0
    wageyInvocations = nil
    error = nil
    isSyncingEntitlement = false
    entitlementSyncMessage = nil
    hasSeenShowcase = false
    hasConsentedToAISharing = false
    hasResolvedEntryState = false
    isSidebarVisible = false
    cachedUserId = nil
    hadSuccessfulToolCalls = false
    pendingSyncTables = []
    currentAssistantMessageId = nil
    currentStreamEnteredBackground = false
    pendingCompactionContent = nil
    consentPersistenceTask?.cancel()
    consentPersistenceTask = nil
  }

  /// Refresh the user-scoped showcase and consent state.
  func refreshEntryState() {  // swiftlint:disable:this explicit_acl type_contents_order
    guard AppCoordinator.shared.userId != nil else {
      hasSeenShowcase = false
      hasConsentedToAISharing = false
      hasResolvedEntryState = false
      return
    }

    loadShowcaseState()
    loadConsentState()
    hasResolvedEntryState = true
  }

  // MARK: - Conversation Management

  /// Load all conversations for the current user
  func loadConversations() {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = AppCoordinator.shared.userId else {
      resetForUserChange()
      return
    }
    cachedUserId = userId
    conversations = conversationsRepository.getConversations(for: userId)
    refreshEntryState()
  }

  /// Fetch wagey usage data from the profiles table
  /// Call this when opening Wagey to get the current usage count
  func fetchWageyUsage() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = AppCoordinator.shared.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    do {
      // Ensure refresh/session access is serialized to avoid refresh-token races
      // when Wagey opens during startup/foreground auth activity.
      _ = try await AuthSessionManager.shared.getSession()

      let profile: ProfileData =
        try await supabase
        .from("profiles")
        .select("wagey_invocations")
        .eq("id", value: userId)
        .single()
        .execute()
        .value

      wageyInvocations = profile.wagey_invocations
      // Reset local counter since we have authoritative server data
      localMessagesSent = 0

      // Check if limit is already reached based on profile data
      if let invocations = wageyInvocations {
        let used = invocations.effectiveCount  // swiftlint:disable:this explicit_type_interface
        let remaining = max(0, messageLimit - used) + invocations.effectiveBonus  // swiftlint:disable:this explicit_type_interface line_length
        limitReached = remaining <= 0
      } else {
        limitReached = false
      }
    } catch {
      // Non-fatal - we can still use local counter as fallback
      // Don't set self.error since this shouldn't block the user
    }
  }

  /// Load a specific conversation
  /// - Parameter id: Conversation ID to load
  func loadConversation(id: String) {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let conversation = conversationsRepository.getConversation(id: id) else {
      return
    }

    // Cancel any ongoing stream
    cancelStream()

    // Load the conversation
    currentConversationId = id
    messages = conversation.messages.map { $0.toChatMessage() }
    streamingMessages = []
    currentCompaction = conversation.compaction
    error = nil
  }

  /// Start a new conversation (clears current state)
  func startNewConversation() {  // swiftlint:disable:this explicit_acl type_contents_order
    // Cancel any ongoing stream
    cancelStream()

    // Save current conversation if it has messages
    saveCurrentConversation()

    // Reset state for new conversation
    currentConversationId = nil
    messages = []
    streamingMessages = []
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    currentCompaction = nil
    error = nil
  }

  /// Delete a conversation
  /// - Parameter id: Conversation ID to delete
  func deleteConversation(id: String) {  // swiftlint:disable:this explicit_acl type_contents_order
    guard conversationsRepository.deleteConversation(id: id) else {
      return
    }

    conversations.removeAll { $0.id == id }

    // If deleting the current conversation, start a new one
    if id == currentConversationId {
      currentConversationId = nil
      startNewConversation()
    }
  }

  /// Toggle sidebar visibility
  func toggleSidebar() {  // swiftlint:disable:this explicit_acl type_contents_order
    isSidebarVisible.toggle()
  }

  /// Get the current conversation title
  var currentConversationTitle: String {  // swiftlint:disable:this explicit_acl
    if let id = currentConversationId,
      let conversation = conversations.first(where: { $0.id == id })
    {
      return conversation.title
    }
    return "New Conversation"
  }

  // MARK: - Public Actions

  /// Send a new message to Wagey
  /// - Parameter content: The message content to send
  func sendMessage(_ content: String) async {  // swiftlint:disable:this explicit_acl type_contents_order
    await sendMessage(content, image: nil)
  }

  /// Send a new message to Wagey with an optional image attachment
  /// - Parameters:
  ///   - content: The message content to send
  ///   - image: Optional image attachment
  func sendMessage(_ content: String, image: ImageAttachment?) async {  // swiftlint:disable:this async_without_await cyclomatic_complexity explicit_acl function_body_length line_length type_contents_order
    // Don't send if already streaming, limit reached, or consent revoked
    guard !isStreaming, !limitReached, hasConsentedToAISharing else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    // Clear any previous error
    error = nil

    // Add user message to conversation (with or without image)
    let userMessage: ChatMessage
    if let image {
      userMessage = ChatMessage.user(content, image: image)
    } else {
      userMessage = ChatMessage(
        id: UUID().uuidString,
        role: .user,
        content: content,
        toolCalls: nil,
        timestamp: Date()
      )
    }
    messages.append(userMessage)

    // Create conversation if this is the first message
    if currentConversationId == nil {
      createNewConversation(with: messages)
    } else {
      saveCurrentConversation()
    }

    // Start streaming
    isStreaming = true
    isModelThinking = true
    currentThinkingStartedAt = nil
    streamingMessages = []
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    hadSuccessfulToolCalls = false
    pendingSyncTables = []
    currentAssistantMessageId = UUID().uuidString
    pendingCompactionContent = nil

    // Prepare haptics for token streaming
    Haptics.prepareStreamingHaptics()
    beginStreamBackgroundTask()

    // Create streaming task
    streamTask = Task { @MainActor in  // swiftlint:disable:this closure_body_length
      defer {
        self.endStreamBackgroundTask()
      }
      do {
        // Get user info from AppCoordinator
        let coordinator = AppCoordinator.shared  // swiftlint:disable:this explicit_type_interface
        guard let userId = coordinator.userId else {
          throw WageyError.notAuthenticated
        }
        let userName = coordinator.userDisplayName.isEmpty ? nil : coordinator.userDisplayName  // swiftlint:disable:this explicit_type_interface line_length

        let apiPayload = messagesForAPI()  // swiftlint:disable:this explicit_type_interface

        // Start streaming from WageyService (compact older messages when the conversation is very long)
        let stream = WageyService.shared.streamChat(  // swiftlint:disable:this explicit_type_interface
          messages: apiPayload.messages,
          userId: userId,
          userName: userName,
          compaction: apiPayload.compaction
        )

        var bufferedChunks: [ChatChunk] = []
        var lastFlushAt = Date()  // swiftlint:disable:this explicit_type_interface
        let flushInterval = Self.streamFlushInterval  // swiftlint:disable:this explicit_type_interface

        // Process chunks
        for try await chunk in stream {
          // Check for cancellation
          if Task.isCancelled { break }
          updateCurrentStreamBackgroundState()
          bufferedChunks.append(chunk)
          let shouldFlush =  // swiftlint:disable:this explicit_type_interface
            !bufferedChunks.isEmpty
            && (!chunk.isDeferrableStreamChunk
              || Date().timeIntervalSince(lastFlushAt) >= flushInterval)
          if shouldFlush {
            let batch = bufferedChunks  // swiftlint:disable:this explicit_type_interface
            bufferedChunks.removeAll(keepingCapacity: true)
            processChunkBatch(batch)
            lastFlushAt = Date()
          }
        }

        if !bufferedChunks.isEmpty {
          let batch = bufferedChunks  // swiftlint:disable:this explicit_type_interface
          bufferedChunks.removeAll(keepingCapacity: true)
          processChunkBatch(batch)
        }

        // Finalize the message if not cancelled
        if !Task.isCancelled {
          updateCurrentStreamBackgroundState()
          finalizeStreamingText()
        }
      } catch {
        if !Task.isCancelled {
          self.error = error
          finalizeStreamingText()
        }
      }
    }
  }

  /// Cancel the current streaming response
  func cancelStream() {  // swiftlint:disable:this explicit_acl type_contents_order
    streamTask?.cancel()
    streamTask = nil
    endStreamBackgroundTask()

    // Finalize any partial message
    if isStreaming {
      finalizeStreamingText(wasCancelled: true)
    }
  }

  /// Clear the conversation and start a new chat (legacy method, now calls startNewConversation)
  func clearConversation() {  // swiftlint:disable:this explicit_acl type_contents_order
    startNewConversation()
  }

  /// Dismiss the current error
  func dismissError() {  // swiftlint:disable:this explicit_acl type_contents_order
    error = nil
  }

  /// Reset the limit reached flag (called when user upgrades tier)
  /// This allows paid users to continue chatting even if server cache is stale
  func resetLimitReached() {  // swiftlint:disable:this explicit_acl type_contents_order
    limitReached = false
    localMessagesSent = 0
  }

  // MARK: - Private Helpers

  /// Returns messages to send to the API, compacting older messages when the
  /// conversation exceeds the max character threshold.
  private func messagesForAPI() -> (messages: [ChatMessage], compaction: String?) {  // swiftlint:disable:this line_length type_contents_order
    let baseCompaction = currentCompaction  // swiftlint:disable:this explicit_type_interface

    guard estimatedConversationCharacters > Self.conversationMaxCharacters else {
      return (messages, baseCompaction)
    }

    var truncated: [ChatMessage] = []
    var charCount = 0  // swiftlint:disable:this explicit_type_interface

    for message in messages.reversed() {
      let messageChars = messageCharacterCount(message)  // swiftlint:disable:this explicit_type_interface

      if charCount + messageChars > Self.conversationCompactionTargetCharacters, !truncated.isEmpty
      {
        break
      }

      charCount += messageChars
      truncated.append(message)
    }

    let recentMessages = truncated.reversed()  // swiftlint:disable:this explicit_type_interface
    let omittedCount = max(0, messages.count - recentMessages.count)  // swiftlint:disable:this explicit_type_interface
    let omittedMessages: [ChatMessage] =
      omittedCount > 0 ? Array(messages.prefix(omittedCount)) : []

    let localCompaction: String? = buildCompactionSummary(for: omittedMessages)
    let combinedCompaction = combinedCompactionSummary(  // swiftlint:disable:this explicit_type_interface
      base: baseCompaction, appended: localCompaction)  // swiftlint:disable:this multiline_arguments_brackets

    return (Array(recentMessages), combinedCompaction)
  }

  private func messageCharacterCount(_ message: ChatMessage) -> Int {  // swiftlint:disable:this type_contents_order
    message.contentBlocks.reduce(0) { blockTotal, block in
      switch block {
      case .text(let text):
        return blockTotal + text.count

      case .toolCall(let toolCall):
        return blockTotal + (toolCall.arguments?.count ?? 0) + (toolCall.result?.count ?? 0)
          + toolCall.name.count

      case .image:
        return blockTotal + 64  // swiftlint:disable:this no_magic_numbers

      case .thoughtStatus:
        return blockTotal
      }
    }
  }

  private func buildCompactionSummary(for messages: [ChatMessage]) -> String? {  // swiftlint:disable:this line_length type_contents_order
    guard !messages.isEmpty else {
      return nil
    }

    let summaryLines: [String] = messages.suffix(Self.compactionMessageLimit).flatMap {
      message -> [String] in
      var lines: [String] = []
      let speaker = message.role == .user ? "User" : "Assistant"  // swiftlint:disable:this explicit_type_interface

      if !message.content.isEmpty {
        lines.append("- \(speaker): \(truncateSummaryText(message.content))")
      }

      let imageCount = message.imageAttachments.count  // swiftlint:disable:this explicit_type_interface
      if imageCount > 0 {
        let suffix = imageCount == 1 ? "" : "s"  // swiftlint:disable:this explicit_type_interface
        lines.append("- \(speaker): attached \(imageCount) image\(suffix)")
      }

      for toolCall in message.toolCalls ?? [] {
        let outcome = toolCall.success == false ? "failed" : "completed"  // swiftlint:disable:this explicit_type_interface line_length
        let detail = truncateSummaryText(toolCall.result ?? toolCall.arguments ?? "")  // swiftlint:disable:this explicit_type_interface line_length
        let detailSuffix = detail.isEmpty ? "" : ": \(detail)"  // swiftlint:disable:this explicit_type_interface
        lines.append("- Tool \(toolCall.name) \(outcome)\(detailSuffix)")
      }

      for thoughtStatus in message.contentBlocks.compactMap({ block -> ThoughtStatus? in
        if case .thoughtStatus(let status) = block { return status }  // swiftlint:disable:this conditional_returns_on_newline line_length
        return nil
      }) {
        lines.append("- \(speaker): \(thoughtStatus.localizedLabel)")
      }

      return lines
    }

    guard !summaryLines.isEmpty else {
      return nil
    }

    return "Summary of earlier conversation (\(messages.count) messages):\n"
      + summaryLines.joined(separator: "\n")
  }

  private func truncateSummaryText(_ text: String, maxLength: Int = 180) -> String {  // swiftlint:disable:this line_length type_contents_order
    let normalized = text.replacingOccurrences(  // swiftlint:disable:this explicit_type_interface
      of: "\\s+",
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard normalized.count > maxLength else {
      return normalized
    }

    let endIndex = normalized.index(normalized.startIndex, offsetBy: maxLength - 1)  // swiftlint:disable:this explicit_type_interface line_length
    return String(normalized[..<endIndex]) + "..."
  }

  private func combinedCompactionSummary(base: String?, appended: String?) -> String? {  // swiftlint:disable:this line_length type_contents_order
    switch (
      base?.trimmingCharacters(in: .whitespacesAndNewlines),
      appended?.trimmingCharacters(in: .whitespacesAndNewlines)
    ) {
    case (let base?, let appended?) where !base.isEmpty && !appended.isEmpty:  // swiftlint:disable:this line_length pattern_matching_keywords
      return "\(base)\n\n\(appended)"

    case (let base?, _) where !base.isEmpty:
      return base

    case (_, let appended?) where !appended.isEmpty:
      return appended

    default:
      return nil
    }
  }

  /// Trigger a background entitlement sync when server/StoreKit mismatch is detected
  /// This uploads the StoreKit subscription to the server to fix the mismatch
  private func triggerEntitlementSync() async {  // swiftlint:disable:this type_contents_order
    logger.info("Triggering entitlement sync due to server/StoreKit mismatch")

    isSyncingEntitlement = true
    entitlementSyncMessage = nil

    do {
      // Restore will sync with Apple and upload any valid entitlements to the server
      try await StoreKitManager.shared.restorePurchases()
      logger.info("Entitlement sync completed successfully")

      // Show brief success feedback
      entitlementSyncMessage = String(localized: .wageyEntitlementSyncSuccess)

      // Auto-dismiss after 3 seconds
      Task {
        try? await Task.sleep(for: .seconds(3))  // swiftlint:disable:this no_magic_numbers
        await MainActor.run {
          if self.entitlementSyncMessage != nil {
            self.entitlementSyncMessage = nil
          }
        }
      }
    } catch {
      logger.error("Entitlement sync failed: \(error.localizedDescription)")

      // Show error with suggestion to restore manually
      entitlementSyncMessage = String(localized: .wageyEntitlementSyncFailed)
    }

    isSyncingEntitlement = false
  }

  /// Dismiss the entitlement sync message
  func dismissEntitlementSyncMessage() {  // swiftlint:disable:this explicit_acl type_contents_order
    entitlementSyncMessage = nil
  }

  /// Create a new conversation in the database
  private func createNewConversation() {  // swiftlint:disable:this type_contents_order
    createNewConversation(with: [])
  }

  /// Save the current conversation to the database
  private func saveCurrentConversation() {  // swiftlint:disable:this type_contents_order
    guard let conversationId = currentConversationId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let storedMessages = messages.map { StoredChatMessage(from: $0) }  // swiftlint:disable:this explicit_type_interface
    guard
      let conversation = conversationsRepository.updateMessages(
        conversationId: conversationId,
        messages: storedMessages,
        compaction: currentCompaction
      )
    else {
      return
    }

    upsertConversation(conversation)
  }

  /// Process a single chunk from the stream
  private func processChunk(_ chunk: ChatChunk) {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    switch chunk {
    case .status(let thinking):
      if Self.shouldFlushStreamingAssistantSegment(
        onThinkingStatus: thinking,
        activeContentBlocks: activeContentBlocks
      ) {
        flushStreamingAssistantSegmentIfNeeded()
      }
      if thinking {
        startThinkingPhaseIfNeeded()
      } else {
        currentThinkingStartedAt = nil
      }
      isModelThinking = thinking

    case .textStart:
      completeThinkingPhaseIfNeeded()
      shouldStartNewStreamingTextBlock = true

    case .messageBreak:
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      if Self.shouldFlushStreamingAssistantSegment(
        onMessageBreak: activeContentBlocks
      ) {
        flushStreamingAssistantSegmentIfNeeded()
      }

    case .text(let content):
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      let normalizedContent =  // swiftlint:disable:this explicit_type_interface
        if shouldStartNewStreamingTextBlock {
          WageyTextContent.trimLeadingBubbleWhitespace(from: content)
        } else {
          content
        }
      guard !normalizedContent.isEmpty else { break }
      // Preserve provider text-block boundaries instead of flattening all text into one run.
      if !shouldStartNewStreamingTextBlock,
        let lastIndex = activeContentBlocks.indices.last,
        case .text(let existingText) = activeContentBlocks[lastIndex]
      {
        activeContentBlocks[lastIndex] = .text(existingText + normalizedContent)
      } else {
        activeContentBlocks.append(.text(normalizedContent))
      }
      shouldStartNewStreamingTextBlock = false

      // Light haptic for each token chunk
      Haptics.playStreamingToken()

    case .toolStart(let toolName, let toolCallId, let toolArguments):  // swiftlint:disable:this line_length pattern_matching_keywords
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Add a new tool call in progress
      let toolCall = ToolCall(  // swiftlint:disable:this explicit_type_interface
        id: toolCallId,
        name: toolName,
        arguments: toolArguments,
        result: nil,
        success: nil
      )
      activeContentBlocks.append(.toolCall(toolCall))

    case .toolResult(let toolName, let toolCallId, let toolArguments, let result, let success):  // swiftlint:disable:this line_length pattern_matching_keywords
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Update the tool call with its result (find by id in content blocks)
      if let index = activeContentBlocks.firstIndex(where: { block in
        if case .toolCall(let tc) = block { return tc.id == toolCallId }  // swiftlint:disable:this conditional_returns_on_newline line_length
        return false
      }), case .toolCall(let existingToolCall) = activeContentBlocks[index] {
        let updatedToolCall = ToolCall(  // swiftlint:disable:this explicit_type_interface
          id: toolCallId,
          name: toolName,
          arguments: toolArguments ?? existingToolCall.arguments,
          result: result,
          success: success
        )
        activeContentBlocks[index] = .toolCall(updatedToolCall)
      }
      // Track successful tool calls for sync
      if success == true {
        hadSuccessfulToolCalls = true
        pendingSyncTables.formUnion(syncTables(for: toolName))
      }

    case .builtInToolStart(let toolName, let toolCallId, let toolArguments):  // swiftlint:disable:this line_length pattern_matching_keywords
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      let toolCall = ToolCall(  // swiftlint:disable:this explicit_type_interface
        id: toolCallId,
        name: toolName,
        kind: .builtIn,
        arguments: toolArguments
      )
      activeContentBlocks.append(.toolCall(toolCall))

    case .builtInToolResult(let toolName, let toolCallId, let result, let success):  // swiftlint:disable:this line_length pattern_matching_keywords
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      if let index = activeContentBlocks.firstIndex(where: { block in
        if case .toolCall(let tc) = block { return tc.id == toolCallId }  // swiftlint:disable:this conditional_returns_on_newline line_length
        return false
      }), case .toolCall(let existingToolCall) = activeContentBlocks[index] {
        let updatedToolCall = ToolCall(  // swiftlint:disable:this explicit_type_interface
          id: toolCallId,
          name: toolName,
          kind: .builtIn,
          arguments: existingToolCall.arguments,
          result: result,
          success: success
        )
        activeContentBlocks[index] = .toolCall(updatedToolCall)
      }

    case .wageyLimit(let remaining, let days, let exceeded, let bonus):  // swiftlint:disable:this line_length pattern_matching_keywords
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Update wagey invocations from API response to stay in sync
      // The count is: limit - remaining
      let usedCount = max(0, messageLimit - remaining)  // swiftlint:disable:this explicit_type_interface
      let formatter = DateFormatter()  // swiftlint:disable:this explicit_type_interface
      formatter.dateFormat = "yyyy-MM"
      let currentMonth = formatter.string(from: Date())  // swiftlint:disable:this explicit_type_interface
      wageyInvocations = WageyInvocations(count: usedCount, month: currentMonth, bonus: bonus)
      // Reset local counter since we have fresh server data
      localMessagesSent = 0
      resetDays = days
      limitReached = (remaining + bonus) <= 0

      // Entitlement mismatch detection:
      // If server says exceeded but StoreKit has valid entitlements, trigger background sync
      // This handles cases where server doesn't know about a valid Apple subscription
      // Only sync if user hasn't genuinely exceeded their StoreKit tier's limit
      // (e.g., after downgrading from max to pro with usage exceeding pro's limit)
      if exceeded, StoreKitManager.shared.currentTier != .free {
        let storeKitTierLimit = Self.messageLimits[StoreKitManager.shared.currentTier] ?? 3  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
        let currentUsed = wageyInvocations?.effectiveCount ?? 0  // swiftlint:disable:this explicit_type_interface
        if currentUsed < storeKitTierLimit {
          logger.warning(
            "Entitlement mismatch detected: server says exceeded but StoreKit has tier \(StoreKitManager.shared.currentTier.rawValue)"  // swiftlint:disable:this line_length
          )
          Task {
            await triggerEntitlementSync()
          }
        }
      }

    case .wageyNoAccess:
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // User doesn't have access to Wagey
      limitReached = true
      error = WageyError.noAccess

    case .sources(let items):
      activeSources = items

    case .compaction(let content):
      pendingCompactionContent = content

    case .unknown:
      break

    case .done:
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
    // Stream completed - finalize handled after loop

    case .error(let message):
      completeThinkingPhaseIfNeeded()
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Server-side error
      error = WageyError.serverError(message)
    }
  }

  /// Finalize the streaming text into a message
  private func finalizeStreamingText(wasCancelled: Bool = false) {  // swiftlint:disable:this function_body_length line_length type_contents_order
    let shouldNotifyBackgroundCompletion =  // swiftlint:disable:this explicit_type_interface
      currentStreamEnteredBackground && UIApplication.shared.applicationState != .active
      && !wasCancelled && !(streamTask?.isCancelled ?? false)
    let finalizeIncompleteToolCalls = wasCancelled || error != nil  // swiftlint:disable:this explicit_type_interface
    let finalizedBlocks = finalizedContentBlocks(  // swiftlint:disable:this explicit_type_interface
      finalizeIncompleteToolCalls: finalizeIncompleteToolCalls)  // swiftlint:disable:this multiline_arguments_brackets
    let fallbackMessage = Self.fallbackAssistantMessage(  // swiftlint:disable:this explicit_type_interface
      error: error,
      limitReached: limitReached,
      wasCancelled: wasCancelled || (streamTask?.isCancelled ?? false),
      hasAssistantContent: !finalizedBlocks.isEmpty
    )

    var finalizedMessages = streamingMessages  // swiftlint:disable:this explicit_type_interface

    if !finalizedBlocks.isEmpty {
      finalizedMessages.append(
        ChatMessage(
          id: currentAssistantMessageId ?? UUID().uuidString,
          role: .assistant,
          contentBlocks: finalizedBlocks,
          sources: activeSources.isEmpty ? nil : activeSources,
          timestamp: Date()
        ))  // swiftlint:disable:this multiline_arguments_brackets
    } else if let fallbackMessage {
      finalizedMessages.append(
        ChatMessage(
          id: currentAssistantMessageId ?? UUID().uuidString,
          role: .assistant,
          contentBlocks: [.text(fallbackMessage)],
          timestamp: Date()
        ))  // swiftlint:disable:this multiline_arguments_brackets
    }

    if !finalizedMessages.isEmpty {
      let keepingMessageId = finalizedMessages.first?.id  // swiftlint:disable:this explicit_type_interface
      messages.append(contentsOf: finalizedMessages)
      applyPendingCompaction(keepingMessageId: keepingMessageId)
      saveCurrentConversation()
      if shouldNotifyBackgroundCompletion,
        let notificationBody = responseNotificationBody(from: finalizedMessages.last)
      {
        let conversationId = currentConversationId  // swiftlint:disable:this explicit_type_interface
        Task {
          await NotificationService.shared.scheduleWageyResponseNotification(
            body: notificationBody,
            conversationId: conversationId
          )
        }
      }
    } else if let pendingCompactionContent {
      currentCompaction = pendingCompactionContent
      saveCurrentConversation()
    }

    // Trigger sync if any tool calls succeeded (shifts may have changed server-side)
    if hadSuccessfulToolCalls, let userId = cachedUserId ?? AppCoordinator.shared.userId {
      let tablesToSync = Array(pendingSyncTables)  // swiftlint:disable:this explicit_type_interface
      Task {
        await syncAndNotifyShiftChanges(userId: userId, tables: tablesToSync)
      }
    }

    // Reset streaming state
    streamingMessages = []
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    pendingCompactionContent = nil
    hadSuccessfulToolCalls = false
    pendingSyncTables = []
    isStreaming = false
    isModelThinking = false
    currentThinkingStartedAt = nil
    currentAssistantMessageId = nil
    currentStreamEnteredBackground = false
    streamTask = nil
    if !shouldPresentAlert(for: error) {
      error = nil
    }
  }

  private func flushStreamingAssistantSegmentIfNeeded() {  // swiftlint:disable:this type_contents_order
    let sanitizedBlocks = sanitizeAssistantBubbleBoundaryBlocks(activeContentBlocks)  // swiftlint:disable:this explicit_type_interface line_length
    guard !sanitizedBlocks.isEmpty else {
      activeContentBlocks = []
      activeSources = []
      shouldStartNewStreamingTextBlock = true
      return
    }

    let assistantMessage = ChatMessage(  // swiftlint:disable:this explicit_type_interface
      id: currentAssistantMessageId ?? UUID().uuidString,
      role: .assistant,
      contentBlocks: sanitizedBlocks,
      sources: activeSources.isEmpty ? nil : activeSources,
      timestamp: Date()
    )
    streamingMessages.append(assistantMessage)
    currentAssistantMessageId = UUID().uuidString
    activeContentBlocks = []
    activeSources = []
    shouldStartNewStreamingTextBlock = true
  }

  private func startThinkingPhaseIfNeeded() {  // swiftlint:disable:this type_contents_order
    guard currentThinkingStartedAt == nil else { return }  // swiftlint:disable:this conditional_returns_on_newline
    currentThinkingStartedAt = Date()
  }

  private func completeThinkingPhaseIfNeeded() {  // swiftlint:disable:this type_contents_order
    guard let startedAt = currentThinkingStartedAt else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let elapsedSeconds = Self.thinkingStatusDurationSeconds(since: startedAt)  // swiftlint:disable:this explicit_type_interface line_length
    if Self.shouldPersistThinkingStatus(durationSeconds: elapsedSeconds) {
      streamingMessages.append(
        ChatMessage(
          role: .assistant,
          contentBlocks: [.thoughtStatus(ThoughtStatus(durationSeconds: elapsedSeconds))],
          timestamp: Date()
        ))  // swiftlint:disable:this multiline_arguments_brackets
    }
    currentThinkingStartedAt = nil
  }

  /// Ensures Wagey-created shift changes are pulled locally before notifying UI observers.
  /// Retries when another sync is already in progress to avoid stale reloads.
  private func syncAndNotifyShiftChanges(userId: String, tables: [SyncTable]) async {  // swiftlint:disable:this line_length type_contents_order
    guard !tables.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let alreadySyncingError = "Sync already in progress"  // swiftlint:disable:this explicit_type_interface
    let retryIntervalNanoseconds: UInt64 = 250_000_000
    let retryDeadline: Date = Date().addingTimeInterval(30)  // swiftlint:disable:this no_magic_numbers
    var syncResult: SyncResult

    while true {
      syncResult = await SyncCoordinator.shared.sync(
        reason: .localChange,
        userId: userId,
        tables: tables
      )

      if syncResult.success {
        break
      }

      guard syncResult.error == alreadySyncingError else {
        break
      }

      guard Date() < retryDeadline else {
        logger.warning("Wagey sync retry timed out after 30 seconds")
        return
      }

      do {
        try await Task.sleep(nanoseconds: retryIntervalNanoseconds)
      } catch {
        logger.info("Wagey sync retry cancelled")
        return
      }
    }

    guard syncResult.success else {
      if let error = syncResult.error {
        logger.warning("Wagey sync failed before UI reload: \(error)")
      } else {
        logger.warning("Wagey sync did not complete successfully before UI reload")
      }
      return
    }

    NotificationCenter.default.postShiftsDidChange(context: .fullReload)
  }

  private func processChunkBatch(_ chunks: [ChatChunk]) {  // swiftlint:disable:this type_contents_order
    for chunk in chunks {
      processChunk(chunk)
    }
  }

  private func responseNotificationBody(from message: ChatMessage?) -> String? {  // swiftlint:disable:this line_length type_contents_order
    guard let message, message.role == .assistant else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let text = message.content  // swiftlint:disable:this explicit_type_interface
      .plainTextForNotification()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    return Self.truncatedNotificationBody(text)
  }

  private static func truncatedNotificationBody(_ text: String) -> String {
    guard text.count > responseNotificationBodyMaxLength else { return text }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let endIndex = text.index(  // swiftlint:disable:this explicit_type_interface
      text.startIndex,
      offsetBy: responseNotificationBodyMaxLength - 1
    )
    return String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
  }

  private func createNewConversation(with messages: [ChatMessage]) {  // swiftlint:disable:this type_contents_order
    guard let userId = cachedUserId ?? AppCoordinator.shared.userId else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    let conversation = conversationsRepository.createConversation(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      title: "New Conversation",
      messages: messages.map { StoredChatMessage(from: $0) },
      compaction: currentCompaction
    )
    currentConversationId = conversation.id
    upsertConversation(conversation)
  }

  private func upsertConversation(_ conversation: LocalConversation) {  // swiftlint:disable:this type_contents_order
    conversations.removeAll { $0.id == conversation.id }
    conversations.insert(conversation, at: 0)
    conversations.sort { $0.updatedAt > $1.updatedAt }
  }

  private func syncTables(for toolName: String) -> Set<SyncTable> {  // swiftlint:disable:this type_contents_order
    switch toolName {
    case "manage_shift":
      return [.userShifts]

    case "confirm_recurring_shift", "manage_recurring_shift", "manage_recurring_exclusion":
      return [.recurringShifts]

    case "manage_shift_advanced":
      return [.userShifts, .recurringShifts]

    case "manage_workplace":
      return [.jobs, .wageSnapshots]

    case "manage_wage_snapshots":
      return [.wageSnapshots]

    case "manage_payroll_adjustment":
      return [.payrollAdjustments]

    case "manage_account", "manage_settings":
      return [.userSettings]

    default:
      return []
    }
  }

  private func applyPendingCompaction(keepingMessageId: String?) {  // swiftlint:disable:this type_contents_order
    guard let pendingCompactionContent else { return }  // swiftlint:disable:this conditional_returns_on_newline
    currentCompaction = pendingCompactionContent

    guard let keepingMessageId,
      let index = messages.firstIndex(where: { $0.id == keepingMessageId })
    else {
      return
    }

    messages = Array(messages.suffix(from: index))
  }

  private func finalizedContentBlocks(finalizeIncompleteToolCalls: Bool) -> [ContentBlock] {  // swiftlint:disable:this line_length type_contents_order
    let sanitizedBlocks = sanitizeAssistantBubbleBoundaryBlocks(activeContentBlocks)  // swiftlint:disable:this explicit_type_interface line_length
    guard finalizeIncompleteToolCalls else { return sanitizedBlocks }  // swiftlint:disable:this conditional_returns_on_newline line_length

    return sanitizedBlocks.compactMap { block in
      switch block {
      case .text(let text):
        return text.isEmpty ? nil : .text(text)

      case .toolCall(let toolCall):
        if toolCall.result != nil {
          return .toolCall(toolCall)
        }

        return .toolCall(interruptedToolCall(from: toolCall))

      case .image(let attachment):
        return .image(attachment)

      case .thoughtStatus(let status):
        return .thoughtStatus(status)
      }
    }
  }

  private func sanitizeAssistantBubbleBoundaryBlocks(_ blocks: [ContentBlock]) -> [ContentBlock] {  // swiftlint:disable:this line_length type_contents_order
    var sanitizedBlocks = blocks  // swiftlint:disable:this explicit_type_interface

    if let firstTextIndex = sanitizedBlocks.firstIndex(where: { block in
      if case .text = block { return true }  // swiftlint:disable:this conditional_returns_on_newline
      return false
    }), case .text(let text) = sanitizedBlocks[firstTextIndex] {
      sanitizedBlocks[firstTextIndex] = .text(
        WageyTextContent.trimLeadingBubbleWhitespace(from: text)
      )
    }

    if let lastTextIndex = sanitizedBlocks.lastIndex(where: { block in
      if case .text = block { return true }  // swiftlint:disable:this conditional_returns_on_newline
      return false
    }), case .text(let text) = sanitizedBlocks[lastTextIndex] {
      sanitizedBlocks[lastTextIndex] = .text(
        WageyTextContent.trimTrailingBubbleWhitespace(from: text)
      )
    }

    return sanitizedBlocks.compactMap { block in
      switch block {
      case .text(let text):
        return text.isEmpty ? nil : .text(text)

      case .toolCall, .image, .thoughtStatus:
        return block
      }
    }
  }

  private func interruptedToolCall(from toolCall: ToolCall) -> ToolCall {  // swiftlint:disable:this type_contents_order
    ToolCall(
      id: toolCall.id,
      name: toolCall.name,
      kind: toolCall.kind,
      arguments: toolCall.arguments,
      result: interruptedToolResultPayload(),
      success: false
    )
  }

  private func interruptedToolResultPayload() -> String {  // swiftlint:disable:this type_contents_order
    let payload: [String: Any] = [
      "success": false,
      "message": String(localized: .wageyToolInterruptedMessage),
    ]

    guard
      let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else {
      return "{\"success\":false}"
    }

    return string
  }

  private func shouldPresentAlert(for error: Error?) -> Bool {  // swiftlint:disable:this type_contents_order
    guard let error else { return false }  // swiftlint:disable:this conditional_returns_on_newline

    switch error {
    case is WageyServiceError:
      return false

    case WageyError.serverError(_), WageyError.noAccess:
      return false

    default:
      return true
    }
  }

  static func fallbackAssistantMessage(  // swiftlint:disable:this explicit_acl
    error: Error?,
    limitReached: Bool,
    wasCancelled: Bool,
    hasAssistantContent: Bool
  ) -> String? {
    guard !hasAssistantContent, !wasCancelled, !limitReached else {
      return nil
    }

    if let serviceError = error as? WageyServiceError, case .cancelled = serviceError {
      return nil
    }

    if let message = error?.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines),
      !message.isEmpty
    {
      return message
    }

    return String(localized: .wageyErrorUnknown)
  }

  static func shouldFlushStreamingAssistantSegment(  // swiftlint:disable:this explicit_acl
    onThinkingStatus thinking: Bool,
    activeContentBlocks: [ContentBlock]
  ) -> Bool {
    thinking && !activeContentBlocks.isEmpty
  }

  static func shouldFlushStreamingAssistantSegment(  // swiftlint:disable:this explicit_acl
    onMessageBreak activeContentBlocks: [ContentBlock]
  ) -> Bool {
    !activeContentBlocks.isEmpty
  }

  static func shouldPersistThinkingStatus(durationSeconds: Int) -> Bool {  // swiftlint:disable:this explicit_acl
    durationSeconds > 2  // swiftlint:disable:this no_magic_numbers
  }

  static func thinkingStatusDurationSeconds(since startedAt: Date, now: Date = Date()) -> Int {  // swiftlint:disable:this explicit_acl line_length
    max(1, Int(now.timeIntervalSince(startedAt).rounded()))
  }
}

extension ChatChunk {  // swiftlint:disable:this extension_access_modifier file_types_order
  fileprivate var isDeferrableStreamChunk: Bool {  // swiftlint:disable:this strict_fileprivate
    switch self {
    case .status:
      return true

    case .textStart, .messageBreak, .toolStart, .toolResult, .builtInToolStart, .builtInToolResult,
      .done, .error,
      .wageyLimit, .wageyNoAccess, .sources, .compaction, .unknown, .text:
      return false
    }
  }
}

// MARK: - Wagey Errors

/// Errors specific to the Wagey feature
enum WageyError: LocalizedError {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case notAuthenticated  // swiftlint:disable:this sorted_enum_cases
  case noAccess
  case serverError(String)  // swiftlint:disable:this sorted_enum_cases
  case networkError(Error)  // swiftlint:disable:this sorted_enum_cases

  var errorDescription: String? {  // swiftlint:disable:this explicit_acl
    switch self {
    case .notAuthenticated:
      return "You must be logged in to use Wagey"

    case .noAccess:
      return "Upgrade to Pro or Max to use Wagey"

    case .serverError(let message):
      return message

    case .networkError(let error):
      return error.localizedDescription
    }
  }
}

extension String {  // swiftlint:disable:this extension_access_modifier
  fileprivate func plainTextForNotification() -> String {  // swiftlint:disable:this strict_fileprivate
    var text = self  // swiftlint:disable:this explicit_type_interface
    let replacements: [(String, String)] = [
      ("```[\\s\\S]*?```", " "),
      ("`([^`]+)`", "$1"),
      ("!\\[([^\\]]*)\\]\\([^\\)]*\\)", "$1"),
      ("\\[([^\\]]+)\\]\\([^\\)]*\\)", "$1"),
      ("\\*\\*([^*]+)\\*\\*", "$1"),
      ("__([^_]+)__", "$1"),
      ("\\*([^*]+)\\*", "$1"),
      ("_([^_]+)_", "$1"),
      ("~~([^~]+)~~", "$1"),
      ("^\\s{0,3}#{1,6}\\s+", ""),
      ("^\\s{0,3}>\\s?", ""),
      ("^\\s*[-*+]\\s+", ""),
      ("^\\s*\\d+[.)]\\s+", ""),
      ("\\s+", " "),
    ]

    for (pattern, replacement) in replacements {
      text = text.replacingOccurrences(
        of: pattern,
        with: replacement,
        options: [.regularExpression]
      )
    }

    return text
  }
}  // swiftlint:disable:this file_length
