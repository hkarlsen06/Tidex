import SwiftUI

/// Parses and renders message content with support for:
/// - Basic markdown (bold, italic)
/// - Tab-separated tables (inside code blocks or inline)
/// - Horizontal rules (---)
struct FormattedMessageContent: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    markdownText(text)
                case .table(let rows):
                    tableView(rows: rows)
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
            .padding(.vertical, 4)
    }

    // MARK: - Text Rendering

    @ViewBuilder
    private func markdownText(_ text: String) -> some View {
        if let attributedString = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributedString)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
        } else {
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    // MARK: - Table Rendering

    @ViewBuilder
    private func tableView(rows: [[String]]) -> some View {
        if rows.isEmpty { EmptyView() }
        else {
            let headerRow = rows[0]
            let dataRows = Array(rows.dropFirst())
            let columnCount = headerRow.count

            ScrollView(.horizontal, showsIndicators: false) {
                // Use Grid for proper column alignment
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    // Header row
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { colIndex in
                            Text(colIndex < headerRow.count ? headerRow[colIndex] : "")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(.tidexTextPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(Color.tidexSurfaceSecondary.opacity(0.5))

                    // Data rows
                    ForEach(Array(dataRows.enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(0..<columnCount, id: \.self) { colIndex in
                                Text(colIndex < row.count ? row[colIndex] : "")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundColor(colIndex == 0 ? .tidexTextPrimary : .tidexTextSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        }
                        .background(
                            rowIndex % 2 == 1 ? Color.tidexSurfaceSecondary.opacity(0.2) : Color.clear
                        )
                    }
                }
                .background(Color.tidexSurfaceSecondary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.tidexBorder.opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Content Parsing

    private enum ContentSegment {
        case text(String)
        case table([[String]])
        case horizontalRule
    }

    private func parseContent() -> [ContentSegment] {
        var segments: [ContentSegment] = []
        let remainingContent = content

        // First, extract code blocks with tab-separated content
        let codeBlockPattern = "```\\n?([^`]+)```"
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
                        if let tableRows = parseTabSeparatedContent(codeContent) {
                            segments.append(.table(tableRows))
                        } else {
                            // Not a table, treat as text
                            segments.append(.text(codeContent))
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
        let patterns = ["^-{3,}$", "^\\*{3,}$", "^_{3,}$", "^(- ){2,}-$", "^(\\* ){2,}\\*$", "^(_ ){2,}_$"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
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
}

// MARK: - Previews

#Preview("With Table") {
    ScrollView {
        FormattedMessageContent(content: """
        Here are your shifts for this week:

        ```
        Day\tDate\tHours\tGross
        Monday\tJan 27\t8.0\t1,600 kr
        Wednesday\tJan 29\t6.5\t1,300 kr
        Friday\tJan 31\t7.5\t1,500 kr
        ```

        Total: **4,400 kr** before taxes.
        """)
        .padding()
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    .padding()
    .background(Color.tidexBackground)
}

#Preview("Inline Table") {
    ScrollView {
        FormattedMessageContent(content: """
        Here's the comparison:

        Scenario\tHours\tGross\tNet
        Morning shift\t8.0\t1,200 kr\t960 kr
        Evening shift\t8.0\t1,520 kr\t1,216 kr

        The evening shift earns **320 kr** more due to supplements.
        """)
        .padding()
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
    .padding()
    .background(Color.tidexBackground)
}

#Preview("No Table") {
    FormattedMessageContent(content: "I've added a shift for tomorrow from **09:00** to **17:00**. You'll earn approximately **1,600 kr** before taxes.")
        .padding()
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding()
        .background(Color.tidexBackground)
}
