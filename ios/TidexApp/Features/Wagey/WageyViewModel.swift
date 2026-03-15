import Combine
import Foundation
import Observation
import Supabase
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "WageyViewModel")

// MARK: - Wagey Invocations

/// Wagey message usage data from the profiles table
struct WageyInvocations: Codable {
  let count: Int
  let month: String?
  let bonus: Int?

  /// Whether the stored month matches the current month
  /// If not, the count should be considered 0 (will reset on next invocation)
  var isCurrentMonth: Bool {
    guard let month = month else { return false }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM"
    let currentMonth = formatter.string(from: Date())
    return month == currentMonth
  }

  /// Effective count considering month reset
  /// Returns 0 if the month doesn't match current month
  var effectiveCount: Int {
    isCurrentMonth ? count : 0
  }

  /// Effective bonus available
  var effectiveBonus: Int {
    bonus ?? 0
  }
}

/// Profile data from the profiles table
private struct ProfileData: Codable {
  let wagey_invocations: WageyInvocations?
}

/// ViewModel for the Wagey AI chat feature
/// Manages conversation state, streaming, persistence, and user interactions
@MainActor
@Observable
final class WageyViewModel {
  // MARK: - Shared Instance

  /// Shared instance that persists across view presentations within the same session
  /// This ensures the current conversation is retained when dismissing and reopening Wagey
  static let shared = WageyViewModel()

  // MARK: - Constants

  /// Message limits per tier
  private static let messageLimits: [SubscriptionTier: Int] = [
    .free: 3,
    .pro: 40,
    .max: 90,
  ]

  /// Character count threshold at which the "conversation is getting long" warning appears
  private static let conversationWarningCharacters = 24_000

  /// Character count threshold at which older messages are truncated before sending to the API
  private static let conversationMaxCharacters = 32_000

  /// Character budget for the recent raw messages kept alongside a compaction summary
  private static let conversationCompactionTargetCharacters = 12_000

  /// Maximum number of older messages to include in the deterministic summary
  private static let compactionMessageLimit = 12

  /// Coalescing window for streamed chunks before mutating UI state.
  private static let streamFlushInterval: TimeInterval = 0.016

  // MARK: - Published State

  /// All conversations for the current user
  private(set) var conversations: [LocalConversation] = []

  /// Current conversation ID (nil for new unsaved conversation)
  private(set) var currentConversationId: String?

  /// Conversation history for the current conversation
  private(set) var messages: [ChatMessage] = []

  /// Content blocks being streamed from the assistant (in chronological order)
  private(set) var activeContentBlocks: [ContentBlock] = []

  /// Whether the next incoming text chunk should begin a new text block.
  private var shouldStartNewStreamingTextBlock = true

  /// Sources associated with the currently streaming assistant response
  private(set) var activeSources: [MessageSource] = []

  /// Whether currently receiving a streaming response
  private(set) var isStreaming: Bool = false

  /// Whether the backend has reported that the model is currently thinking
  private(set) var isModelThinking: Bool = false

  /// Latest server-authored compaction summary for the active conversation.
  private(set) var currentCompaction: String?

  /// Whether the user has reached their message limit
  private(set) var limitReached: Bool = false

  /// Local count of messages sent this session (used when server data unavailable)
  private(set) var localMessagesSent: Int = 0

  /// Days until limit resets (for showing in limit reached message)
  private(set) var resetDays: Int = 0

  /// Wagey invocations from the profiles table (used to calculate usage)
  private(set) var wageyInvocations: WageyInvocations?

  /// Current error if any
  private(set) var error: Error?

  /// Whether an entitlement sync is in progress (server/StoreKit mismatch detected)
  private(set) var isSyncingEntitlement: Bool = false

  /// Message to show after entitlement sync (success or failure)
  private(set) var entitlementSyncMessage: String?

  /// Whether the user has seen the showcase (per user, stored in UserDefaults)
  private(set) var hasSeenShowcase: Bool = false

  /// Whether the user has consented to AI data sharing (per user, stored in UserDefaults)
  private(set) var hasConsentedToAISharing: Bool = false

  /// Whether the entry flow state has been loaded for the current user context
  private(set) var hasResolvedEntryState: Bool = false

  // MARK: - Computed Properties for Usage

  /// The user's current subscription tier
  var currentTier: SubscriptionTier {
    EntitlementService.shared.effectiveTier
  }

  /// The message limit for the current tier
  var messageLimit: Int {
    Self.messageLimits[currentTier] ?? 3
  }

  /// Number of messages used this month
  /// Uses profile data (wagey_invocations) when available, falls back to local session count
  var messagesUsed: Int {
    if let invocations = wageyInvocations {
      // Use profile data - effectiveCount handles month reset
      return invocations.effectiveCount + localMessagesSent
    }
    // Fall back to local session count when profile data unavailable
    return localMessagesSent
  }

  /// Number of messages remaining this month
  var remainingMessagesCount: Int {
    max(0, messageLimit - messagesUsed) + bonusMessages
  }

  /// Number of bonus messages available
  var bonusMessages: Int {
    wageyInvocations?.effectiveBonus ?? 0
  }

  /// Whether to show the showcase (free tier + hasn't seen it)
  var shouldShowShowcase: Bool {
    currentTier == .free && !hasSeenShowcase
  }

  /// Whether to show the consent view (hasn't consented yet)
  var shouldShowConsent: Bool {
    !hasConsentedToAISharing
  }

  /// Estimated total character count across all messages (proxy for token usage)
  var estimatedConversationCharacters: Int {
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
          }
        }
    }
  }

  /// Whether the conversation is long enough to show a soft warning
  var isConversationLong: Bool {
    estimatedConversationCharacters >= Self.conversationWarningCharacters
  }

  // MARK: - Computed Properties for Streaming

  /// Current streaming text (concatenated from all text blocks)
  var currentStreamingText: String {
    WageyTextContent.flatten(
      blocks: activeContentBlocks.compactMap { block in
        if case .text(let text) = block { return text }
        return nil
      })
  }

  /// Active tool calls (extracted from content blocks for UI)
  var activeToolCalls: [ToolCall] {
    activeContentBlocks.compactMap { block in
      if case .toolCall(let toolCall) = block { return toolCall }
      return nil
    }
  }

  /// Whether the sidebar is visible
  var isSidebarVisible: Bool = false

  var presentedAlertError: Error? {
    guard shouldPresentAlert(for: error) else { return nil }
    return error
  }

  // MARK: - Private State

  /// Whether any tool calls succeeded during the current stream (triggers sync)
  private var hadSuccessfulToolCalls: Bool = false

  /// Tables that need a follow-up sync after successful mutating tool calls.
  private var pendingSyncTables: Set<SyncTable> = []

  /// Current streaming task (for cancellation)
  private var streamTask: Task<Void, Never>?

  /// ID of the message currently being streamed
  private var currentAssistantMessageId: String?

  /// Compaction summary emitted during the current stream, committed on finalize.
  private var pendingCompactionContent: String?

  /// Repository for conversation persistence
  private let conversationsRepository = ConversationsRepository.shared

  /// Cached user ID for persistence
  private var cachedUserId: String?

  /// Subscription for observing tier changes
  private var tierChangeSubscription: AnyCancellable?

  // MARK: - Initialization

  /// Private initializer to enforce singleton pattern
  private init() {
    loadConversations()
    observeTierChanges()
  }

  /// Observe tier changes to reset limit state when user upgrades
  private func observeTierChanges() {
    tierChangeSubscription = EntitlementService.shared.$effectiveTier
      .dropFirst()  // Skip initial value
      .sink { [weak self] newTier in
        guard let self = self else { return }
        // If user upgraded to paid tier, reset the limit reached flag
        if newTier != .free && self.limitReached {
          self.limitReached = false
          // Also reset local counter since they have new limits now
          self.localMessagesSent = 0
          self.wageyInvocations = nil
        }
      }
  }

  // MARK: - Showcase State Management

  /// UserDefaults key for showcase seen state (per user)
  private func showcaseKey(for userId: String) -> String {
    "wagey.hasSeenShowcase.\(userId)"
  }

  /// Load the showcase seen state from UserDefaults
  private func loadShowcaseState() {
    guard let userId = AppCoordinator.shared.userId else {
      hasSeenShowcase = false
      return
    }
    hasSeenShowcase = UserDefaults.standard.bool(forKey: showcaseKey(for: userId))
  }

  /// Mark the showcase as seen and save to UserDefaults
  func markShowcaseSeen() {
    guard let userId = AppCoordinator.shared.userId else { return }
    hasSeenShowcase = true
    hasResolvedEntryState = true
    UserDefaults.standard.set(true, forKey: showcaseKey(for: userId))
  }

  /// Reset the showcase state (for debugging) - clears UserDefaults and cached state
  func resetShowcaseSeen() {
    guard let userId = AppCoordinator.shared.userId else { return }
    hasSeenShowcase = false
    UserDefaults.standard.removeObject(forKey: showcaseKey(for: userId))
  }

  // MARK: - AI Consent State Management

  /// UserDefaults key for AI data sharing consent (per user)
  private func consentKey(for userId: String) -> String {
    "wagey.hasConsentedToAISharing.\(userId)"
  }

  /// Load the consent state from UserDefaults
  private func loadConsentState() {
    guard let userId = AppCoordinator.shared.userId else {
      hasConsentedToAISharing = false
      return
    }
    hasConsentedToAISharing = UserDefaults.standard.bool(forKey: consentKey(for: userId))
  }

  /// Mark that the user has consented to AI data sharing
  func grantAIConsent() {
    guard let userId = AppCoordinator.shared.userId else { return }
    hasConsentedToAISharing = true
    hasResolvedEntryState = true
    UserDefaults.standard.set(true, forKey: consentKey(for: userId))
  }

  /// Revoke consent for AI data sharing (called from Settings)
  func revokeAIConsent() {
    guard let userId = AppCoordinator.shared.userId else { return }
    hasConsentedToAISharing = false
    hasResolvedEntryState = true
    UserDefaults.standard.set(false, forKey: consentKey(for: userId))
  }

  /// Reset all in-memory user-scoped state.
  /// Called when signing out or switching authenticated user contexts.
  func resetForUserChange() {
    // Cancel without finalizing/saving partial assistant output to avoid reentrant resets.
    streamTask?.cancel()
    streamTask = nil
    isStreaming = false

    conversations = []
    currentConversationId = nil
    messages = []
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
    pendingCompactionContent = nil
  }

  /// Refresh the user-scoped showcase and consent state.
  func refreshEntryState() {
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
  func loadConversations() {
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
  func fetchWageyUsage() async {
    guard let userId = AppCoordinator.shared.userId else { return }

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
        let used = invocations.effectiveCount
        let remaining = max(0, messageLimit - used) + invocations.effectiveBonus
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
  func loadConversation(id: String) {
    guard let conversation = conversationsRepository.getConversation(id: id) else {
      return
    }

    // Cancel any ongoing stream
    cancelStream()

    // Load the conversation
    currentConversationId = id
    messages = conversation.messages.map { $0.toChatMessage() }
    currentCompaction = conversation.compaction
    error = nil
  }

  /// Start a new conversation (clears current state)
  func startNewConversation() {
    // Cancel any ongoing stream
    cancelStream()

    // Save current conversation if it has messages
    saveCurrentConversation()

    // Reset state for new conversation
    currentConversationId = nil
    messages = []
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    currentCompaction = nil
    error = nil
  }

  /// Delete a conversation
  /// - Parameter id: Conversation ID to delete
  func deleteConversation(id: String) {
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
  func toggleSidebar() {
    isSidebarVisible.toggle()
  }

  /// Get the current conversation title
  var currentConversationTitle: String {
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
  func sendMessage(_ content: String) async {
    await sendMessage(content, image: nil)
  }

  /// Send a new message to Wagey with an optional image attachment
  /// - Parameters:
  ///   - content: The message content to send
  ///   - image: Optional image attachment
  func sendMessage(_ content: String, image: ImageAttachment?) async {  // swiftlint:disable:this async_without_await
    // Don't send if already streaming, limit reached, or consent revoked
    guard !isStreaming && !limitReached && hasConsentedToAISharing else { return }

    // Clear any previous error
    error = nil

    // Add user message to conversation (with or without image)
    let userMessage: ChatMessage
    if let image = image {
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
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    hadSuccessfulToolCalls = false
    pendingSyncTables = []
    currentAssistantMessageId = UUID().uuidString
    pendingCompactionContent = nil

    // Prepare haptics for token streaming
    Haptics.prepareStreamingHaptics()

    // Create streaming task
    streamTask = Task { @MainActor in
      do {
        // Get user info from AppCoordinator
        let coordinator = AppCoordinator.shared
        guard let userId = coordinator.userId else {
          throw WageyError.notAuthenticated
        }
        let userName = coordinator.userDisplayName.isEmpty ? nil : coordinator.userDisplayName

        let apiPayload = messagesForAPI()

        // Start streaming from WageyService (compact older messages when the conversation is very long)
        let stream = WageyService.shared.streamChat(
          messages: apiPayload.messages,
          userId: userId,
          userName: userName,
          compaction: apiPayload.compaction
        )

        var bufferedChunks: [ChatChunk] = []
        var lastFlushAt = Date()
        let flushInterval = Self.streamFlushInterval

        // Process chunks
        for try await chunk in stream {
          // Check for cancellation
          if Task.isCancelled { break }
          bufferedChunks.append(chunk)
          let shouldFlush =
            !bufferedChunks.isEmpty
            && (!chunk.isDeferrableStreamChunk
              || Date().timeIntervalSince(lastFlushAt) >= flushInterval)
          if shouldFlush {
            let batch = bufferedChunks
            bufferedChunks.removeAll(keepingCapacity: true)
            processChunkBatch(batch)
            lastFlushAt = Date()
          }
        }

        if !bufferedChunks.isEmpty {
          let batch = bufferedChunks
          bufferedChunks.removeAll(keepingCapacity: true)
          processChunkBatch(batch)
        }

        // Finalize the message if not cancelled
        if !Task.isCancelled {
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
  func cancelStream() {
    streamTask?.cancel()
    streamTask = nil

    // Finalize any partial message
    if isStreaming {
      finalizeStreamingText(wasCancelled: true)
    }
  }

  /// Clear the conversation and start a new chat (legacy method, now calls startNewConversation)
  func clearConversation() {
    startNewConversation()
  }

  /// Dismiss the current error
  func dismissError() {
    error = nil
  }

  /// Reset the limit reached flag (called when user upgrades tier)
  /// This allows paid users to continue chatting even if server cache is stale
  func resetLimitReached() {
    limitReached = false
    localMessagesSent = 0
  }

  // MARK: - Private Helpers

  /// Returns messages to send to the API, compacting older messages when the
  /// conversation exceeds the max character threshold.
  private func messagesForAPI() -> (messages: [ChatMessage], compaction: String?) {
    let baseCompaction = currentCompaction

    guard estimatedConversationCharacters > Self.conversationMaxCharacters else {
      return (messages, baseCompaction)
    }

    var truncated: [ChatMessage] = []
    var charCount = 0

    for message in messages.reversed() {
      let messageChars = messageCharacterCount(message)

      if charCount + messageChars > Self.conversationCompactionTargetCharacters
        && !truncated.isEmpty
      {
        break
      }

      charCount += messageChars
      truncated.append(message)
    }

    let recentMessages = truncated.reversed()
    let omittedCount = max(0, messages.count - recentMessages.count)
    let omittedMessages = omittedCount > 0 ? Array(messages.prefix(omittedCount)) : []

    let localCompaction = buildCompactionSummary(for: omittedMessages)
    let combinedCompaction = combinedCompactionSummary(
      base: baseCompaction, appended: localCompaction)

    return (Array(recentMessages), combinedCompaction)
  }

  private func messageCharacterCount(_ message: ChatMessage) -> Int {
    message.contentBlocks.reduce(0) { blockTotal, block in
      switch block {
      case .text(let text):
        return blockTotal + text.count
      case .toolCall(let toolCall):
        return blockTotal + (toolCall.arguments?.count ?? 0) + (toolCall.result?.count ?? 0)
          + toolCall.name.count
      case .image:
        return blockTotal + 64
      }
    }
  }

  private func buildCompactionSummary(for messages: [ChatMessage]) -> String? {
    guard !messages.isEmpty else {
      return nil
    }

    let summaryLines = messages.suffix(Self.compactionMessageLimit).flatMap { message -> [String] in
      var lines: [String] = []
      let speaker = message.role == .user ? "User" : "Assistant"

      if !message.content.isEmpty {
        lines.append("- \(speaker): \(truncateSummaryText(message.content))")
      }

      let imageCount = message.imageAttachments.count
      if imageCount > 0 {
        let suffix = imageCount == 1 ? "" : "s"
        lines.append("- \(speaker): attached \(imageCount) image\(suffix)")
      }

      for toolCall in message.toolCalls ?? [] {
        let outcome = toolCall.success == false ? "failed" : "completed"
        let detail = truncateSummaryText(toolCall.result ?? toolCall.arguments ?? "")
        let detailSuffix = detail.isEmpty ? "" : ": \(detail)"
        lines.append("- Tool \(toolCall.name) \(outcome)\(detailSuffix)")
      }

      return lines
    }

    guard !summaryLines.isEmpty else {
      return nil
    }

    return "Summary of earlier conversation (\(messages.count) messages):\n"
      + summaryLines.joined(separator: "\n")
  }

  private func truncateSummaryText(_ text: String, maxLength: Int = 180) -> String {
    let normalized = text.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    ).trimmingCharacters(in: .whitespacesAndNewlines)

    guard normalized.count > maxLength else {
      return normalized
    }

    let endIndex = normalized.index(normalized.startIndex, offsetBy: maxLength - 1)
    return String(normalized[..<endIndex]) + "..."
  }

  private func combinedCompactionSummary(base: String?, appended: String?) -> String? {
    switch (
      base?.trimmingCharacters(in: .whitespacesAndNewlines),
      appended?.trimmingCharacters(in: .whitespacesAndNewlines)
    ) {
    case (let base?, let appended?) where !base.isEmpty && !appended.isEmpty:
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
  private func triggerEntitlementSync() async {
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
        try? await Task.sleep(for: .seconds(3))
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
  func dismissEntitlementSyncMessage() {
    entitlementSyncMessage = nil
  }

  /// Create a new conversation in the database
  private func createNewConversation() {
    createNewConversation(with: [])
  }

  /// Save the current conversation to the database
  private func saveCurrentConversation() {
    guard let conversationId = currentConversationId else { return }

    let storedMessages = messages.map { StoredChatMessage(from: $0) }
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
  private func processChunk(_ chunk: ChatChunk) {
    switch chunk {
    case .status(let thinking):
      isModelThinking = thinking

    case .textStart:
      shouldStartNewStreamingTextBlock = true

    case .text(let content):
      isModelThinking = false
      // Preserve provider text-block boundaries instead of flattening all text into one run.
      if !shouldStartNewStreamingTextBlock,
        let lastIndex = activeContentBlocks.indices.last,
        case .text(let existingText) = activeContentBlocks[lastIndex]
      {
        activeContentBlocks[lastIndex] = .text(existingText + content)
      } else {
        activeContentBlocks.append(.text(content))
      }
      shouldStartNewStreamingTextBlock = false

      // Light haptic for each token chunk
      Haptics.playStreamingToken()

    case .toolStart(let toolName, let toolCallId, let toolArguments):
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Add a new tool call in progress
      let toolCall = ToolCall(
        id: toolCallId,
        name: toolName,
        arguments: toolArguments,
        result: nil,
        success: nil
      )
      activeContentBlocks.append(.toolCall(toolCall))

    case .toolResult(let toolName, let toolCallId, let result, let success):
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Update the tool call with its result (find by id in content blocks)
      if let index = activeContentBlocks.firstIndex(where: { block in
        if case .toolCall(let tc) = block { return tc.id == toolCallId }
        return false
      }), case .toolCall(let existingToolCall) = activeContentBlocks[index] {
        let updatedToolCall = ToolCall(
          id: toolCallId,
          name: toolName,
          arguments: existingToolCall.arguments,
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

    case .builtInToolStart(let toolName, let toolCallId):
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      let toolCall = ToolCall(
        id: toolCallId,
        name: toolName,
        kind: .builtIn
      )
      activeContentBlocks.append(.toolCall(toolCall))

    case .builtInToolResult(let toolName, let toolCallId, let result, let success):
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      if let index = activeContentBlocks.firstIndex(where: { block in
        if case .toolCall(let tc) = block { return tc.id == toolCallId }
        return false
      }), case .toolCall(let existingToolCall) = activeContentBlocks[index] {
        let updatedToolCall = ToolCall(
          id: toolCallId,
          name: toolName,
          kind: .builtIn,
          arguments: existingToolCall.arguments,
          result: result,
          success: success
        )
        activeContentBlocks[index] = .toolCall(updatedToolCall)
      }

    case .wageyLimit(let remaining, let days, let exceeded, let bonus):
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Update wagey invocations from API response to stay in sync
      // The count is: limit - remaining
      let usedCount = max(0, messageLimit - remaining)
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM"
      let currentMonth = formatter.string(from: Date())
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
      if exceeded && StoreKitManager.shared.currentTier != .free {
        let storeKitTierLimit = Self.messageLimits[StoreKitManager.shared.currentTier] ?? 3
        let currentUsed = wageyInvocations?.effectiveCount ?? 0
        if currentUsed < storeKitTierLimit {
          logger.warning(
            "Entitlement mismatch detected: server says exceeded but StoreKit has tier \(StoreKitManager.shared.currentTier.rawValue)"
          )
          Task {
            await triggerEntitlementSync()
          }
        }
      }

    case .wageyNoAccess:
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
      isModelThinking = false
      shouldStartNewStreamingTextBlock = true
      // Server-side error
      error = WageyError.serverError(message)
    }
  }

  /// Finalize the streaming text into a message
  private func finalizeStreamingText(wasCancelled: Bool = false) {
    let finalizeIncompleteToolCalls = wasCancelled || error != nil
    let finalizedBlocks = finalizedContentBlocks(
      finalizeIncompleteToolCalls: finalizeIncompleteToolCalls)
    let fallbackMessage = Self.fallbackAssistantMessage(
      error: error,
      limitReached: limitReached,
      wasCancelled: wasCancelled || (streamTask?.isCancelled ?? false),
      hasAssistantContent: !finalizedBlocks.isEmpty
    )

    // Only create a message if we have content blocks
    if !finalizedBlocks.isEmpty {
      let assistantMessage = ChatMessage(
        id: currentAssistantMessageId ?? UUID().uuidString,
        role: .assistant,
        contentBlocks: finalizedBlocks,
        sources: activeSources.isEmpty ? nil : activeSources,
        timestamp: Date()
      )
      messages.append(assistantMessage)
      applyPendingCompaction(keepingMessageId: assistantMessage.id)

      // Save after assistant responds
      saveCurrentConversation()
    } else if let fallbackMessage {
      messages.append(
        ChatMessage(
          id: currentAssistantMessageId ?? UUID().uuidString,
          role: .assistant,
          contentBlocks: [.text(fallbackMessage)],
          timestamp: Date()
        ))

      // Surface stream failures inline instead of silently dismissing the typing indicator.
      applyPendingCompaction(keepingMessageId: messages.last?.id)
      saveCurrentConversation()
    } else if let pendingCompactionContent {
      currentCompaction = pendingCompactionContent
      saveCurrentConversation()
    }

    // Trigger sync if any tool calls succeeded (shifts may have changed server-side)
    if hadSuccessfulToolCalls, let userId = cachedUserId ?? AppCoordinator.shared.userId {
      let tablesToSync = Array(pendingSyncTables)
      Task {
        await syncAndNotifyShiftChanges(userId: userId, tables: tablesToSync)
      }
    }

    // Reset streaming state
    activeContentBlocks = []
    shouldStartNewStreamingTextBlock = true
    activeSources = []
    pendingCompactionContent = nil
    hadSuccessfulToolCalls = false
    pendingSyncTables = []
    isStreaming = false
    isModelThinking = false
    currentAssistantMessageId = nil
    streamTask = nil
    if !shouldPresentAlert(for: error) {
      error = nil
    }
  }

  /// Ensures Wagey-created shift changes are pulled locally before notifying UI observers.
  /// Retries when another sync is already in progress to avoid stale reloads.
  private func syncAndNotifyShiftChanges(userId: String, tables: [SyncTable]) async {
    guard !tables.isEmpty else { return }

    let alreadySyncingError = "Sync already in progress"
    let retryIntervalNanoseconds: UInt64 = 250_000_000
    let retryDeadline = Date().addingTimeInterval(30)
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

    NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
  }

  private func processChunkBatch(_ chunks: [ChatChunk]) {
    for chunk in chunks {
      processChunk(chunk)
    }
  }

  private func createNewConversation(with messages: [ChatMessage]) {
    guard let userId = cachedUserId ?? AppCoordinator.shared.userId else { return }

    let conversation = conversationsRepository.createConversation(
      for: userId,
      title: "New Conversation",
      messages: messages.map { StoredChatMessage(from: $0) },
      compaction: currentCompaction
    )
    currentConversationId = conversation.id
    upsertConversation(conversation)
  }

  private func upsertConversation(_ conversation: LocalConversation) {
    conversations.removeAll { $0.id == conversation.id }
    conversations.insert(conversation, at: 0)
    conversations.sort { $0.updatedAt > $1.updatedAt }
  }

  private func syncTables(for toolName: String) -> Set<SyncTable> {
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
    case "manage_settings":
      return [.userSettings]
    default:
      return []
    }
  }

  private func applyPendingCompaction(keepingMessageId: String?) {
    guard let pendingCompactionContent else { return }
    currentCompaction = pendingCompactionContent

    guard let keepingMessageId,
      let index = messages.firstIndex(where: { $0.id == keepingMessageId })
    else {
      return
    }

    messages = Array(messages.suffix(from: index))
  }

  private func finalizedContentBlocks(finalizeIncompleteToolCalls: Bool) -> [ContentBlock] {
    guard finalizeIncompleteToolCalls else { return activeContentBlocks }

    return activeContentBlocks.compactMap { block in
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
      }
    }
  }

  private func interruptedToolCall(from toolCall: ToolCall) -> ToolCall {
    ToolCall(
      id: toolCall.id,
      name: toolCall.name,
      kind: toolCall.kind,
      arguments: toolCall.arguments,
      result: interruptedToolResultPayload(),
      success: false
    )
  }

  private func interruptedToolResultPayload() -> String {
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

  private func shouldPresentAlert(for error: Error?) -> Bool {
    guard let error else { return false }

    switch error {
    case is WageyServiceError:
      return false
    case WageyError.serverError(_), WageyError.noAccess:
      return false
    default:
      return true
    }
  }

  static func fallbackAssistantMessage(
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
}

extension ChatChunk {
  fileprivate var isDeferrableStreamChunk: Bool {
    switch self {
    case .status:
      return true
    case .textStart, .toolStart, .toolResult, .builtInToolStart, .builtInToolResult, .done, .error,
      .wageyLimit, .wageyNoAccess, .sources, .compaction, .unknown, .text:
      return false
    }
  }
}

// MARK: - Wagey Errors

/// Errors specific to the Wagey feature
enum WageyError: LocalizedError {
  case notAuthenticated
  case noAccess
  case serverError(String)
  case networkError(Error)

  var errorDescription: String? {
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
