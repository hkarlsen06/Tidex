import SwiftUI
import TipKit

struct ShiftSelectionTip: Tip {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  var title: Text {  // swiftlint:disable:this explicit_acl
    Text(.shiftsSelectionTipTitle)
      .font(.tidexLabelStrong)
      .foregroundStyle(Color.tidexTextPrimary)
  }

  var message: Text? {  // swiftlint:disable:this explicit_acl
    Text(.shiftsSelectionTipMessage)
      .font(.tidexFootnote)
      .foregroundStyle(Color.tidexTextSecondary)
  }

  var image: Image? {  // swiftlint:disable:this explicit_acl
    Image(systemName: "hand.tap")
  }
}
