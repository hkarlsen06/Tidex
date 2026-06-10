import SwiftUI

/// Parses and renders message content with support for:
/// - Basic markdown (bold, italic)
/// - Tables (tab-separated inline/code blocks, plus fixed-width code block tables)
/// - Horizontal rules (---)
struct FormattedMessageContent: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  let content: String  // swiftlint:disable:this explicit_acl type_contents_order

  var body: some View {  // swiftlint:disable:this explicit_acl type_contents_order
    VStack(alignment: .leading, spacing: Spacing.xs) {
      ForEach(Array(parseContent().enumerated()), id: \.offset) { _, segment in
        switch segment {
        case .text(let text):
          markdownText(text)

        case .table(let rows):
          tableView(rows: rows)

        case .code(let code):
          codeBlockView(code)

        case .horizontalRule:
          horizontalRuleView
        }
      }
    }
  }

  // MARK: - Horizontal Rule

  private var horizontalRuleView: some View {  // swiftlint:disable:this type_contents_order
    Rectangle()
      .fill(Color.tidexBorder)
      .frame(height: 1)
      .padding(.vertical, Spacing.xxs)
  }

  // MARK: - Text Rendering

  @ViewBuilder
  private func markdownText(_ text: String) -> some View {  // swiftlint:disable:this type_contents_order
    if let attributedString = try? AttributedString(
      markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      Text(attributedString)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
    } else {
      Text(text)
        .font(.tidexBody)
        .foregroundColor(.tidexTextPrimary)
    }
  }

  // MARK: - Table Rendering

  @ViewBuilder
  private func tableView(rows: [[String]]) -> some View {  // swiftlint:disable:this function_body_length line_length type_contents_order
    if rows.isEmpty {
      EmptyView()
    } else {
      let headerRow = rows[0]  // swiftlint:disable:this explicit_type_interface
      let dataRows = Array(rows.dropFirst())  // swiftlint:disable:this explicit_type_interface
      let columnCount = headerRow.count  // swiftlint:disable:this explicit_type_interface
      let numericColumns = detectNumericColumns(headerRow: headerRow, dataRows: dataRows)  // swiftlint:disable:this explicit_type_interface line_length

      ScrollView(.horizontal, showsIndicators: false) {  // swiftlint:disable:this closure_body_length
        // Use Grid for proper column alignment
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
          // Header row
          GridRow {
            ForEach(0..<columnCount, id: \.self) { colIndex in
              Text(colIndex < headerRow.count ? headerRow[colIndex] : "")
                .font(.tidexMonoCaptionStrong)
                .foregroundColor(.tidexTextPrimary)
                .frame(
                  minWidth: minColumnWidth(rows: rows, column: colIndex),
                  alignment: columnAlignment(column: colIndex, numericColumns: numericColumns)
                )
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
          }
          .background(Color.tidexSurfaceSecondary.opacity(0.5))  // swiftlint:disable:this no_magic_numbers

          // Data rows
          ForEach(Array(dataRows.enumerated()), id: \.offset) { rowIndex, row in
            GridRow {
              ForEach(0..<columnCount, id: \.self) { colIndex in
                Text(colIndex < row.count ? row[colIndex] : "")
                  .font(.tidexMonoCaptionRegular)
                  .foregroundColor(colIndex == 0 ? .tidexTextPrimary : .tidexTextSecondary)
                  .frame(
                    minWidth: minColumnWidth(rows: rows, column: colIndex),
                    alignment: columnAlignment(column: colIndex, numericColumns: numericColumns)
                  )
                  .padding(.horizontal, Spacing.sm)
                  .padding(.vertical, Spacing.xxxs)
              }
            }
            .background(rowBackground(for: rowIndex))
          }
        }
        .background(Color.tidexSurfaceSecondary.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.sm)
            .stroke(Color.tidexBorder.opacity(0.5), lineWidth: 1)  // swiftlint:disable:this no_magic_numbers
        )
      }
    }
  }

  // MARK: - Code Block Rendering

  private func codeBlockView(_ code: String) -> some View {  // swiftlint:disable:this type_contents_order
    ScrollView(.horizontal, showsIndicators: false) {
      Text(code)
        .font(.tidexMonoCaptionRegular)
        .foregroundColor(.tidexTextPrimary)
        .textSelection(.enabled)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
    .background(Color.tidexSurfaceSecondary.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .stroke(Color.tidexBorder.opacity(0.5), lineWidth: 1)  // swiftlint:disable:this no_magic_numbers
    )
  }

  private func rowBackground(for rowIndex: Int) -> Color { rowIndex.isMultiple(of: 2) ? .clear : Color.tidexSurfaceSecondary.opacity(0.2) }  // swiftlint:disable:this line_length no_magic_numbers type_contents_order

  private func minColumnWidth(rows: [[String]], column: Int) -> CGFloat {  // swiftlint:disable:this type_contents_order
    let maxCharacters: Int =
      rows
      .compactMap { row in
        guard column < row.count else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
        return row[column].count
      }
      .max() ?? 0

    return min(220, max(48, CGFloat(maxCharacters) * 8.0))  // swiftlint:disable:this no_magic_numbers
  }

  private func detectNumericColumns(headerRow: [String], dataRows: [[String]]) -> Set<Int> {  // swiftlint:disable:this line_length type_contents_order
    let numericHeaderHints = [  // swiftlint:disable:this explicit_type_interface
      "timer", "hours", "inntekt", "gross", "net", "amount", "sum", "total",
    ]

    var numericColumns: Set<Int> = []

    for column in headerRow.indices {
      let header = headerRow[column].lowercased()  // swiftlint:disable:this explicit_type_interface
      if numericHeaderHints.contains(where: { header.contains($0) }) {
        numericColumns.insert(column)
        continue
      }

      let values: [String] = dataRows.compactMap { (row: [String]) -> String? in
        guard column < row.count else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
        return row[column]
      }

      guard !values.isEmpty else { continue }

      let numericLikeCount = values.filter(isNumericLike).count  // swiftlint:disable:this explicit_type_interface
      if Double(numericLikeCount) / Double(values.count) >= 0.6 {  // swiftlint:disable:this no_magic_numbers
        numericColumns.insert(column)
      }
    }

    return numericColumns
  }

  private func isNumericLike(_ text: String) -> Bool {  // swiftlint:disable:this type_contents_order
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()  // swiftlint:disable:this explicit_type_interface line_length
    if trimmed == "-" || trimmed == "–" || trimmed == "—" { return true }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return trimmed.range(
      of: #"^[0-9.,:\-+\s]+(?:kr|nok|%)?$"#, options: .regularExpression) != nil  // swiftlint:disable:this line_length multiline_arguments_brackets
  }

  private func columnAlignment(column: Int, numericColumns: Set<Int>) -> Alignment {  // swiftlint:disable:this line_length type_contents_order
    numericColumns.contains(column) ? .trailing : .leading
  }

  // MARK: - Content Parsing

  private enum ContentSegment {
    case text(String)
    case table([[String]])
    case code(String)
    case horizontalRule
  }

  private func parseContent() -> [ContentSegment] {  // swiftlint:disable:this type_contents_order
    var segments: [ContentSegment] = []
    let remainingContent = content  // swiftlint:disable:this explicit_type_interface

    // First, extract code blocks with tab-separated content
    let codeBlockPattern: String = #"```(?:[A-Za-z0-9_+-]+)?\n([\s\S]*?)```"#
    if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
      var lastEnd = remainingContent.startIndex  // swiftlint:disable:this explicit_type_interface
      let nsRange = NSRange(remainingContent.startIndex..., in: remainingContent)  // swiftlint:disable:this explicit_type_interface line_length

      let matches = regex.matches(in: remainingContent, options: [], range: nsRange)  // swiftlint:disable:this explicit_type_interface line_length

      for match in matches {
        // Text before code block
        if let matchRange = Range(match.range, in: remainingContent) {
          let textBefore = String(remainingContent[lastEnd..<matchRange.lowerBound])  // swiftlint:disable:this explicit_type_interface line_length

          // Check for inline tables in text before
          let textSegments = extractInlineTables(from: textBefore)  // swiftlint:disable:this explicit_type_interface
          segments.append(contentsOf: textSegments)

          // Code block content
          if let contentRange = Range(match.range(at: 1), in: remainingContent) {
            let codeContent = String(remainingContent[contentRange])  // swiftlint:disable:this explicit_type_interface
            if let tableRows = parseTableContent(codeContent) {
              segments.append(.table(tableRows))
            } else {
              // Keep non-table code blocks monospaced for readability
              segments.append(.code(codeContent))
            }
          }

          lastEnd = matchRange.upperBound
        }
      }

      // Text after last code block
      let textAfter = String(remainingContent[lastEnd...])  // swiftlint:disable:this explicit_type_interface
      if !textAfter.isEmpty {
        let textSegments = extractInlineTables(from: textAfter)  // swiftlint:disable:this explicit_type_interface
        segments.append(contentsOf: textSegments)
      }
    } else {
      // No code blocks, check for inline tables
      segments = extractInlineTables(from: remainingContent)
    }

    // If no segments were created, return the original content as text
    if segments.isEmpty, !content.isEmpty {
      segments.append(.text(content))
    }

    return segments
  }

  /// Check if a line is a horizontal rule (---, ***, ___)
  private func isHorizontalRule(_ line: String) -> Bool {  // swiftlint:disable:this type_contents_order
    let trimmed = line.trimmingCharacters(in: .whitespaces)  // swiftlint:disable:this explicit_type_interface
    // Match 3+ of the same character (-, *, _) with optional spaces between
    let patterns = [  // swiftlint:disable:this explicit_type_interface
      "^-{3,}$", "^\\*{3,}$", "^_{3,}$", "^(- ){2,}-$", "^(\\* ){2,}\\*$", "^(_ ){2,}_$",
    ]
    for pattern in patterns {
      if let regex = try? NSRegularExpression(pattern: pattern),
        regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
      {
        return true
      }
    }
    return false
  }

  /// Extract inline tables and horizontal rules from text (consecutive lines with tabs)
  private func extractInlineTables(from text: String) -> [ContentSegment] {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    let lines = text.components(separatedBy: "\n")  // swiftlint:disable:this explicit_type_interface
    var segments: [ContentSegment] = []
    var currentTextLines: [String] = []
    var currentTableLines: [String] = []
    var inTable = false  // swiftlint:disable:this explicit_type_interface

    for line in lines {
      // Check for horizontal rule first
      if isHorizontalRule(line) {
        // Flush any pending content
        if inTable {
          if currentTableLines.count >= 2 {  // swiftlint:disable:this no_magic_numbers
            if let rows = parseTabSeparatedContent(currentTableLines.joined(separator: "\n")) {
              segments.append(.table(rows))
            }
          } else if !currentTableLines.isEmpty {
            currentTextLines.append(contentsOf: currentTableLines)
          }
          currentTableLines = []
          inTable = false
        }
        if !currentTextLines.isEmpty {
          let textContent = currentTextLines.joined(separator: "\n")  // swiftlint:disable:this explicit_type_interface
          if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(textContent))
          }
          currentTextLines = []
        }
        segments.append(.horizontalRule)
        continue
      }

      let hasTab = line.contains("\t")  // swiftlint:disable:this explicit_type_interface

      if hasTab {
        if !inTable {
          // Starting a potential table
          if !currentTextLines.isEmpty {
            let textContent: String = currentTextLines.joined(separator: "\n")
            if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              segments.append(.text(textContent))
            }
            currentTextLines = []
          }
          inTable = true
        }
        currentTableLines.append(line)
      } else {
        if inTable {
          // Ending table section
          if currentTableLines.count >= 2 {  // swiftlint:disable:this no_magic_numbers
            if let rows = parseTabSeparatedContent(currentTableLines.joined(separator: "\n")) {
              segments.append(.table(rows))
            }
          } else if !currentTableLines.isEmpty {
            // Not enough lines for a table, treat as text
            currentTextLines.append(contentsOf: currentTableLines)
          }
          currentTableLines = []
          inTable = false
        }
        currentTextLines.append(line)
      }
    }

    // Flush remaining content
    if inTable, currentTableLines.count >= 2 {  // swiftlint:disable:this no_magic_numbers
      if let rows = parseTabSeparatedContent(currentTableLines.joined(separator: "\n")) {
        segments.append(.table(rows))
      }
    } else if !currentTableLines.isEmpty {
      currentTextLines.append(contentsOf: currentTableLines)
    }

    if !currentTextLines.isEmpty {
      let textContent = currentTextLines.joined(separator: "\n")  // swiftlint:disable:this explicit_type_interface
      if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        segments.append(.text(textContent))
      }
    }

    return segments
  }

  /// Parse tab-separated content into rows and columns
  private func parseTabSeparatedContent(_ content: String) -> [[String]]? {  // swiftlint:disable:this discouraged_optional_collection line_length type_contents_order
    let lines = content.components(separatedBy: "\n")  // swiftlint:disable:this explicit_type_interface
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    let minimumTableLineCount: Int = 2
    guard lines.count >= minimumTableLineCount else {
      return nil
    }

    // Check if lines have tabs
    let hasTabLines = lines.filter { $0.contains("\t") }  // swiftlint:disable:this explicit_type_interface
    guard hasTabLines.count >= minimumTableLineCount else {
      return nil
    }

    return lines.map { line in
      line.components(separatedBy: "\t")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }
  }

  /// Parse both tab-separated and fixed-width (multi-space) tables.
  private func parseTableContent(_ content: String) -> [[String]]? {  // swiftlint:disable:this discouraged_optional_collection line_length type_contents_order
    parseTabSeparatedContent(content) ?? parseFixedWidthTableContent(content)
  }

  /// Parse tables that use 2+ spaces as column separators.
  /// Common when LLMs emit visually aligned tables inside code blocks.
  private func parseFixedWidthTableContent(_ content: String) -> [[String]]? {  // swiftlint:disable:this discouraged_optional_collection line_length type_contents_order
    let lines = content.components(separatedBy: "\n")  // swiftlint:disable:this explicit_type_interface
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    let minimumTableLineCount: Int = 2
    guard lines.count >= minimumTableLineCount else {
      return nil
    }

    let rows = lines.map(splitByMultiSpaces)  // swiftlint:disable:this explicit_type_interface

    let columnCounts = rows.map(\.count)  // swiftlint:disable:this explicit_type_interface
    let minimumColumnCount: Int = 3
    guard let firstCount = columnCounts.first, firstCount >= minimumColumnCount else {
      return nil
    }
    guard columnCounts.filter({ $0 == firstCount }).count >= 2 else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length no_magic_numbers
    guard columnCounts.allSatisfy({ abs($0 - firstCount) <= 1 }) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length

    return rows.map { row in
      row.count == firstCount ? row : row + Array(repeating: "", count: firstCount - row.count)
    }
  }

  private static let multiSpaceSeparatorRegex = try? NSRegularExpression(  // swiftlint:disable:this explicit_type_interface line_length
    pattern: "\\s{2,}", options: [])  // swiftlint:disable:this multiline_arguments_brackets

  private func splitByMultiSpaces(_ line: String) -> [String] {
    guard let regex = Self.multiSpaceSeparatorRegex else {
      return [line]
    }

    let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)  // swiftlint:disable:this explicit_type_interface
    let matches: [NSTextCheckingResult] = regex.matches(in: line, options: [], range: nsRange)

    guard !matches.isEmpty else {
      return [line]
    }

    var result: [String] = []
    var lastIndex = line.startIndex  // swiftlint:disable:this explicit_type_interface

    for match in matches {
      guard let range = Range(match.range, in: line) else { continue }
      let part = line[lastIndex..<range.lowerBound]  // swiftlint:disable:this explicit_type_interface
        .trimmingCharacters(in: .whitespaces)
      if !part.isEmpty {
        result.append(part)
      }
      lastIndex = range.upperBound
    }

    let tail: String = line[lastIndex...].trimmingCharacters(in: .whitespaces)
    if !tail.isEmpty {
      result.append(tail)
    }

    return result
  }
}

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
