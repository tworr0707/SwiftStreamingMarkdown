//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

final class LatexCompilationTests: XCTestCase {
  private func render(_ source: String) async -> RenderableDocument {
    let result = await MarkdownParserImpl().parse(
      text: source,
      option: .init(speculativeRewrite: false)
    )
    return await RenderableDocument(document: result.document, config: .default)
  }

  func testHessianExpressionCompilesAsOneDisplayTree() async {
    let document = await render(#"\[H_z = \operatorname{diag}(p)-pp^\top.\]"#)

    XCTAssertEqual(document.latexCompilationSummary.totalExpressions, 1)
    XCTAssertEqual(document.latexCompilationSummary.failedExpressions, 0)
    guard case .latex(_, let compiled) = document.renderables.first else {
      return XCTFail("Expected one compiled display expression")
    }
    XCTAssertEqual(compiled.source, #"H_z = \operatorname{diag}(p)-pp^\top."#)
  }

  func testInlineExpressionCarriesItsCompiledTreeInTheAttachment() async throws {
    let document = await render(#"Result: \(\boxed{x^2} + \dots + x_n\)."#)

    XCTAssertEqual(document.latexCompilationSummary.totalExpressions, 1)
    XCTAssertEqual(document.latexCompilationSummary.failedExpressions, 0)
    guard case .paragraph(_, let content) = document.renderables.first else {
      return XCTFail("Expected a paragraph")
    }
    var attachment: LatexAttachment?
    content.enumerateAttribute(
      .attachment,
      in: NSRange(location: 0, length: content.length)
    ) { value, _, stop in
      attachment = value as? LatexAttachment
      if attachment != nil {
        stop.pointee = ObjCBool(true)
      }
    }
    XCTAssertEqual(try XCTUnwrap(attachment).compiled.source, #"\boxed{x^2} + \dots + x_n"#)
  }

  func testUnsupportedDisplayMathFallsBackToLiteralText() async {
    let source = #"\[\notARealCommand{x}\]"#
    let document = await render(source)

    XCTAssertEqual(document.latexCompilationSummary.totalExpressions, 1)
    XCTAssertEqual(document.latexCompilationSummary.failedExpressions, 1)
    XCTAssertEqual(document.latexCompilationSummary.failureCodes, [.unsupportedCommand])
    guard case .paragraph(_, let content) = document.renderables.first else {
      return XCTFail("Expected a literal paragraph fallback")
    }
    XCTAssertEqual(content.string, "\\[\n\\notARealCommand{x}\n\\]")
    XCTAssertNil(content.attribute(.attachment, at: 0, effectiveRange: nil))
  }

  func testMultipleFailuresAreCountedIndependently() async {
    let document = await render(#"\(\badA\) and \(\badB\)"#)

    XCTAssertEqual(document.latexCompilationSummary.totalExpressions, 2)
    XCTAssertEqual(document.latexCompilationSummary.failedExpressions, 2)
    XCTAssertEqual(document.latexCompilationSummary.failureCodes, [.unsupportedCommand])
  }
}
