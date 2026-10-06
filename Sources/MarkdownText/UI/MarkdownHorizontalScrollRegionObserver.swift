//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI
#if os(iOS)
import UIKit

/// Reports passive viewport anchors to a host that arbitrates navigation gestures.
@MainActor
public protocol MarkdownHorizontalScrollRegionObserver: AnyObject {
  func updateRegion(id: UUID, anchor: UIView, hasHorizontalOverflow: Bool)
  func removeRegion(id: UUID)
}

extension EnvironmentValues {
  @Entry public var markdownHorizontalScrollRegionObserver: (any MarkdownHorizontalScrollRegionObserver)?
}

struct MarkdownHorizontalScrollAnchor: UIViewRepresentable {
  let hasHorizontalOverflow: Bool
  @Environment(\.markdownHorizontalScrollRegionObserver) private var observer

  func makeUIView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.isUserInteractionEnabled = false
    view.accessibilityElementsHidden = true
    return view
  }

  func updateUIView(_ view: AnchorView, context: Context) {
    view.update(observer: observer, hasHorizontalOverflow: hasHorizontalOverflow)
  }

  static func dismantleUIView(_ view: AnchorView, coordinator: Void) {
    view.update(observer: nil, hasHorizontalOverflow: false)
  }

  final class AnchorView: UIView {
    private let regionID = UUID()
    private weak var observer: (any MarkdownHorizontalScrollRegionObserver)?
    private var hasHorizontalOverflow = false

    func update(observer nextObserver: (any MarkdownHorizontalScrollRegionObserver)?, hasHorizontalOverflow: Bool) {
      guard observer !== nextObserver || self.hasHorizontalOverflow != hasHorizontalOverflow else { return }
      if observer !== nextObserver {
        observer?.removeRegion(id: regionID)
        observer = nextObserver
      }
      self.hasHorizontalOverflow = hasHorizontalOverflow
      report()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      report()
    }

    private func report() {
      if window != nil {
        observer?.updateRegion(id: regionID, anchor: self, hasHorizontalOverflow: hasHorizontalOverflow)
      } else {
        observer?.removeRegion(id: regionID)
      }
    }
  }
}
#endif
