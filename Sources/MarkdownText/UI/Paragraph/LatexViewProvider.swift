//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import iosMath
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class LatexViewProvider: NSTextAttachmentViewProvider {
  private let compiled: CompiledLatex?
  private let fontSize: CGFloat
  private let textColor: MDColor

  #if canImport(UIKit)
  required override init(
    textAttachment attachment: NSTextAttachment,
    parentView: UIView?,
    textLayoutManager: NSTextLayoutManager?,
    location: any NSTextLocation
  ) {
    let latex = attachment as? LatexAttachment
    compiled = latex?.compiled
    fontSize = latex?.fontSize ?? Typography.base.mdFont.pointSize
    textColor = latex?.resolvedTextColor
      ?? MDColor(Color.Theme.Foreground.Primary.Primary750)
    super.init(
      textAttachment: attachment,
      parentView: parentView,
      textLayoutManager: textLayoutManager,
      location: location
    )
    tracksTextAttachmentViewBounds = true
  }
  #elseif canImport(AppKit)
  required override init(
    textAttachment attachment: NSTextAttachment,
    parentView: NSView?,
    textLayoutManager: NSTextLayoutManager?,
    location: any NSTextLocation
  ) {
    let latex = attachment as? LatexAttachment
    compiled = latex?.compiled
    fontSize = latex?.fontSize ?? Typography.base.mdFont.pointSize
    textColor = latex?.resolvedTextColor
      ?? MDColor(Color.Theme.Foreground.Primary.Primary750)
    super.init(
      textAttachment: attachment,
      parentView: parentView,
      textLayoutManager: textLayoutManager,
      location: location
    )
    tracksTextAttachmentViewBounds = true
  }
  #endif

  override func loadView() {
    let label = MTMathUILabel()
    label.mathList = compiled?.mathList
    label.textColor = textColor
    label.displayErrorInline = false
    label.fontSize = fontSize
    label.setContentHuggingPriority(.defaultHigh, for: .vertical)
    view = label
  }

  override func attachmentBounds(
    for attributes: [NSAttributedString.Key: Any],
    location: any NSTextLocation,
    textContainer: NSTextContainer?,
    proposedLineFragment: CGRect,
    position: CGPoint
  ) -> CGRect {
    guard let mathLabel = view as? MTMathUILabel else { return .zero }
    #if canImport(UIKit)
    mathLabel.sizeToFit()
    let size = mathLabel.bounds.size
    #elseif canImport(AppKit)
    let size = mathLabel.intrinsicContentSize
    #endif
    let height = size.height.rounded(.up) + 1.0
    let font = attributes[.font] as? MDFont ?? MDFont.systemFont(ofSize: fontSize)
    let yOffset = (font.xHeight - height) / 2.0
    return CGRect(x: 0, y: yOffset, width: size.width.rounded(.up), height: height)
  }
}
