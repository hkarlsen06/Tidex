// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable cyclomatic_complexity explicit_acl explicit_top_level_acl no_magic_numbers
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases vertical_whitespace_between_cases
import SwiftUI

/// Semantic motion tokens for consistent animation timing/curves across the app.
enum MotionTokens {
  enum Token {
    case navigationPush
    case navigationPop
    case pageTransition
    case emphasis
    case affordance
    case feedback
    case subtle
    case instant
  }

  enum TransitionToken {
    case navigationPush
    case navigationPop
    case pageTransition
  }

  enum NavigationDirection {
    case push
    case pop
  }

  static func animation(_ token: Token, reduceMotion: Bool) -> Animation {
    if reduceMotion {
      return instant(reduceMotion: false)
    }

    switch token {
    case .navigationPush:
      return .spring(response: 0.35, dampingFraction: 0.85)

    case .navigationPop:
      return .spring(response: 0.35, dampingFraction: 0.85)

    case .pageTransition:
      return .spring(response: 0.35, dampingFraction: 0.85)

    case .emphasis:
      return .spring(response: 0.4, dampingFraction: 0.8)

    case .affordance:
      return .easeOut(duration: 0.1)

    case .feedback:
      return .easeInOut(duration: 0.2)

    case .subtle:
      return .easeInOut(duration: 0.25)

    case .instant:
      return .linear(duration: 0.001)
    }
  }

  static func optionalAnimation(_ token: Token, reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : animation(token, reduceMotion: false)
  }

  static func instant(reduceMotion: Bool) -> Animation {
    animation(.instant, reduceMotion: reduceMotion)
  }

  static func transaction(_ token: Token, reduceMotion: Bool) -> Transaction {
    Transaction(animation: optionalAnimation(token, reduceMotion: reduceMotion))
  }

  static func animate(_ token: Token, reduceMotion: Bool, _ updates: () -> Void) {
    withTransaction(transaction(token, reduceMotion: reduceMotion), updates)
  }

  static func transition(_ token: TransitionToken, reduceMotion: Bool) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }

    switch token {
    case .navigationPush:
      return .asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
      )

    case .navigationPop:
      return .asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
      )

    case .pageTransition:
      return .move(edge: .bottom).combined(with: .opacity)
    }
  }

  static func navigationTransition(
    direction: NavigationDirection,
    reduceMotion: Bool
  ) -> AnyTransition {
    switch direction {
    case .push:
      return transition(.navigationPush, reduceMotion: reduceMotion)

    case .pop:
      return transition(.navigationPop, reduceMotion: reduceMotion)
    }
  }

  static func mirroredMoveTransition(edge: Edge, reduceMotion: Bool) -> AnyTransition {
    if reduceMotion {
      return .opacity
    }

    return .asymmetric(
      insertion: .move(edge: edge).combined(with: .opacity),
      removal: .move(edge: edge).combined(with: .opacity)
    )
  }
}

extension View {
  func motionAnimation<Value: Equatable>(
    _ token: MotionTokens.Token,
    value: Value,
    reduceMotion: Bool
  ) -> some View {
    animation(MotionTokens.optionalAnimation(token, reduceMotion: reduceMotion), value: value)
  }
}
