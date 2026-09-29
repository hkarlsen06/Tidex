import Accessibility
import SwiftUI

/// VoiceOver chart data for a Stats bar chart with one value per category.
/// Replaces the default Swift Charts description, which uses the English `.value(...)` names
/// and raw numbers, with localized titles and formatted values.
struct StatsCategoryChartDescriptor: AXChartDescriptorRepresentable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length
  struct Point {  // swiftlint:disable:this explicit_acl
    let category: String  // swiftlint:disable:this explicit_acl
    let value: Double  // swiftlint:disable:this explicit_acl
    /// Spoken description of the point, for example "Monday, 1 200 kr".
    let label: String  // swiftlint:disable:this explicit_acl
  }

  let title: String  // swiftlint:disable:this explicit_acl
  let summary: String?  // swiftlint:disable:this explicit_acl
  let categoryAxisTitle: String  // swiftlint:disable:this explicit_acl
  let valueAxisTitle: String  // swiftlint:disable:this explicit_acl
  let points: [Point]  // swiftlint:disable:this explicit_acl
  let formatValue: (Double) -> String  // swiftlint:disable:this explicit_acl

  func makeChartDescriptor() -> AXChartDescriptor {  // swiftlint:disable:this explicit_acl
    let xAxis = AXCategoricalDataAxisDescriptor(  // swiftlint:disable:this explicit_type_interface
      title: categoryAxisTitle,
      categoryOrder: points.map(\.category)
    )
    let maxValue = max(points.map(\.value).max() ?? 0, 1)  // swiftlint:disable:this explicit_type_interface
    let yAxis = AXNumericDataAxisDescriptor(  // swiftlint:disable:this explicit_type_interface
      title: valueAxisTitle,
      range: 0...maxValue,
      gridlinePositions: []
    ) { value in
      formatValue(value)
    }
    let series = AXDataSeriesDescriptor(  // swiftlint:disable:this explicit_type_interface
      name: title,
      isContinuous: false,
      dataPoints: points.map { point in
        AXDataPoint(x: point.category, y: point.value, label: point.label)
      }
    )
    return AXChartDescriptor(
      title: title,
      summary: summary,
      xAxis: xAxis,
      yAxis: yAxis,
      additionalAxes: [],
      series: [series]
    )
  }

  func updateChartDescriptor(_ descriptor: AXChartDescriptor) {  // swiftlint:disable:this explicit_acl
    let updated = makeChartDescriptor()  // swiftlint:disable:this explicit_type_interface
    descriptor.title = updated.title
    descriptor.summary = updated.summary
    descriptor.xAxis = updated.xAxis
    descriptor.yAxis = updated.yAxis
    descriptor.series = updated.series
  }
}

/// VoiceOver chart data for a Stats line chart with numeric x values, such as day of month.
struct StatsLineChartDescriptor: AXChartDescriptorRepresentable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length
  struct Series {  // swiftlint:disable:this explicit_acl
    let name: String  // swiftlint:disable:this explicit_acl
    let points: [(x: Double, y: Double)]  // swiftlint:disable:this explicit_acl
  }

  let title: String  // swiftlint:disable:this explicit_acl
  let summary: String?  // swiftlint:disable:this explicit_acl
  let xAxisTitle: String  // swiftlint:disable:this explicit_acl
  let yAxisTitle: String  // swiftlint:disable:this explicit_acl
  let xRange: ClosedRange<Double>  // swiftlint:disable:this explicit_acl
  let series: [Series]  // swiftlint:disable:this explicit_acl
  let formatValue: (Double) -> String  // swiftlint:disable:this explicit_acl

  func makeChartDescriptor() -> AXChartDescriptor {  // swiftlint:disable:this explicit_acl
    let xAxis = AXNumericDataAxisDescriptor(  // swiftlint:disable:this explicit_type_interface
      title: xAxisTitle,
      range: xRange,
      gridlinePositions: []
    ) { value in
      String(Int(value))
    }
    let maxValue = max(series.flatMap { $0.points.map(\.y) }.max() ?? 0, 1)  // swiftlint:disable:this explicit_type_interface line_length
    let yAxis = AXNumericDataAxisDescriptor(  // swiftlint:disable:this explicit_type_interface
      title: yAxisTitle,
      range: 0...maxValue,
      gridlinePositions: []
    ) { value in
      formatValue(value)
    }
    let descriptors = series.map { item in  // swiftlint:disable:this explicit_type_interface
      AXDataSeriesDescriptor(
        name: item.name,
        isContinuous: true,
        dataPoints: item.points.map { point in
          AXDataPoint(x: point.x, y: point.y)
        }
      )
    }
    return AXChartDescriptor(
      title: title,
      summary: summary,
      xAxis: xAxis,
      yAxis: yAxis,
      additionalAxes: [],
      series: descriptors
    )
  }

  func updateChartDescriptor(_ descriptor: AXChartDescriptor) {  // swiftlint:disable:this explicit_acl
    let updated = makeChartDescriptor()  // swiftlint:disable:this explicit_type_interface
    descriptor.title = updated.title
    descriptor.summary = updated.summary
    descriptor.xAxis = updated.xAxis
    descriptor.yAxis = updated.yAxis
    descriptor.series = updated.series
  }
}

/// A small marker above the bar for today or the current month.
/// It shows the highlight without color when Differentiate Without Color is on.
struct StatsBarHighlightMarker: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  var body: some View {  // swiftlint:disable:this explicit_acl
    Image(systemName: "triangle.fill")
      .font(.tidexMicro)
      .rotationEffect(.degrees(180))  // swiftlint:disable:this no_magic_numbers
      .foregroundStyle(Color.tidexBlueText)
      .accessibilityHidden(true)
  }
}
