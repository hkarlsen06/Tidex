import SwiftData
import SwiftUI
import UIKit
import os

private let launchLog = Logger(subsystem: "no.tidex.app", category: "Launch")

extension Notification.Name {
  static let restartPreAuthOnboarding = Notification.Name("restartPreAuthOnboarding")
}

/// Root view wrapper that ensures a seamless launch experience.
///
/// The first SwiftUI frame renders a lightweight `LoadingView` that only depends
/// on cached appearance state. This guarantees the frame is committed before iOS
/// removes the launch storyboard, preventing the black-flash issue that can occur
/// when heavier singletons trigger initialization during the first body evaluation.
///
/// After the initial frame is on screen, `isReady` flips and `RootContent` is
/// created, which initializes `AppCoordinator` and other heavier singletons.
struct RootView: View {
  @State private var isReady = false

  #if DEBUG
    private let uiTestingConfiguration = UITestingConfiguration.current
  #endif

  var body: some View {
    #if DEBUG
      if let uiTestingConfiguration {
        UITestingRootView(configuration: uiTestingConfiguration)
      } else if isReady {
        RootContent()
      } else {
        LoadingView()
          .task {
            // The .task fires after the view has appeared on screen.
            // Flipping isReady triggers RootContent creation (with singletons)
            // while LoadingView is already visible — no black gap.
            isReady = true
          }
      }
    #else
      if isReady {
        RootContent()
      } else {
        LoadingView()
          .task {
            // The .task fires after the view has appeared on screen.
            // Flipping isReady triggers RootContent creation (with singletons)
            // while LoadingView is already visible — no black gap.
            isReady = true
          }
      }
    #endif
  }
}

/// Actual root content that manages the app's navigation based on authentication state.
/// Handles transitions between: Loading -> Onboarding -> Login -> MFA -> Post-Auth Onboarding -> Dashboard
private struct RootContent: View {
  // Note: Using @ObservedObject for singletons as @StateObject is meant for owned instances
  @ObservedObject private var coordinator = AppCoordinator.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  // Theme is handled at UIKit window level - no need to observe AppearanceManager here

  // Onboarding state - explicit naming for two-phase onboarding
  @AppStorage("hasCompletedPreAuthOnboarding") private var hasCompletedPreAuthOnboarding = false
  @AppStorage("hasCompletedPostAuthOnboarding") private var hasCompletedPostAuthOnboarding = false

  // Navigation state for transitioning from onboarding to auth
  @State private var showAuthAfterOnboarding = false
  @State private var authDestination: AuthDestination = .login

  // Storage warning state - shown when LocalStore falls back to in-memory storage
  @State private var showStorageWarning = false
  @State private var activeChatToast: InAppChatToastPayload?
  @State private var chatToastDismissTask: Task<Void, Never>?
  @State private var showPasswordRecovery = false

  enum AuthDestination {
    case login
    case signup
  }

  var body: some View {
    let postAuthOnboardingPresentation = coordinator.currentPostAuthOnboardingPresentation(
      hasCompletedLocally: hasCompletedPostAuthOnboarding
    )

    ZStack {
      rootBackground

      // Content based on app state
      Group {
        switch coordinator.appState {
        case .loading:
          LoadingView()

        case .unauthenticated:
          if !hasCompletedPreAuthOnboarding && !showAuthAfterOnboarding {
            // Show pre-auth onboarding (screens 1-3)
            OnboardingView(
              onNavigateToSignup: {
                completePreAuthOnboarding(destination: .signup)
              }
            )
            .transition(.opacity)
          } else {
            // Show auth navigation with the selected destination
            AuthNavigationView(initialScreen: authDestination == .signup ? .signup : .login)
              .transition(.opacity)
          }

        case .mfaRequired:
          if let factor = coordinator.pendingMFAFactor {
            MFAVerifyView(factor: factor, coordinator: coordinator)
              .transition(.opacity)
          } else {
            // Fallback - shouldn't happen
            AuthNavigationView()
          }

        case .termsRequired:
          AcceptTermsView(isUpdate: coordinator.isTermsUpdate, coordinator: coordinator)
            .transition(.opacity)

        case .authenticated:
          if let entryMode = postAuthOnboardingPresentation.entryMode {
            PostAuthOnboardingView(
              entryMode: entryMode,
              onComplete: {
                hasCompletedPostAuthOnboarding = true
                coordinator.dismissPostAuthOnboarding(markCompletedRemotely: true)
              },
              onClose: {
                coordinator.dismissPostAuthOnboarding()
              },
              userId: coordinator.userId ?? ""
            )
            .transition(.opacity)
          } else {
            MainTabView()
              .overlay(alignment: .top) {
                if let activeChatToast {
                  InAppChatToastView(
                    payload: activeChatToast,
                    onTap: {
                      dismissChatToast()
                      guard activeChatToast.destination == .friendChat,
                        !activeChatToast.threadId.isEmpty
                      else {
                        return
                      }

                      coordinator.pendingDeepLink = .friendChat(
                        threadId: activeChatToast.threadId,
                        messageId: activeChatToast.messageId,
                        senderUserId: activeChatToast.senderUserId,
                        typingUserId: activeChatToast.typingUserId,
                        navigationRequestId: UUID()
                      )
                    },
                    onDismiss: {
                      dismissChatToast()
                    }
                  )
                  .frame(maxWidth: AdaptiveMaxWidth.tabContent)
                  .padding(.horizontal, Spacing.md)
                  .padding(.top, 8)
                  .transition(.move(edge: .top).combined(with: .opacity))
                  .zIndex(10)
                }
              }
          }
        }
      }
    }
    .fullScreenCover(isPresented: $showPasswordRecovery) {
      ResetPasswordView(
        presentationMode: .recovery,
        onNavigateToLogin: {
          showPasswordRecovery = false
          NotificationCenter.default.post(name: .tidexNavigateToLoginRequested, object: nil)
        }
      )
      .interactiveDismissDisabled()
    }
    .motionAnimation(
      .pageTransition, value: hasCompletedPreAuthOnboarding, reduceMotion: reduceMotion
    )
    .motionAnimation(
      .pageTransition, value: hasCompletedPostAuthOnboarding, reduceMotion: reduceMotion
    )
    .environmentObject(coordinator)
    // Theme is handled at UIKit window level via AppearanceManager.applyToWindows()
    // Don't use .preferredColorScheme() here as it conflicts with window.overrideUserInterfaceStyle
    .onAppear {
      launchLog.info(
        "[Launch] RootContent.onAppear – appState=\(String(describing: coordinator.appState))")
      coordinator.refreshPostAuthOnboardingPresentation(
        hasCompletedLocally: hasCompletedPostAuthOnboarding
      )
    }
    .onAppear {
      Task { @MainActor in
        // Defer storage initialization until after first render to avoid launch stalls.
        await Task.yield()
        if LocalStore.shared.isUsingInMemoryFallback {
          showStorageWarning = true
        }
      }
    }
    .alert(String(localized: .alertsStorageIssueTitle), isPresented: $showStorageWarning) {
      Button(String(localized: .alertsOk), role: .cancel) {}
    } message: {
      Text(.alertsStorageIssueMessage)
    }
    .onReceive(NotificationCenter.default.publisher(for: .restartPreAuthOnboarding)) { _ in
      restartPreAuthOnboarding()
    }
    .onReceive(NotificationCenter.default.publisher(for: .inAppChatToastRequested)) {
      notification in
      guard coordinator.appState == .authenticated,
        let payload = notification.object as? InAppChatToastPayload
      else {
        return
      }

      showChatToast(payload)
    }
    .onReceive(NotificationCenter.default.publisher(for: .tidexPasswordRecoveryRequested)) { _ in
      authDestination = .login
      showAuthAfterOnboarding = true
      showPasswordRecovery = true
    }
    .onChange(of: coordinator.appState) { _, _ in
      coordinator.refreshPostAuthOnboardingPresentation(
        hasCompletedLocally: hasCompletedPostAuthOnboarding
      )
    }
    .onChange(of: coordinator.hasFinishedOnboardingRemotely) { _, _ in
      coordinator.refreshPostAuthOnboardingPresentation(
        hasCompletedLocally: hasCompletedPostAuthOnboarding
      )
    }
    .onChange(of: hasCompletedPostAuthOnboarding) { _, newValue in
      coordinator.refreshPostAuthOnboardingPresentation(hasCompletedLocally: newValue)
    }
    .onDisappear {
      chatToastDismissTask?.cancel()
      chatToastDismissTask = nil
    }
  }

  @ViewBuilder
  private var rootBackground: some View {
    switch coordinator.appState {
    case .unauthenticated:
      Color.tidexBackground
        .ignoresSafeArea()
    default:
      TidexAppBackground()
    }
  }

  private func showChatToast(_ payload: InAppChatToastPayload) {
    chatToastDismissTask?.cancel()
    withAnimation(.spring(duration: 0.32, bounce: 0.14)) {
      activeChatToast = payload
    }

    chatToastDismissTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      dismissChatToast()
    }
  }

  private func dismissChatToast() {
    chatToastDismissTask?.cancel()
    chatToastDismissTask = nil
    withAnimation(.spring(duration: 0.28, bounce: 0.08)) {
      activeChatToast = nil
    }
  }

  private func completePreAuthOnboarding(destination: AuthDestination) {
    performWithoutRootTransition {
      hasCompletedPreAuthOnboarding = true
      authDestination = destination
      showAuthAfterOnboarding = true
    }
  }

  private func restartPreAuthOnboarding() {
    performWithoutRootTransition {
      hasCompletedPreAuthOnboarding = false
      showAuthAfterOnboarding = false
      authDestination = .login
    }
  }

  private func performWithoutRootTransition(_ updates: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, updates)
  }
}

// MARK: - Loading View

/// Initial loading view shown while checking authentication state
/// Matches the splash screen exactly, with a spinner below the logo
struct LoadingView: View {
  @ObservedObject private var appearanceManager = AppearanceManager.shared
  @Environment(\.colorScheme) private var systemColorScheme

  private var launchBackgroundColor: Color {
    let userInterfaceStyle: UIUserInterfaceStyle

    switch appearanceManager.theme.resolvedColorScheme(fallback: systemColorScheme) {
    case .light:
      userInterfaceStyle = .light
    case .dark:
      userInterfaceStyle = .dark
    @unknown default:
      userInterfaceStyle = .light
    }

    let traits = UITraitCollection(userInterfaceStyle: userInterfaceStyle)
    if let color = UIColor(named: "LaunchBackground", in: .main, compatibleWith: traits) {
      return Color(uiColor: color)
    }

    return .tidexLaunchBackground
  }

  var body: some View {
    ZStack {
      // Use the cached app theme so the first SwiftUI frame matches the
      // user's last-selected appearance as early as possible.
      launchBackgroundColor

      // Center the logo without reading container geometry during launch.
      Image("SplashLaunch")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 150, height: 150)

      ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
        .scaleEffect(1.2)
        .offset(y: 105)
    }
    .ignoresSafeArea()
    .onAppear {
      launchLog.info("[Launch] LoadingView.onAppear – first SwiftUI frame visible")
    }
  }
}

#Preview("Root View") {
  RootView()
}

#Preview("Loading View") {
  ZStack {
    TidexAppBackground()
    LoadingView()
  }
}

#if DEBUG
  private struct UITestingConfiguration {
    enum Scenario: String {
      case friendsChat = "friends-chat"
      case friendsChatReply = "friends-chat-reply"
      case wageyHistoryDelete = "wagey-history-delete"
    }

    let scenario: Scenario

    static var current: UITestingConfiguration? {
      let processInfo = ProcessInfo.processInfo
      guard processInfo.arguments.contains("-ui-testing") else { return nil }

      let rawScenario =
        processInfo.environment["TIDEX_UI_TEST_SCENARIO"] ?? Scenario.friendsChat.rawValue
      let scenario = Scenario(rawValue: rawScenario) ?? .friendsChat
      return UITestingConfiguration(scenario: scenario)
    }
  }

  private struct UITestingRootView: View {
    let configuration: UITestingConfiguration

    var body: some View {
      switch configuration.scenario {
      case .friendsChat, .friendsChatReply:
        FriendsThreadUITestHostView(configuration: configuration)
      case .wageyHistoryDelete:
        WageyHistoryUITestHostView()
      }
    }
  }

  private struct WageyHistoryUITestHostView: View {
    @State private var conversations: [LocalConversation] = [
      LocalConversation(
        id: "ui-test-conversation-1",
        userId: "UI-TEST-USER",
        title: "Review overtime rules",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
      ),
      LocalConversation(
        id: "ui-test-conversation-2",
        userId: "UI-TEST-USER",
        title: "Holiday pay question",
        messages: [],
        createdAt: Date(timeIntervalSince1970: 1_700_000_100),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
      ),
    ]
    @State private var currentConversationId: String? = "ui-test-conversation-1"

    var body: some View {
      NavigationStack {
        ConversationSidebarView(
          conversations: conversations,
          currentConversationId: currentConversationId,
          onSelectConversation: { id in
            currentConversationId = id
          },
          onNewConversation: {
            currentConversationId = nil
          },
          onDeleteConversation: { id in
            conversations.removeAll { $0.id == id }
            if currentConversationId == id {
              currentConversationId = conversations.first?.id
            }
          }
        )
      }
    }
  }

  private struct FriendsThreadUITestHostView: View {
    let configuration: UITestingConfiguration

    @State private var viewModel: FriendsThreadViewModel?
    @State private var errorMessage: String?

    var body: some View {
      Group {
        if let viewModel {
          NavigationStack {
            FriendsThreadView(viewModel: viewModel)
          }
        } else if let errorMessage {
          Text(errorMessage)
            .accessibilityIdentifier("ui-testing.error")
        } else {
          ProgressView()
            .accessibilityIdentifier("ui-testing.loading")
        }
      }
      .task {
        guard viewModel == nil, errorMessage == nil else { return }

        do {
          viewModel = try await makeViewModel(for: configuration.scenario)
        } catch {
          errorMessage = error.localizedDescription
        }
      }
    }

    private func makeViewModel(
      for scenario: UITestingConfiguration.Scenario
    ) async throws -> FriendsThreadViewModel {
      let storage = try FriendsThreadUITestStorage.make()
      let thread = FriendsThreadUITestFixtures.thread
      let service = FriendsThreadUITestService(
        threadSummary: thread,
        messages: FriendsThreadUITestFixtures.messages
      )

      await storage.repository.saveThread(thread, for: FriendsThreadUITestFixtures.viewerUserId)
      await storage.repository.saveMessages(
        FriendsThreadUITestFixtures.messages,
        in: thread.id,
        for: FriendsThreadUITestFixtures.viewerUserId
      )

      AppCoordinator.shared.configureForUITesting(
        userId: FriendsThreadUITestFixtures.viewerUserId,
        displayName: FriendsThreadUITestFixtures.viewerDisplayName
      )

      let viewModel = FriendsThreadViewModel(
        route: FriendsThreadUITestFixtures.route,
        viewerUserId: FriendsThreadUITestFixtures.viewerUserId,
        service: service,
        capabilities: FriendsThreadUITestCapabilities(),
        shareVisibilityResolver: FriendsThreadUITestShareVisibilityResolver(),
        sharingPreviewService: FriendsThreadUITestSharingPreviewService(),
        sharedShiftsCache: FriendsThreadUITestSharedShiftsCache(),
        repository: storage.repository,
        composerDraftStore: storage.draftStore,
        realtimeCoordinator: FriendsThreadUITestRealtimeCoordinator()
      )

      if scenario == .friendsChatReply,
        let replyTarget = FriendsThreadUITestFixtures.messages.first
      {
        viewModel.setReplyTarget(replyTarget)
      }

      return viewModel
    }
  }

  private enum FriendsThreadUITestFixtures {
    static let viewerUserId = "ui-test-viewer"
    static let viewerDisplayName = "UITest Viewer"
    static let counterpartUserId = "ui-test-friend"

    static let thread = FriendThread(
      id: "ui-test-thread",
      kind: .direct,
      title: nil,
      avatarUrl: nil,
      metadataData: nil,
      counterpartUserId: counterpartUserId,
      counterpartDisplayName: "UITest Friend",
      counterpartProfilePictureUrl: nil,
      counterpartOAuthAvatarUrl: nil,
      lastMessageId: "ui-test-outgoing-1",
      lastMessageSenderId: viewerUserId,
      lastMessageAt: Date(timeIntervalSince1970: 1_762_000_120),
      lastMessageBody: "Earlier outgoing message",
      lastMessageHasImage: false,
      unreadCount: 1,
      muted: false,
      createdAt: Date(timeIntervalSince1970: 1_762_000_000)
    )

    static let route = FriendChatRoute(
      thread: thread,
      fallbackDisplayName: "UITest Friend",
      fallbackAvatarUrl: nil
    )

    static let messages: [FriendMessage] = [
      FriendMessage(
        id: "ui-test-incoming-1",
        threadId: thread.id,
        senderUserId: counterpartUserId,
        messageType: .user,
        body: "Initial incoming message",
        clientId: "",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_762_000_060),
        editedAt: nil,
        deletedAt: nil,
        metadataData: nil,
        attachments: [],
        reactions: [],
        sendState: .sent,
        failureMessage: nil
      ),
      FriendMessage(
        id: "ui-test-outgoing-1",
        threadId: thread.id,
        senderUserId: viewerUserId,
        messageType: .user,
        body: "Earlier outgoing message",
        clientId: "ui-test-outgoing-client-1",
        replyToMessageId: nil,
        createdAt: Date(timeIntervalSince1970: 1_762_000_120),
        editedAt: nil,
        deletedAt: nil,
        metadataData: nil,
        attachments: [],
        reactions: [],
        sendState: .sent,
        failureMessage: nil
      ),
    ]
  }

  private struct FriendsThreadUITestStorage {
    let repository: FriendsMessagesRepository
    let draftStore: FriendsComposerDraftStore

    @MainActor
    static func make() throws -> FriendsThreadUITestStorage {
      let schema = Schema([
        LocalPendingFriendComposerDraft.self,
        LocalThread.self,
        LocalThreadState.self,
        LocalMessage.self,
        LocalMessageAttachment.self,
        LocalMessageReaction.self,
      ])

      let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        allowsSave: true
      )

      let container = try ModelContainer(for: schema, configurations: [configuration])
      let storeActor = LocalStoreActor(modelContainer: container)

      return FriendsThreadUITestStorage(
        repository: FriendsMessagesRepository(container: container, storeActor: storeActor),
        draftStore: FriendsComposerDraftStore(container: container, storeActor: storeActor)
      )
    }
  }

  private struct FriendsThreadUITestCapabilities: FriendsMessagingCapabilityProviding {
    let canSendShiftSnapshots = false
  }

  @MainActor
  private final class FriendsThreadUITestShareVisibilityResolver:
    FriendsThreadShareVisibilityResolving
  {
    func canCounterpartSeeOwnerEarnings(counterpartUserId _: String) async throws -> Bool {
      await Task.yield()
      return false
    }

    func invalidateCachedVisibility(counterpartUserId _: String?) {}
  }

  @MainActor
  private final class FriendsThreadUITestSharingPreviewService: SharingPreviewProviding {
    func fetchShiftPreviews(sharerIds _: [String], forceRefresh _: Bool) async throws
      -> [SharerShiftPreview]
    {
      await Task.yield()
      return []
    }
  }

  @MainActor
  private final class FriendsThreadUITestSharedShiftsCache: SharedShiftsCaching {
    func getCachedFriends(
      for _: String,
      includeHidden _: Bool
    ) -> SharedShiftsRepository.CachedFriendsSnapshot {
      .init(sharers: [], chatOnlyUserIds: [])
    }

    func getShiftPreviews(for _: String) -> [String: SharerShiftPreview] {
      [:]
    }

    func saveShiftPreviews(_: [SharerShiftPreview], for _: String) async {
      await Task.yield()
    }
  }

  @MainActor
  private final class FriendsThreadUITestRealtimeCoordinator: FriendsMessagingRealtimeCoordinating {
    func startForAuthenticatedUser(viewerUserId _: String) async { await Task.yield() }
    func stopForAuthenticatedUser() async { await Task.yield() }
    func handleAppDidBecomeActive() async { await Task.yield() }
    func setFriendsFeedVisible(_: Bool) {}
    func setVisibleThreadIds(_: [String]) {}
    func setActiveThread(threadId _: String, viewerUserId _: String) async { await Task.yield() }
    func clearActiveThread(threadId _: String) async { await Task.yield() }
    func startThreadListSubscription(viewerUserId _: String) async { await Task.yield() }
    func stopThreadListSubscription() async { await Task.yield() }
    func startThreadSubscription(threadId _: String, viewerUserId _: String) async {
      await Task.yield()
    }
    func stopThreadSubscription(threadId _: String) async { await Task.yield() }
    func sendTypingStart(threadId _: String, userId _: String) async -> Bool {
      await Task.yield()
      return true
    }
    func sendTypingStop(threadId _: String, userId _: String) async -> Bool {
      await Task.yield()
      return true
    }
  }

  @MainActor
  private final class FriendsThreadUITestService: FriendsMessagingServiceProviding {
    private var threadSummary: FriendThread
    private var messages: [FriendMessage]
    private var sentMessageCount = 0

    init(threadSummary: FriendThread, messages: [FriendMessage]) {
      self.threadSummary = threadSummary
      self.messages = messages
    }

    func getOrCreateDirectThread(otherUserId _: String) async throws -> FriendThread {
      await Task.yield()
      return threadSummary
    }

    func listMyThreads(limit _: Int, before _: FriendThreadCursor?) async throws -> [FriendThread] {
      await Task.yield()
      return [threadSummary]
    }

    func fetchInboxSyncSnapshotV2(limit _: Int, before _: FriendThreadCursor?) async throws
      -> FriendInboxSyncSnapshot
    {
      await Task.yield()
      return FriendInboxSyncSnapshot(
        threads: [threadSummary],
        unreadDirectMessageCount: 0,
        nextCursor: nil,
        snapshotVersion: 0,
        retainedFromVersion: 0,
        hasMore: false
      )
    }

    func listInboxEventsV2(afterVersion _: Int64, limit _: Int) async throws
      -> FriendInboxSyncEventsPage
    {
      await Task.yield()
      return FriendInboxSyncEventsPage(
        requiresSnapshot: false,
        latestVersion: 0,
        retainedFromVersion: 0,
        hasMore: false,
        events: []
      )
    }

    func listThreadMessages(
      threadId _: String,
      limit _: Int,
      before _: FriendMessageCursor?
    ) async throws -> [FriendMessage] {
      await Task.yield()
      return messages
    }

    func listThreadMessagesV2(
      threadId _: String,
      limit _: Int,
      before _: FriendMessageCursor?
    ) async throws -> FriendThreadMessagesPage {
      await Task.yield()
      return FriendThreadMessagesPage(
        messages: messages,
        nextCursor: nil,
        hasMore: false
      )
    }

    func fetchThreadSyncSnapshotV2(threadId _: String, messageLimit _: Int) async throws
      -> FriendThreadSyncSnapshot
    {
      await Task.yield()
      let viewerState = FriendThreadState(
        threadId: threadSummary.id,
        userId: FriendsThreadUITestFixtures.viewerUserId,
        lastReadMessageId: messages.last?.id,
        lastReadAt: messages.last?.createdAt,
        muted: threadSummary.muted,
        updatedAt: Date()
      )

      return FriendThreadSyncSnapshot(
        thread: threadSummary,
        viewerState: viewerState,
        counterpartPresence: threadSummary.counterpartUserId.map {
          FriendThreadCounterpartPresence(
            userId: $0,
            displayName: threadSummary.counterpartDisplayName,
            profilePictureUrl: threadSummary.counterpartProfilePictureUrl,
            oauthAvatarUrl: threadSummary.counterpartOAuthAvatarUrl
          )
        },
        messages: messages,
        nextCursor: nil,
        snapshotVersion: 0,
        retainedFromVersion: 0,
        hasMore: false
      )
    }

    func listThreadEventsV2(threadId _: String, afterVersion _: Int64, limit _: Int) async throws
      -> FriendThreadSyncEventsPage
    {
      await Task.yield()
      return FriendThreadSyncEventsPage(
        requiresSnapshot: false,
        latestVersion: 0,
        retainedFromVersion: 0,
        hasMore: false,
        events: []
      )
    }

    func sendMessage(
      threadId: String,
      clientId: String,
      body: String?,
      replyToMessageId: String?,
      attachments _: [FriendOutgoingAttachment],
      metadataData: Data?
    ) async throws -> FriendMessage {
      await Task.yield()
      sentMessageCount += 1

      let message = FriendMessage(
        id: "ui-test-sent-\(sentMessageCount)",
        threadId: threadId,
        senderUserId: FriendsThreadUITestFixtures.viewerUserId,
        messageType: .user,
        body: body,
        clientId: clientId,
        replyToMessageId: replyToMessageId,
        createdAt: Date(timeIntervalSince1970: 1_762_000_200 + Double(sentMessageCount)),
        editedAt: nil,
        deletedAt: nil,
        metadataData: metadataData,
        attachments: [],
        reactions: [],
        sendState: .sent,
        failureMessage: nil
      )

      messages.append(message)
      threadSummary = FriendThread(
        id: threadSummary.id,
        kind: threadSummary.kind,
        title: threadSummary.title,
        avatarUrl: threadSummary.avatarUrl,
        metadataData: threadSummary.metadataData,
        counterpartUserId: threadSummary.counterpartUserId,
        counterpartDisplayName: threadSummary.counterpartDisplayName,
        counterpartProfilePictureUrl: threadSummary.counterpartProfilePictureUrl,
        counterpartOAuthAvatarUrl: threadSummary.counterpartOAuthAvatarUrl,
        lastMessageId: message.id,
        lastMessageSenderId: message.senderUserId,
        lastMessageAt: message.createdAt,
        lastMessageBody: message.body,
        lastMessageHasImage: message.attachments.contains(where: { $0.kind == .image }),
        unreadCount: 0,
        muted: threadSummary.muted,
        createdAt: threadSummary.createdAt
      )

      return message
    }

    func editMessage(messageId: String, body: String) async throws -> FriendMessage {
      await Task.yield()
      guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
        throw FriendsMessagingServiceError.httpError(statusCode: 404, message: "Message not found")
      }

      let updated = messages[index].withEditedBody(body, editedAt: Date())
      messages[index] = updated
      return updated
    }

    func deleteMessage(messageId: String) async throws -> FriendThread {
      await Task.yield()
      messages.removeAll { $0.id == messageId }
      return threadSummary
    }

    func markThreadRead(threadId: String, throughMessageId: String) async throws
      -> FriendThreadState
    {
      await Task.yield()
      return FriendThreadState(
        threadId: threadId,
        userId: FriendsThreadUITestFixtures.viewerUserId,
        lastReadMessageId: throughMessageId,
        lastReadAt: Date(),
        muted: false,
        updatedAt: Date()
      )
    }

    func setThreadMuted(threadId: String, muted: Bool) async throws -> FriendThreadState {
      await Task.yield()
      return FriendThreadState(
        threadId: threadId,
        userId: FriendsThreadUITestFixtures.viewerUserId,
        lastReadMessageId: nil,
        lastReadAt: nil,
        muted: muted,
        updatedAt: Date()
      )
    }

    func queueThreadTypingNotification(threadId _: String) async throws -> Bool {
      await Task.yield()
      return false
    }

    func fetchUnreadDirectMessageCount(userId _: String) async throws -> Int {
      await Task.yield()
      return 0
    }

    func fetchThreadSummary(threadId _: String) async throws -> FriendThread {
      await Task.yield()
      return threadSummary
    }

    func fetchThreadState(threadId _: String, userId _: String) async throws -> FriendThreadState? {
      await Task.yield()
      return nil
    }

    func listThreadStates(threadId _: String) async throws -> [FriendThreadState] {
      await Task.yield()
      return []
    }

    func fetchMessagePayload(messageId: String) async throws -> FriendMessage {
      await Task.yield()
      guard let message = messages.first(where: { $0.id == messageId }) else {
        throw FriendsMessagingServiceError.httpError(statusCode: 404, message: "Message not found")
      }
      return message
    }

    func fetchMessageSyncPayloadV2(messageId: String) async throws -> FriendMessage {
      try await fetchMessagePayload(messageId: messageId)
    }

    func toggleMessageReaction(
      messageId: String,
      emoji: String,
      attachmentId: String?
    ) async throws -> FriendMessage {
      await Task.yield()
      guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
        throw FriendsMessagingServiceError.httpError(statusCode: 404, message: "Message not found")
      }

      let message = messages[index]
      let updated = message.toggledReaction(emoji: emoji, attachmentId: attachmentId)
      messages[index] = updated
      return updated
    }

    func createAbuseReport(
      threadId _: String,
      reportedUserId _: String,
      messageId _: String?,
      reason _: FriendAbuseReportReason
    ) async throws {
      await Task.yield()
    }

    func blockUserPair(otherUserId _: String) async throws {
      await Task.yield()
    }

    func uploadImageAttachment(threadId _: String, image _: ImageAttachment) async throws
      -> FriendOutgoingAttachment
    {
      await Task.yield()
      return FriendOutgoingAttachment(
        attachmentId: "ui-test-upload",
        storagePath: "ui-testing/image.jpg",
        mimeType: "image/jpeg",
        byteSize: 0,
        width: nil,
        height: nil
      )
    }

    func downloadAttachmentData(path _: String) async throws -> Data {
      await Task.yield()
      return Data()
    }
  }
#endif
