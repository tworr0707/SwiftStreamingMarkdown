//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation

/// Converts supported math delimiters into Markdown nodes without changing the
/// TeX body. Compilation happens later, exactly once, when renderables are built.
protocol LaTexPreProcessor {
  func process(input: String, matchingRules: [MarkdownParseOption.LatexMatching]) -> String
}

extension LaTexPreProcessor {
  func process(input: String) -> String {
    process(input: input, matchingRules: MarkdownParseOption.LatexMatching.allCases)
  }
}

final class LaTexPreProcessorImpl: LaTexPreProcessor {
  static let blockSlashLanguage = "blockmath-square"
  static let blockDollarLanguage = "blockmath-dollar"
  static let inlineSlashPrefix = "\\("
  static let inlineSlashSuffix = "\\)"
  static let inlineDollarPrefix = "\\($"
  static let inlineDollarSuffix = "$\\)"

  private static let slashBlock = try! NSRegularExpression(
    pattern: #"(?ms)^(\h*)\\\[(.+?)\\\]\h*$"#
  )
  private static let dollarBlock = try! NSRegularExpression(
    pattern: #"(?ms)^(\h*)\$\$(.+?)\$\$\h*$"#
  )

  func process(input: String, matchingRules: [MarkdownParseOption.LatexMatching]) -> String {
    let rules = Set(matchingRules)
    let blocks = transformOutsideFences(input) { segment in
      processBlockMath(segment, rules: rules)
    }
    return transformOutsideFences(blocks) { segment in
      processInlineMath(segment, rules: rules)
    }
  }

  private func transformOutsideFences(
    _ input: String,
    transform: (String) -> String
  ) -> String {
    var output: [String] = []
    var ordinary: [String] = []
    var fence: String?

    func flushOrdinary() {
      guard !ordinary.isEmpty else { return }
      output.append(transform(ordinary.joined(separator: "\n")))
      ordinary.removeAll(keepingCapacity: true)
    }

    for line in input.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let currentFence = fence {
        output.append(line)
        if trimmed.hasPrefix(currentFence) {
          fence = nil
        }
        continue
      }
      if let marker = openingFence(trimmed) {
        flushOrdinary()
        fence = marker
        output.append(line)
      } else {
        ordinary.append(line)
      }
    }
    flushOrdinary()
    return output.joined(separator: "\n")
  }

  private func processBlockMath(
    _ input: String,
    rules: Set<MarkdownParseOption.LatexMatching>
  ) -> String {
    var result = input
    if rules.contains(.blockSlashBracket) {
      result = replaceBlocks(
        in: result,
        regex: Self.slashBlock,
        language: Self.blockSlashLanguage
      )
    }
    if rules.contains(.blockDollar) {
      result = replaceBlocks(
        in: result,
        regex: Self.dollarBlock,
        language: Self.blockDollarLanguage
      )
    }
    return result
  }

  private func replaceBlocks(
    in input: String,
    regex: NSRegularExpression,
    language: String
  ) -> String {
    let source = input as NSString
    let matches = regex.matches(
      in: input,
      range: NSRange(location: 0, length: source.length)
    )
    guard !matches.isEmpty else { return input }
    let result = NSMutableString(string: input)
    for match in matches.reversed() {
      let indentation = source.substring(with: match.range(at: 1))
      let expression = trimmingDelimiterLines(source.substring(with: match.range(at: 2)))
      let fenced = "\(indentation)```\(language)\n\(expression)\n\(indentation)```"
      result.replaceCharacters(in: match.range, with: fenced)
    }
    return result as String
  }

  /// Removes only the otherwise-empty line fragments occupied by the opening
  /// and closing delimiters. Whitespace within the TeX body is preserved.
  private func trimmingDelimiterLines(_ expression: String) -> String {
    var lines = expression.components(separatedBy: "\n")
    if lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
      lines.removeFirst()
    }
    if lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
      lines.removeLast()
    }
    return lines.joined(separator: "\n")
  }

  private func processInlineMath(
    _ input: String,
    rules: Set<MarkdownParseOption.LatexMatching>
  ) -> String {
    var output = ""
    var cursor = input.startIndex

    while cursor < input.endIndex {
      if input[cursor] == "`" {
        let markerEnd = runEnd(of: "`", from: cursor, in: input)
        let marker = String(input[cursor..<markerEnd])
        if let close = input[markerEnd...].range(of: marker)?.upperBound {
          output += String(input[cursor..<close])
          cursor = close
          continue
        }
        output += String(input[cursor...])
        break
      }

      if rules.contains(.inlineSlashBracket),
         input[cursor...].hasPrefix(Self.inlineSlashPrefix),
         !isEscaped(cursor, in: input),
         let close = matchingSlashSuffix(from: cursor, in: input) {
        let bodyStart = input.index(cursor, offsetBy: Self.inlineSlashPrefix.count)
        let body = String(input[bodyStart..<close])
        output += inlineCode("\(Self.inlineSlashPrefix)\(body)\(Self.inlineSlashSuffix)")
        cursor = input.index(close, offsetBy: Self.inlineSlashSuffix.count)
        continue
      }

      if rules.contains(.inlineDollar), input[cursor] == "$",
         !isEscaped(cursor, in: input), !input[cursor...].hasPrefix("$$"),
         let match = matchingDollar(from: cursor, in: input) {
        let bodyStart = input.index(after: cursor)
        let body = String(input[bodyStart..<match])
        if looksLikeMath(body) {
          output += inlineCode("\(Self.inlineDollarPrefix)\(body)\(Self.inlineDollarSuffix)")
          cursor = input.index(after: match)
          continue
        }
      }

      output.append(input[cursor])
      cursor = input.index(after: cursor)
    }
    return output
  }

  private func matchingSlashSuffix(
    from opening: String.Index,
    in input: String
  ) -> String.Index? {
    var index = input.index(opening, offsetBy: Self.inlineSlashPrefix.count)
    while index < input.endIndex, input[index] != "\n" {
      if input[index...].hasPrefix(Self.inlineSlashSuffix), !isEscaped(index, in: input) {
        return index
      }
      index = input.index(after: index)
    }
    return nil
  }

  private func inlineCode(_ content: String) -> String {
    var longestRun = 0
    var index = content.startIndex
    while index < content.endIndex {
      if content[index] == "`" {
        let end = runEnd(of: "`", from: index, in: content)
        longestRun = max(longestRun, content.distance(from: index, to: end))
        index = end
      } else {
        index = content.index(after: index)
      }
    }
    let delimiter = String(repeating: "`", count: longestRun + 1)
    let padding = content.hasPrefix("`") || content.hasSuffix("`") ? " " : ""
    return "\(delimiter)\(padding)\(content)\(padding)\(delimiter)"
  }

  private func matchingDollar(from opening: String.Index, in input: String) -> String.Index? {
    var index = input.index(after: opening)
    while index < input.endIndex, input[index] != "\n" {
      if input[index] == "$", !isEscaped(index, in: input),
         !input[index...].hasPrefix("$$") {
        return index
      }
      index = input.index(after: index)
    }
    return nil
  }

  private func looksLikeMath(_ expression: String) -> Bool {
    let trimmed = expression.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.contains("  ") else { return false }
    if trimmed.range(of: #"^[£€$]?\d+(?:[.,]\d+)?$"#, options: .regularExpression) != nil {
      return false
    }
    if trimmed.count == 1, trimmed.first?.isLetter == true { return true }
    return trimmed.contains(where: { "\\^_=+−*/{}[]()<>|".contains($0) })
      || trimmed.range(
        of: #"\b(?:sin|cos|tan|log|ln|exp|lim|max|min)\b"#,
        options: .regularExpression
      ) != nil
  }

  private func openingFence(_ line: String) -> String? {
    if line.hasPrefix("```") { return "```" }
    if line.hasPrefix("~~~") { return "~~~" }
    return nil
  }

  private func runEnd(
    of character: Character,
    from start: String.Index,
    in input: String
  ) -> String.Index {
    var index = start
    while index < input.endIndex, input[index] == character {
      index = input.index(after: index)
    }
    return index
  }

  private func isEscaped(_ index: String.Index, in input: String) -> Bool {
    var cursor = index
    var count = 0
    while cursor > input.startIndex {
      let previous = input.index(before: cursor)
      guard input[previous] == "\\" else { break }
      count += 1
      cursor = previous
    }
    return count.isMultiple(of: 2) == false
  }
}
