//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A `MarkdownRenderConfig`-aware snapshot of a parsed markdown `Document`,
/// ready to be handed to a `MarkdownView` for rendering. Producing one is
/// the heavyweight step; rendering it is cheap.
public struct RenderableDocument: Equatable, Sendable {
  let renderables: [MarkdownRenderable]
  public let latexCompilationSummary: LatexCompilationSummary

  var containsCodeBlock: Bool {
    return renderables.contains(where: { $0.isCodeBlock })
  }

  var containsBlockQuote: Bool {
    return renderables.contains(where: { $0.isBlockQuote })
  }

  var isEmpty: Bool {
    return renderables.isEmpty
  }

  /// Convert a parsed `Document` into a `RenderableDocument` using the supplied config.
  /// - Parameters:
  ///   - document: The parsed markdown tree.
  ///   - config: Styling and behavior used during conversion.
  public init(document: Markdown.Document, config: MarkdownRenderConfig) async {
    let renderables = document.convert(with: config)
    self.renderables = renderables
    self.latexCompilationSummary = renderables.latexCompilationSummary
  }

  /// Construct a renderable wrapping a single plain-text paragraph styled
  /// with `config.paragraphStyle`. Useful for showing non-markdown text in a
  /// `MarkdownView` without round-tripping through the parser.
  public init(plainText: String, config: MarkdownRenderConfig) {
    var attributes: [NSAttributedString.Key: Any] = [
      .font: config.paragraphStyle.textFonts.normal,
      .foregroundColor: MDColor(config.paragraphStyle.textColor)
    ]
    if let kern = config.paragraphStyle.textFonts.preferredLetterSpacing {
      attributes[.kern] = kern
    }
    let content = NSMutableAttributedString(string: plainText, attributes: attributes)
    self.init(renderables: [.paragraph(id: UUID().uuidString, content: content)])
  }

  init(renderables: [MarkdownRenderable]) {
    self.renderables = renderables
    self.latexCompilationSummary = renderables.latexCompilationSummary
  }

  /// An empty document, equivalent to `RenderableDocument(plainText: "", …)`
  /// but allocation-free.
  public static let empty = RenderableDocument(renderables: [])
}

private extension Array where Element == MarkdownRenderable {
  var latexCompilationSummary: LatexCompilationSummary {
    reduce(.empty) { $0.merging($1.latexCompilationSummary) }
  }
}

private extension MarkdownRenderable {
  var latexCompilationSummary: LatexCompilationSummary {
    switch self {
    case .latex:
      return LatexCompilationSummary(totalExpressions: 1, failedExpressions: 0, failureCodes: [])
    case .paragraph(_, let content), .heading(_, _, let content):
      return content.latexCompilationSummary
    case .orderedList(_, let items), .unorderedList(_, let items, _):
      return items.reduce(.empty) { partial, item in
        partial.merging(item.children.latexCompilationSummary)
      }
    case .table(_, let headers, let rows, _):
      return (headers + rows.flatMap { $0 }).reduce(.empty) {
        $0.merging($1.latexCompilationSummary)
      }
    case .codeBlock, .thematicBreak, .blockQuote, .image:
      return .empty
    }
  }
}

private extension NSAttributedString {
  var latexCompilationSummary: LatexCompilationSummary {
    var successes = 0
    var failures = 0
    var codes: Set<LatexCompilationFailureCode> = []
    let fullRange = NSRange(location: 0, length: length)
    enumerateAttribute(.attachment, in: fullRange) { value, _, _ in
      if value is LatexAttachment { successes += 1 }
    }
    enumerateAttribute(.latexCompilationFailure, in: fullRange) { value, _, _ in
      guard let failure = value as? LatexCompilationFailureAttribute else { return }
      failures += 1
      codes.insert(failure.code)
    }
    return LatexCompilationSummary(
      totalExpressions: successes + failures,
      failedExpressions: failures,
      failureCodes: codes
    )
  }
}

extension RenderableDocument {
  var attributedStrings: [NSAttributedString] {
    return renderables.flatMap { $0.extractAttributedStrings() }
  }

  /// The full document rendered as plain text, across every block kind
  /// (headings, paragraphs, lists, code blocks, tables, block quotes). Used to
  /// populate the "Select more text" modal.
  var plainText: String {
    renderables
      .compactMap { $0.plainText }
      .joined(separator: "\n\n")
  }
}

extension MarkdownRenderable {
  /// A plain-text representation of this block, or `nil` for blocks that carry
  /// no selectable text (e.g. thematic breaks).
  var plainText: String? {
    switch self {
    case .paragraph(_, let content), .heading(_, _, let content):
      return content.string
    case .latex(_, let content):
      return content.source
    case .orderedList(_, let items):
      return items.plainText(separator: "\n")
    case .unorderedList(_, let items, _):
      return items.plainText(separator: "\n")
    case .codeBlock(_, _, let code):
      return code
    case .table(_, let headers, let rows, _):
      let headerLine = headers.map { $0.string }.joined(separator: "\t")
      let rowLines = rows.map { row in row.map { $0.string }.joined(separator: "\t") }
      return ([headerLine] + rowLines).joined(separator: "\n")
    case .blockQuote(_, let item):
      return item.quoteType.plainText
    case .thematicBreak:
      return nil
    case .image(_, let data):
      return data.alt.isEmpty ? nil : data.alt
    }
  }
}

private extension Array where Element == MarkdownListItem {
  func plainText(separator: String) -> String? {
    let lines = flatMap { item in
      item.children.compactMap { $0.plainText }
    }
    return lines.isEmpty ? nil : lines.joined(separator: separator)
  }
}

private extension BlockQuoteType {
  var plainText: String {
    switch self {
    case .text(let text):
      return text
    case .nested(let items):
      return items.map { $0.plainText }.joined(separator: "\n")
    }
  }
}

extension MarkdownRenderable {
  func extractAttributedStrings() -> [NSAttributedString] {
    switch self {
    case .paragraph(_, let str):
      return [str]
    case .orderedList(_, let items):
      return items.flatMap { $0.attributedStrings() }
    case .unorderedList(_, let items, _):
      return items.flatMap { $0.attributedStrings() }
    case .table(_, let headers, let rows, _):
      return headers + rows.flatMap { $0 }
    default:
      return []
    }
  }
}

extension MarkdownListItem {
  func attributedStrings() -> [NSAttributedString] {
    return self.children.flatMap { $0.extractAttributedStrings() }
  }
}
