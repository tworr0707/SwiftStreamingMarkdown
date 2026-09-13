//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class CodeBlockCopyTests: XCTestCase {

  func testCopyForwardsExactCodeAndReportsSuccess() {
    let code = "let greeting = \"Héllo 👋\"\n    print(greeting)\n"
    var writtenCode: String?
    var callbackCount = 0

    let copied = performCodeBlockCopy(
      code: code,
      write: {
        writtenCode = $0
        return true
      },
      onCodeCopied: { callbackCount += 1 }
    )

    XCTAssertTrue(copied)
    XCTAssertEqual(writtenCode, code)
    XCTAssertEqual(callbackCount, 1)
  }

  func testCopyDoesNotReportSuccessWhenClipboardWriteFails() {
    var callbackCount = 0

    let copied = performCodeBlockCopy(
      code: "print(\"Hello\")",
      write: { _ in false },
      onCodeCopied: { callbackCount += 1 }
    )

    XCTAssertFalse(copied)
    XCTAssertEqual(callbackCount, 0)
  }

  func testPlatformClipboardPreservesExactCode() throws {
    let code = "func answer() -> Int {\n    42\n}\n"

    #if canImport(UIKit)
    let name = UIPasteboard.Name("CodeBlockCopyTests.\(UUID().uuidString)")
    let pasteboard = try XCTUnwrap(UIPasteboard(name: name, create: true))
    defer { UIPasteboard.remove(withName: name) }

    XCTAssertTrue(CodeBlockClipboard.write(code, to: pasteboard))
    XCTAssertEqual(pasteboard.string, code)
    #elseif canImport(AppKit)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.clearContents() }

    XCTAssertTrue(CodeBlockClipboard.write(code, to: pasteboard))
    XCTAssertEqual(pasteboard.string(forType: .string), code)
    #endif
  }
}
