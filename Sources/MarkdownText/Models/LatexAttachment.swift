//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class LatexAttachment: NSTextAttachment {
  let compiled: CompiledLatex
  let fontSize: CGFloat
  let lightTextColor: String
  let darkTextColor: String

  init(
    compiled: CompiledLatex,
    fontSize: CGFloat,
    lightTextColor: String,
    darkTextColor: String
  ) {
    self.compiled = compiled
    self.fontSize = fontSize
    self.lightTextColor = lightTextColor
    self.darkTextColor = darkTextColor
    super.init(data: Data(), ofType: UTType.data.identifier)
  }

  required init?(coder: NSCoder) {
    nil
  }
}

extension LatexAttachment {
  var resolvedTextColor: MDColor {
    let fallback = MDColor(Color.Theme.Foreground.Primary.Primary750)
    #if canImport(UIKit)
    guard let lightColor = UIColor(hex: lightTextColor),
          let darkColor = UIColor(hex: darkTextColor) else {
      return fallback
    }
    return UIColor { trait in
      trait.userInterfaceStyle == .dark ? darkColor : lightColor
    }
    #elseif canImport(AppKit)
    guard let lightColor = NSColor(hex: lightTextColor),
          let darkColor = NSColor(hex: darkTextColor) else {
      return fallback
    }
    return NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
    }
    #endif
  }
}
