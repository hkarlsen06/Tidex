import SwiftUI

// MARK: - Previews

#Preview("With Table") {
  ScrollView {
    FormattedMessageContent(
      content: """
        Here are your shifts for this week:

        ```
        Day\tDate\tHours\tGross
        Monday\tJan 27\t8.0\t1,600 kr
        Wednesday\tJan 29\t6.5\t1,300 kr
        Friday\tJan 31\t7.5\t1,500 kr
        ```

        Total: **4,400 kr** before taxes.
        """
    )
    .padding()
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble))
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Inline Table") {
  ScrollView {
    FormattedMessageContent(
      content: """
        Here's the comparison:

        Scenario\tHours\tGross\tNet
        Morning shift\t8.0\t1,200 kr\t960 kr
        Evening shift\t8.0\t1,520 kr\t1,216 kr

        The evening shift earns **320 kr** more due to supplements.
        """
    )
    .padding()
    .background(Color.tidexSurfacePrimary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble))
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("No Table") {
  FormattedMessageContent(
    content:
      "I've added a shift for tomorrow from **09:00** to **17:00**. You'll earn approximately **1,600 kr** before taxes."  // swiftlint:disable:this line_length
  )
  .padding()
  .background(Color.tidexSurfacePrimary)
  .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble))
  .padding()
  .background(Color.tidexBackground)
}
