import SwiftUI

struct FriendsThreadView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @StateObject private var viewModel: FriendsThreadViewModel
  @State private var lastScrolledMessageId: String?

  init(route: FriendChatRoute, viewerUserId: String) {
    _viewModel = StateObject(
      wrappedValue: FriendsThreadViewModel(route: route, viewerUserId: viewerUserId)
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      Divider()
        .overlay(Color.tidexBorderSubtle)

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: Spacing.sm) {
            if viewModel.isLoading && viewModel.messages.isEmpty {
              loadingState
            } else if viewModel.messages.isEmpty {
              emptyState
            } else {
              ForEach(viewModel.messages) { message in
                messageRow(message)
                  .id(message.id)
              }
            }
          }
          .padding(.horizontal, Spacing.md)
          .padding(.vertical, Spacing.md)
        }
        .background(Color.tidexBackground)
        .onAppear {
          scrollToBottom(using: proxy, animated: false)
        }
        .onChange(of: viewModel.messages.last?.id) { _, _ in
          scrollToBottom(using: proxy, animated: !reduceMotion)
        }
      }

      composer
    }
    .background(Color.tidexBackground.ignoresSafeArea())
    .navigationTitle(viewModel.thread.counterpartDisplayName ?? viewModel.route.displayName)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadIfNeeded()
    }
    .refreshable {
      await viewModel.refresh()
    }
    .onDisappear {
      Task {
        await viewModel.stopRealtime()
      }
    }
  }

  private var loadingState: some View {
    VStack(spacing: Spacing.sm) {
      ProgressView()
      Text(.friendsChatLoading)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Spacing.xxl)
  }

  private var emptyState: some View {
    VStack(spacing: Spacing.sm) {
      Image(systemName: "message")
        .font(.system(size: 26, weight: .semibold))
        .foregroundColor(.tidexBlue)
        .padding(14)
        .background(
          Circle()
            .fill(Color.tidexBlue.opacity(0.12))
        )

      Text(.friendsChatEmptyTitle)
        .font(.tidexHeadline)
        .foregroundColor(.tidexTextPrimary)

      Text(String(localized: .friendsChatEmptyDescription(viewModel.route.displayName)))
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, Spacing.xxl)
    .padding(.horizontal, Spacing.lg)
  }

  private func messageRow(_ message: FriendMessage) -> some View {
    let isCurrentUser = message.senderUserId == AppCoordinator.shared.getCurrentUserId()

    return HStack {
      if isCurrentUser { Spacer(minLength: 48) }

      VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: Spacing.xxs) {
        if let body = message.body, !body.isEmpty {
          Text(body)
            .font(.tidexBody)
            .foregroundColor(isCurrentUser ? .tidexTextOnBrand : .tidexTextPrimary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous)
                .fill(isCurrentUser ? Color.tidexBrandPrimary : Color.tidexSurfacePrimary)
            )
            .overlay(
              RoundedRectangle(cornerRadius: CornerRadius.bubble, style: .continuous)
                .stroke(
                  isCurrentUser ? Color.clear : Color.tidexBorderSubtle,
                  lineWidth: 1
                )
            )
            .frame(maxWidth: 280, alignment: isCurrentUser ? .trailing : .leading)
        }

        Text(message.createdAt.formatted(.dateTime.hour().minute()))
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
      }

      if !isCurrentUser { Spacer(minLength: 48) }
    }
  }

  private var composer: some View {
    VStack(spacing: Spacing.xs) {
      if let sendErrorMessage = viewModel.sendErrorMessage {
        HStack(spacing: Spacing.xs) {
          Text(sendErrorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)

          Spacer()

          Button {
            Task {
              await viewModel.sendDraft()
            }
          } label: {
            Text(.friendsChatRetry)
              .font(.tidexFootnoteMedium)
              .foregroundColor(.tidexBlue)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
      }

      HStack(alignment: .bottom, spacing: Spacing.sm) {
        TextField(
          String(localized: .friendsChatPlaceholder),
          text: $viewModel.draft,
          axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(.tidexBody)
        .lineLimit(1...5)
        .disabled(viewModel.isSending)

        Button {
          Task {
            await viewModel.sendDraft()
          }
        } label: {
          Group {
            if viewModel.isSending {
              ProgressView()
                .progressViewStyle(.circular)
                .tint(.tidexTextOnBrand)
            } else {
              Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.tidexTextOnBrand)
            }
          }
          .frame(width: 38, height: 38)
        }
        .background(
          Circle()
            .fill(canSend ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
        )
        .disabled(!canSend)
      }
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(Color.tidexSurfacePrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .padding(.horizontal, Spacing.md)
      .padding(.top, Spacing.xs)
      .padding(.bottom, MonthPickerLayout.bottomPadding)
      .background(Color.tidexBackground)
    }
  }

  private var canSend: Bool {
    !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
  }

  private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
    guard let lastMessageId = viewModel.messages.last?.id, lastMessageId != lastScrolledMessageId
    else {
      return
    }

    lastScrolledMessageId = lastMessageId

    let action = {
      proxy.scrollTo(lastMessageId, anchor: .bottom)
    }

    if animated {
      withAnimation(.easeOut(duration: 0.2), action)
    } else {
      action()
    }
  }
}
