//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
@preconcurrency import iosMath

public enum LatexCompilationFailureCode: String, Codable, Hashable, Sendable {
  case unsupportedCommand
  case unsupportedEnvironment
  case malformed
  case resourceLimit
  case unknown
}

public struct LatexCompilationSummary: Equatable, Sendable {
  public let totalExpressions: Int
  public let failedExpressions: Int
  public let failureCodes: Set<LatexCompilationFailureCode>

  public static let empty = LatexCompilationSummary(
    totalExpressions: 0,
    failedExpressions: 0,
    failureCodes: []
  )

  init(totalExpressions: Int, failedExpressions: Int, failureCodes: Set<LatexCompilationFailureCode>) {
    self.totalExpressions = totalExpressions
    self.failedExpressions = failedExpressions
    self.failureCodes = failureCodes
  }

  func merging(_ other: LatexCompilationSummary) -> LatexCompilationSummary {
    LatexCompilationSummary(
      totalExpressions: totalExpressions + other.totalExpressions,
      failedExpressions: failedExpressions + other.failedExpressions,
      failureCodes: failureCodes.union(other.failureCodes)
    )
  }
}

struct LatexCompilationFailure: Error, Equatable, Sendable {
  let code: LatexCompilationFailureCode
}

final class LatexCompilationFailureAttribute: NSObject {
  let code: LatexCompilationFailureCode

  init(code: LatexCompilationFailureCode) {
    self.code = code
  }
}

/// An immutable math tree. The Objective-C model is mutable by API, but this
/// wrapper never exposes it outside the renderer and no code mutates it after
/// construction. Both inline and block views receive this same tree.
final class CompiledLatex: @unchecked Sendable, Equatable {
  let source: String
  let mathList: MTMathList

  private init(source: String, mathList: MTMathList) {
    self.source = source
    self.mathList = mathList
  }

  static func compile(_ source: String) -> Result<CompiledLatex, LatexCompilationFailure> {
    let builder = MTMathListBuilder(string: source)
    guard let list = builder.build() else {
      return .failure(LatexCompilationFailure(code: classify(builder.error)))
    }
    return .success(CompiledLatex(source: source, mathList: list))
  }

  static func == (lhs: CompiledLatex, rhs: CompiledLatex) -> Bool {
    lhs.source == rhs.source
  }

  private static func classify(_ error: Error?) -> LatexCompilationFailureCode {
    guard let error = error as NSError? else { return .unknown }
    switch error.code {
    case 2:
      return .unsupportedCommand
    case 8, 9:
      return .unsupportedEnvironment
    case 15:
      return .resourceLimit
    case 1, 3...7, 10...12, 14:
      return .malformed
    default:
      return .unknown
    }
  }
}

extension NSAttributedString.Key {
  static let latexCompilationFailure = NSAttributedString.Key(
    "com.microsoft.SwiftStreamingMarkdown.latexCompilationFailure"
  )
}

func literalLatex(
  _ source: String,
  failure: LatexCompilationFailure,
  attributes: NSAttributeContainer
) -> NSMutableAttributedString {
  let value = NSMutableAttributedString(string: source).mergingAttributes(attributes)
  value.addAttribute(
    .latexCompilationFailure,
    value: LatexCompilationFailureAttribute(code: failure.code),
    range: NSRange(location: 0, length: value.length)
  )
  return value
}
