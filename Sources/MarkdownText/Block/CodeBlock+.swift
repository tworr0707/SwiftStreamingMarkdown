//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

extension CodeBlock: BlockConvertible {
  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable {
    let delimiter: (opening: String, closing: String)?
    switch self.language {
    case LaTexPreProcessorImpl.blockSlashLanguage:
      delimiter = ("\\[", "\\]")
    case LaTexPreProcessorImpl.blockDollarLanguage:
      delimiter = ("$$", "$$")
    default:
      delimiter = nil
    }
    guard let delimiter else {
      return .codeBlock(id: self.id, language: self.language, code: self.code)
    }

    // swift-markdown includes the fence's structural trailing newline in
    // `CodeBlock.code`; it is not part of the TeX expression.
    let expression = self.code.hasSuffix("\n") ? String(self.code.dropLast()) : self.code
    switch CompiledLatex.compile(expression) {
    case .success(let compiled):
      return .latex(id: self.id, content: compiled)
    case .failure(let failure):
      var container = attributeContainer
      container[.font] = config.paragraphStyle.textFonts.normal
      container[.typography] = config.paragraphStyle.textFonts
      container[.foregroundColor] = MDColor(config.paragraphStyle.textColor)
      let source = "\(delimiter.opening)\n\(expression)\n\(delimiter.closing)"
      return .paragraph(
        id: self.id,
        content: literalLatex(source, failure: failure, attributes: container)
      )
    }
  }
}
