import SwiftUI

/// Parses and renders message content with support for:
/// - Basic markdown (bold, italic)
/// - Tables (tab-separated inline/code blocks, plus fixed-width code block tables)
/// - Horizontal rules (---)
struct FormattedMessageContent: View {
  let content: String

  var body: some View {
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

  private var horizontalRuleView: some View {
    Rectangle()
      .fill(Color.tidexBorder)
      .frame(height: 1)
      .padding(.vertical, Spacing.xxs)
  }

  // MARK: - Text Rendering

  @ViewBuilder
  private func markdownText(_ text: String) -> some View {
    if let attributedString = try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
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
  private func tableView(rows: [[String]]) -> some View {
    if rows.isEmpty {
      EmptyView()
    } else {
      let headerRow = rows[0]
      let dataRows = Array(rows.dropFirst())
      let columnCount = headerRow.count
      let numericColumns = detectNumericColumns(headerRow: headerRow, dataRows: dataRows)

      ScrollView(.horizontal, showsIndicators: false) {
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
                  alignment: columnAlignment(column: colIndex, numericColumns: numericColumns))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
            }
          }
          .background(Color.tidexSurfaceSecondary.opacity(0.5))

          // Data rows
          ForEach(Array(dataRows.enumerated()), id: \.offset) { rowIndex, row in
            GridRow {
              ForEach(0..<columnCount, id: \.self) { colIndex in
                Text(colIndex < row.count ? row[colIndex] : "")
                  .font(.tidexMonoCaptionRegular)
                  .foregroundColor(colIndex == 0 ? .tidexTextPrimary : .tidexTextSecondary)
                  .frame(
                    minWidth: minColumnWidth(rows: rows, column: colIndex),
                    alignment: columnAlignment(
                      column: colIndex, numericColumns: numericColumns))
                  .padding(.horizontal, Spacing.sm)
                  .padding(.vertical, Spacing.xxxs)
              }
            }
            .background(
              rowIndex % 2 == 1 ? Color.tidexSurfaceSecondary.opacity(0.2) : Color.clear
            )
          }
        }
        .background(Color.tidexSurfaceSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.sm)
            .stroke(Color.tidexBorder.opacity(0.5), lineWidth: 1)
        )
      }
    }
  }

  // MARK: - Code Block Rendering

  private func codeBlockView(_ code: String) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      Text(code)
        .font(.tidexMonoCaptionRegular)
        .foregroundColor(.tidexTextPrimary)
        .textSelection(.enabled)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
    .background(Color.tidexSurfaceSecondary.opacity(0.3))
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    .overlay(
      RoundedRectangle(cornerRadius: CornerRadius.sm)
        .stroke(Color.tidexBorder.opacity(0.5), lineWidth: 1)
    )
  }

  private func minColumnWidth(rows: [[String]], column: Int) -> CGFloat {
    let maxCharacters = rows
      .compactMap { row in
        guard column < row.count else { return nil }
        return row[column].count
      }
      .max() ?? 0

    return min(220, max(48, CGFloat(maxCharacters) * 8.0))
  }

  private func detectNumericColumns(headerRow: [String], dataRows: [[String]]) -> Set<Int> {
    let numericHeaderHints = [
      "timer", "hours", "inntekt", "gross", "net", "amount", "sum", "total",
    ]

    var numericColumns: Set<Int> = []

    for column in headerRow.indices {
      let header = headerRow[column].lowercased()
      if numericHeaderHints.contains(where: { header.contains($0) }) {
        numericColumns.insert(column)
        continue
      }

      let values: [String] = dataRows.compactMap { (row: [String]) -> String? in
        guard column < row.count else { return nil }
        return row[column]
      }

      guard !values.isEmpty else { continue }

      let numericLikeCount = values.filter(isNumericLike).count
      if Double(numericLikeCount) / Double(values.count) >= 0.6 {
        numericColumns.insert(column)
      }
    }

    return numericColumns
  }

  private func isNumericLike(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed == "-" || trimmed == "–" || trimmed == "—" { return true }
    return trimmed.range(
      of: #"^[0-9.,:\-+\s]+(?:kr|nok|%)?$"#, options: .regularExpression) != nil
  }

  private func columnAlignment(column: Int, numericColumns: Set<Int>) -> Alignment {
    numericColumns.contains(column) ? .trailing : .leading
  }

  // MARK: - Content Parsing

  private enum ContentSegment {
    case text(String)
    case table([[String]])
    case code(String)
    case horizontalRule
  }

  private func parseContent() -> [ContentSegment] {
    var segments: [ContentSegment] = []
    let remainingContent = content

    // First, extract code blocks with tab-separated content
    let codeBlockPattern = "```(?:[A-Za-z0-9_+-]+)?\\n([\\s\\S]*?)```"
    if let regex = try? NSRegularExpression(pattern: codeBlockPattern, options: []) {
      var lastEnd = remainingContent.startIndex
      let nsRange = NSRange(remainingContent.startIndex..., in: remainingContent)

      let matches = regex.matches(in: remainingContent, options: [], range: nsRange)

      for match in matches {
        // Text before code block
        if let matchRange = Range(match.range, in: remainingContent) {
          let textBefore = String(remainingContent[lastEnd..<matchRange.lowerBound])

          // Check for inline tables in text before
          let textSegments = extractInlineTables(from: textBefore)
          segments.append(contentsOf: textSegments)

          // Code block content
          if let contentRange = Range(match.range(at: 1), in: remainingContent) {
            let codeContent = String(remainingContent[contentRange])
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
      let textAfter = String(remainingContent[lastEnd...])
      if !textAfter.isEmpty {
        let textSegments = extractInlineTables(from: textAfter)
        segments.append(contentsOf: textSegments)
      }
    } else {
      // No code blocks, check for inline tables
      segments = extractInlineTables(from: remainingContent)
    }

    // If no segments were created, return the original content as text
    if segments.isEmpty && !content.isEmpty {
      segments.append(.text(content))
    }

    return segments
  }

  /// Check if a line is a horizontal rule (---, ***, ___)
  private func isHorizontalRule(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    // Match 3+ of the same character (-, *, _) with optional spaces between
    let patterns = [
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
  private func extractInlineTables(from text: String) -> [ContentSegment] {
    let lines = text.components(separatedBy: "\n")
    var segments: [ContentSegment] = []
    var currentTextLines: [String] = []
    var currentTableLines: [String] = []
    var inTable = false

    for line in lines {
      // Check for horizontal rule first
      if isHorizontalRule(line) {
        // Flush any pending content
        if inTable {
          if currentTableLines.count >= 2 {
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
          let textContent = currentTextLines.joined(separator: "\n")
          if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(textContent))
          }
          currentTextLines = []
        }
        segments.append(.horizontalRule)
        continue
      }

      let hasTab = line.contains("\t")

      if hasTab {
        if !inTable {
          // Starting a potential table
          if !currentTextLines.isEmpty {
            let textContent = currentTextLines.joined(separator: "\n")
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
          if currentTableLines.count >= 2 {
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
    if inTable && currentTableLines.count >= 2 {
      if let rows = parseTabSeparatedContent(currentTableLines.joined(separator: "\n")) {
        segments.append(.table(rows))
      }
    } else if !currentTableLines.isEmpty {
      currentTextLines.append(contentsOf: currentTableLines)
    }

    if !currentTextLines.isEmpty {
      let textContent = currentTextLines.joined(separator: "\n")
      if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        segments.append(.text(textContent))
      }
    }

    return segments
  }

  /// Parse tab-separated content into rows and columns
  private func parseTabSeparatedContent(_ content: String) -> [[String]]? {
    let lines = content.components(separatedBy: "\n")
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    guard lines.count >= 2 else { return nil }

    // Check if lines have tabs
    let hasTabLines = lines.filter { $0.contains("\t") }
    guard hasTabLines.count >= 2 else { return nil }

    let rows = lines.map { line in
      line.components(separatedBy: "\t")
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    return rows
  }

  /// Parse both tab-separated and fixed-width (multi-space) tables.
  private func parseTableContent(_ content: String) -> [[String]]? {
    if let tabRows = parseTabSeparatedContent(content) {
      return tabRows
    }
    return parseFixedWidthTableContent(content)
  }

  /// Parse tables that use 2+ spaces as column separators.
  /// Common when LLMs emit visually aligned tables inside code blocks.
  private func parseFixedWidthTableContent(_ content: String) -> [[String]]? {
    let lines = content.components(separatedBy: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard lines.count >= 2 else { return nil }

    let rows = lines.map(splitByMultiSpaces)

    let columnCounts = rows.map(\.count)
    guard let firstCount = columnCounts.first, firstCount >= 3 else { return nil }
    guard columnCounts.filter({ $0 == firstCount }).count >= 2 else { return nil }
    guard columnCounts.allSatisfy({ abs($0 - firstCount) <= 1 }) else { return nil }

    let normalized = rows.map { row in
      if row.count == firstCount {
        return row
      }
      return row + Array(repeating: "", count: firstCount - row.count)
    }

    return normalized
  }

  private static let multiSpaceSeparatorRegex = try? NSRegularExpression(
    pattern: "\\s{2,}", options: [])

  private func splitByMultiSpaces(_ line: String) -> [String] {
    guard let regex = Self.multiSpaceSeparatorRegex else {
      return [line]
    }

    let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
    let matches = regex.matches(in: line, options: [], range: nsRange)

    guard !matches.isEmpty else {
      return [line]
    }

    var result: [String] = []
    var lastIndex = line.startIndex

    for match in matches {
      guard let range = Range(match.range, in: line) else { continue }
      let part = line[lastIndex..<range.lowerBound]
        .trimmingCharacters(in: .whitespaces)
      if !part.isEmpty {
        result.append(part)
      }
      lastIndex = range.upperBound
    }

    let tail = line[lastIndex...].trimmingCharacters(in: .whitespaces)
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
      "I've added a shift for tomorrow from **09:00** to **17:00**. You'll earn approximately **1,600 kr** before taxes."
  )
  .padding()
  .background(Color.tidexSurfacePrimary)
  .clipShape(RoundedRectangle(cornerRadius: CornerRadius.bubble))
  .padding()
  .background(Color.tidexBackground)
}
