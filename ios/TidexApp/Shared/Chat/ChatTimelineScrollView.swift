import SwiftUI

struct ChatTimelineScrollCommand: Equatable {
  enum Kind: Equatable {
    case generic
    case restore
    case reply
  }

  let kind: Kind
  let targetID: AnyHashable
  let anchor: UnitPoint
  let animated: Bool

  init(
    kind: Kind = .generic,
    targetID: AnyHashable,
    anchor: UnitPoint,
    animated: Bool
  ) {
    self.kind = kind
    self.targetID = targetID
    self.anchor = anchor
    self.animated = animated
  }
}

struct ChatTimelineScrollContext {
  let isPinnedToBottom: Bool
  let suppressAutoFollow: Bool
  let shouldAutoFollow: Bool
  let scrollToBottom: (_ animated: Bool, _ force: Bool) -> Void
  let scrollToTarget: (_ id: AnyHashable, _ anchor: UnitPoint, _ animated: Bool) -> Void
  let resetAutoFollow: () -> Void
}

struct ChatTimelineScrollView<ScrollState: Equatable, Content: View>: View {
  let scrollState: ScrollState
  let bottomContentInset: CGFloat
  @Binding var isPinnedToBottom: Bool
  var scrollToBottomTrigger: Int = 0
  var explicitScrollCommand: Binding<ChatTimelineScrollCommand?> = .constant(nil)
  var dismissKeyboardOnTap = false
  var onScrollStateChange: ((ScrollState, ScrollState, ChatTimelineScrollContext) -> Void)? = nil
  @ViewBuilder let content: () -> Content

  @State private var scrollTask: Task<Void, Never>?
  @State private var suppressAutoFollow = false

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: Spacing.sm) {
          content()

          Color.clear
            .frame(height: max(bottomContentInset, Spacing.bottomScrollMargin))
            .id("bottom-spacer")

          Color.clear
            .frame(height: 1)
            .id("bottom")
            .onAppear {
              isPinnedToBottom = true
              suppressAutoFollow = false
            }
            .onDisappear {
              isPinnedToBottom = false
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 4)
          .onChanged { _ in
            scrollTask?.cancel()
            if !isPinnedToBottom {
              suppressAutoFollow = true
            }
          }
          .onEnded { _ in
            suppressAutoFollow = !isPinnedToBottom
          }
      )
      .onAppear {
        isPinnedToBottom = true
        suppressAutoFollow = false
        scheduleScrollToBottom(proxy: proxy, animated: false, force: true)
      }
      .onChange(of: scrollState) { oldValue, newValue in
        onScrollStateChange?(
          oldValue,
          newValue,
          ChatTimelineScrollContext(
            isPinnedToBottom: isPinnedToBottom,
            suppressAutoFollow: suppressAutoFollow,
            shouldAutoFollow: isPinnedToBottom && !suppressAutoFollow,
            scrollToBottom: { animated, force in
              scheduleScrollToBottom(proxy: proxy, animated: animated, force: force)
            },
            scrollToTarget: { id, anchor, animated in
              scrollTask?.cancel()
              if animated {
                withAnimation(.easeInOut(duration: 0.2)) {
                  proxy.scrollTo(id, anchor: anchor)
                }
              } else {
                proxy.scrollTo(id, anchor: anchor)
              }
            },
            resetAutoFollow: {
              isPinnedToBottom = true
              suppressAutoFollow = false
            }
          )
        )
      }
      .onChange(of: scrollToBottomTrigger) { _, _ in
        isPinnedToBottom = true
        suppressAutoFollow = false
        scheduleScrollToBottom(proxy: proxy, animated: true, force: true)
      }
      .onChange(of: explicitScrollCommand.wrappedValue) { _, newValue in
        guard let command = newValue else { return }
        scrollTask?.cancel()
        if command.animated {
          withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(command.targetID, anchor: command.anchor)
          }
        } else {
          proxy.scrollTo(command.targetID, anchor: command.anchor)
        }
        explicitScrollCommand.wrappedValue = nil
      }
      .scrollDismissesKeyboard(.interactively)
      .onDisappear {
        scrollTask?.cancel()
        scrollTask = nil
      }
    }
    .onTapGesture {
      guard dismissKeyboardOnTap else { return }
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
  }

  private func scheduleScrollToBottom(
    proxy: ScrollViewProxy,
    animated: Bool,
    force: Bool
  ) {
    scrollTask?.cancel()
    scrollTask = Task { @MainActor in
      await Task.yield()
      await Task.yield()
      guard !Task.isCancelled else { return }
      guard force || !suppressAutoFollow else { return }

      if animated {
        withAnimation(.easeOut(duration: 0.2)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      } else {
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
  }
}
