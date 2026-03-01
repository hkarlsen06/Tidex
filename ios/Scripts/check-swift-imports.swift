#!/usr/bin/env swift

import Foundation

private struct Issue {
  let file: String
  let line: Int
  let message: String
}

private let fileManager = FileManager.default

private func parseImports(in source: String) -> Set<String> {
  let pattern = #"(?m)^import\s+([A-Za-z_][A-Za-z0-9_]*)"#
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

  let ns = source as NSString
  let matches = regex.matches(
    in: source, options: [], range: NSRange(location: 0, length: ns.length))
  return Set(
    matches.compactMap { match in
      guard match.numberOfRanges == 2 else { return nil }
      return ns.substring(with: match.range(at: 1))
    })
}

private func firstMatchLine(in source: String, pattern: String) -> Int? {
  guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
  let ns = source as NSString
  let range = NSRange(location: 0, length: ns.length)
  guard let match = regex.firstMatch(in: source, options: [], range: range) else { return nil }

  let prefix = ns.substring(with: NSRange(location: 0, length: match.range.location))
  return prefix.reduce(into: 1) { line, char in
    if char == "\n" { line += 1 }
  }
}

private func runCommand(_ launchPath: String, _ arguments: [String]) -> (
  status: Int32, output: String
) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: launchPath)
  process.arguments = arguments

  let stdout = Pipe()
  process.standardOutput = stdout
  process.standardError = Pipe()

  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return (1, "")
  }

  let data = stdout.fileHandleForReading.readDataToEndOfFile()
  let output = String(data: data, encoding: .utf8) ?? ""
  return (process.terminationStatus, output)
}

private func changedSwiftFilePaths(from root: URL) -> [String] {
  let commands: [[String]] = [
    ["diff", "--name-only", "--", "*.swift"],
    ["diff", "--cached", "--name-only", "--", "*.swift"],
    ["ls-files", "--others", "--exclude-standard", "--", "*.swift"],
  ]

  var paths = Set<String>()
  let basePath = root.path + "/"

  for args in commands {
    let result = runCommand("/usr/bin/git", args)
    guard result.status == 0 else { continue }
    let lines = result.output.split(separator: "\n").map(String.init)
    for line in lines where !line.isEmpty {
      let absolute = root.appendingPathComponent(line).path
      if !absolute.hasPrefix(basePath) { continue }
      if absolute.contains("/ios/Scripts/") { continue }
      if fileManager.fileExists(atPath: absolute) {
        paths.insert(absolute)
      }
    }
  }

  return paths.sorted()
}

private func validateFile(_ url: URL) -> [Issue] {
  guard let source = try? String(contentsOf: url, encoding: .utf8) else {
    return [Issue(file: url.path, line: 1, message: "Unable to read file")]
  }

  let imports = parseImports(in: source)
  var issues: [Issue] = []

  let observablePattern = #"(?m)^[^/\n]*(\bObservableObject\b|@Published\b)"#
  if let line = firstMatchLine(in: source, pattern: observablePattern) {
    let hasProvider = imports.contains("Combine") || imports.contains("SwiftUI")
    if !hasProvider {
      issues.append(
        Issue(
          file: url.path,
          line: line,
          message: "Uses ObservableObject/@Published but imports neither Combine nor SwiftUI"
        ))
    }
  }

  let observationPattern = #"(?m)^[^/\n]*@Observable\b"#
  if let line = firstMatchLine(in: source, pattern: observationPattern) {
    let hasProvider = imports.contains("Observation") || imports.contains("SwiftUI")
    if !hasProvider {
      issues.append(
        Issue(
          file: url.path,
          line: line,
          message: "Uses @Observable but imports neither Observation nor SwiftUI"
        ))
    }
  }

  let localizedPattern = #"(?m)^[^/\n]*\bLocalizedStringResource\b"#
  if let line = firstMatchLine(in: source, pattern: localizedPattern) {
    let hasProvider = imports.contains("Foundation") || imports.contains("SwiftUI")
    if !hasProvider {
      issues.append(
        Issue(
          file: url.path,
          line: line,
          message: "Uses LocalizedStringResource but imports neither Foundation nor SwiftUI"
        ))
    }
  }

  let widgetPattern =
    #"(?m)^[^/\n]*(\bWidgetBundle\b|\bWidgetConfiguration\b|\bWidgetCenter\b|\bsome\s+Widget\b|:\s*Widget\b)"#
  if let line = firstMatchLine(in: source, pattern: widgetPattern) {
    if !imports.contains("WidgetKit") {
      issues.append(
        Issue(
          file: url.path,
          line: line,
          message: "Uses WidgetKit symbols but does not import WidgetKit"
        ))
    }
  }

  let loggerPattern = #"(?m)^[^/\n]*\bLogger\s*\("#
  if let line = firstMatchLine(in: source, pattern: loggerPattern) {
    let hasProvider = imports.contains("os") || imports.contains("OSLog")
    if !hasProvider {
      issues.append(
        Issue(
          file: url.path,
          line: line,
          message: "Uses Logger(...) but imports neither os.log/os nor OSLog"
        ))
    }
  }

  return issues
}

private func run() -> Int32 {
  let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
  let root = currentDirectory
  let iosRoot = root.appendingPathComponent("ios", isDirectory: true)

  guard fileManager.fileExists(atPath: iosRoot.path) else {
    fputs("ios directory not found at: \(iosRoot.path)\n", stderr)
    return 1
  }

  let files = changedSwiftFilePaths(from: root)
  if files.isEmpty {
    print("Swift import guard skipped (no changed Swift files).")
    return 0
  }

  let issues = files.map { URL(fileURLWithPath: $0) }.flatMap(validateFile)

  if issues.isEmpty {
    print("Swift import guard passed (\(files.count) files checked).")
    return 0
  }

  for issue in issues {
    print("\(issue.file):\(issue.line): error: \(issue.message)")
  }

  fputs("Found \(issues.count) import guard issue(s).\n", stderr)
  return 1
}

exit(run())
