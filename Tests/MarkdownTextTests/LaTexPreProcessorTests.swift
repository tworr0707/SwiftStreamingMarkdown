//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

final class LaTexPreProcessorTests: XCTestCase {
  private let preprocessor = LaTexPreProcessorImpl()

  func testPlainTextAndCurrencyAreUnchanged() {
    let input = "Your order is $5, the budget is $1,200, and the range is $$5 to $$10."
    XCTAssertEqual(preprocessor.process(input: input), input)
  }

  func testDollarBlockBecomesDedicatedMarkdownNode() {
    let input = #"$$H_z = \operatorname{diag}(p)-pp^\top.$$"#
    let expected = #"""
    ```blockmath-dollar
    H_z = \operatorname{diag}(p)-pp^\top.
    ```
    """#
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testSlashBlockBecomesDedicatedMarkdownNode() {
    let input = #"""
    Before
    \[
    \boxed{x^2} + \operatorname*{argmax}_{y} f(y)
    \]
    After
    """#
    let expected = #"""
    Before
    ```blockmath-square
    \boxed{x^2} + \operatorname*{argmax}_{y} f(y)
    ```
    After
    """#
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testTexBodyIsNeverRewritten() {
    let source = #"f'(a), \overrightarrow{FA}, \implies, \rightleftharpoons, \dots, \boxed{x}"#
    let input = "\\[\n\(source)\n\\]"
    let expected = "```blockmath-square\n\(source)\n```"
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testInlineSlashAndDollarMathUseDistinctSentinels() {
    let input = #"Slash \(x^2 + y^2\) and dollar $\alpha + 1$."#
    let expected = #"Slash `\(x^2 + y^2\)` and dollar `\($\alpha + 1$\)`."#
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testSingleLetterDollarMathIsRecognised() {
    XCTAssertEqual(preprocessor.process(input: "Value $x$."), #"Value `\($x$\)`."#)
  }

  func testInlineCodeIsNeverScannedForMath() {
    let input = #"Use `\(not math\)` and `$x^2$`, then render \(y^2\)."#
    let expected = #"Use `\(not math\)` and `$x^2$`, then render `\(y^2\)`."#
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testUnclosedInlineCodeIsNeverScannedForMath() {
    let input = #"Start `literal \(not math\)"#
    XCTAssertEqual(preprocessor.process(input: input), input)
  }

  func testMathContainingBackticksUsesALongerCodeFence() {
    let input = #"Render \(\text{`code`}\)."#
    let expected = #"Render ``\(\text{`code`}\)``."#
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testFencedCodeIsNeverScannedForMath() {
    let input = #"""
    ```swift
    let formula = "\(not math\)"
    let dollars = "$x^2$"
    ```
    Outside \(x^2\).
    """#
    let expected = #"""
    ```swift
    let formula = "\(not math\)"
    let dollars = "$x^2$"
    ```
    Outside `\(x^2\)`.
    """#
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testUnclosedStreamingDelimitersRemainLiteral() {
    let inputs = [#"Partial \(x +"#, "Partial $x +", #"Partial \[\nx +"#, "Partial $$\nx +"]
    for input in inputs {
      XCTAssertEqual(preprocessor.process(input: input), input)
    }
  }

  func testConsecutiveDollarBlocksAreNotMistakenForInlineMath() {
    let input = "$$x^2$$\n$$y^2$$"
    let expected = "```blockmath-dollar\nx^2\n```\n```blockmath-dollar\ny^2\n```"
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testIndentedSlashBlockKeepsContainerIndentation() {
    let input = "- Result:\n  \\[\n    x = y\n  \\]"
    let expected = "- Result:\n  ```blockmath-square\n    x = y\n  ```"
    XCTAssertEqual(preprocessor.process(input: input), expected)
  }

  func testMatchingRulesAreStrictlyGated() {
    let input = #"$$a=b$$, $x$, \(y\), and \[z\]"#
    let output = preprocessor.process(
      input: input,
      matchingRules: [.inlineSlashBracket]
    )
    XCTAssertEqual(output, #"$$a=b$$, $x$, `\(y\)`, and \[z\]"#)
  }
}
