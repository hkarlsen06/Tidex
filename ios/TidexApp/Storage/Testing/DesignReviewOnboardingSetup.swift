#if DEBUG
  import SwiftUI

  /// Walks the real setup screens without creating an account or saving a job.
  internal struct DesignReviewOnboardingSetup: View {
    @State private var data = OnboardingData()
    @State private var step = 0

    internal var body: some View {
      Group {
        switch step {
        case 0:
          PurposeScreen(onSelectPaySetup: { step = 1 }, onSelectFriendsOnly: { step = 5 })
        case 1:
          JobBasicsOnboardingScreen(data: data, onContinue: { step = 2 }, onBack: { step = 0 })
        case 2:
          WageScreen(data: data, onContinue: { step = 3 }, onBack: { step = 1 })
        case 3:
          SupplementsScreen(data: data, onContinue: { step = 4 }, onBack: { step = 2 })
        case 4:
          SettingsAccordionScreen(data: data, onContinue: { step = 5 }, onBack: { step = 3 })
        default:
          SuccessScreen(completionMode: .fullSetup, onComplete: { step = 0 })
        }
      }
      .userCurrency(data.currency)
    }
  }
#endif
