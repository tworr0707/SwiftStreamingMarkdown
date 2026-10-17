//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if os(macOS)
import AppKit
import SwiftUI

/// SwiftUI's horizontal scroll view consumes vertical wheel input on macOS.
/// This passive content anchor forwards it to the enclosing vertical viewport.
struct MarkdownScrollWheelBridge: NSViewRepresentable {
  func makeNSView(context: Context) -> AnchorView { AnchorView() }
  func updateNSView(_ view: AnchorView, context: Context) {}

  static func dismantleNSView(_ view: AnchorView, coordinator: Void) {
    view.stopMonitoring()
  }

  final class AnchorView: NSView {
    private enum Direction { case pending, horizontal, vertical }

    private var monitor: NSObjectProtocol?
    private var direction: Direction?
    private weak var gestureViewport: NSScrollView?
    private weak var gestureParent: NSScrollView?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      stopMonitoring()
      guard window != nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        guard let self else { return event }
        return self.route(event)
      } as? NSObjectProtocol
    }

    override func viewDidMoveToSuperview() {
      super.viewDidMoveToSuperview()
      resetGesture()
    }

    func stopMonitoring() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      resetGesture()
    }

    private func resetGesture() {
      direction = nil
      gestureViewport = nil
      gestureParent = nil
    }

    private func verticalParent(of viewport: NSScrollView) -> NSScrollView? {
      var parent = viewport.superview
      while let view = parent {
        if let scroll = view as? NSScrollView,
           scroll.hasVerticalScroller || (scroll.documentView?.frame.height ?? 0) > scroll.contentSize.height {
          return scroll
        }
        parent = view.superview
      }
      return nil
    }

    private func owns(_ event: NSEvent, viewport: NSScrollView) -> Bool {
      guard !viewport.isHiddenOrHasHiddenAncestor,
            viewport.visibleRect.contains(viewport.convert(event.locationInWindow, from: nil)),
            let content = window?.contentView else { return false }
      let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
      var hit = content.hitTest(point)
      while let view = hit {
        if let scroll = view as? NSScrollView { return scroll === viewport }
        hit = view.superview
      }
      return false
    }

    private func eventDirection(_ event: NSEvent) -> Direction {
      if event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0 { return .pending }
      return !event.modifierFlags.contains(.shift)
        && abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) ? .vertical : .horizontal
    }

    private func route(_ event: NSEvent) -> NSEvent? {
      guard event.window === window, let viewport = enclosingScrollView else { return event }
      let discrete = event.phase.isEmpty && event.momentumPhase.isEmpty
      let begins = event.phase.contains(.began) || event.phase.contains(.mayBegin)
      if discrete || begins {
        resetGesture()
        guard owns(event, viewport: viewport), let parent = verticalParent(of: viewport) else { return event }
        gestureViewport = viewport
        gestureParent = parent
        direction = .pending
      }
      guard gestureViewport === viewport, let parent = gestureParent,
            parent.window === window, verticalParent(of: viewport) === parent else {
        resetGesture()
        return event
      }
      if direction == .pending { direction = eventDirection(event) }
      let forwards = direction == .vertical
      // End-of-touch and momentum are separate streams. Keep the destination
      // after touch ended so momentum stays there even if the pointer moves.
      if discrete || event.phase.contains(.cancelled)
        || event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled)
        || (event.phase.contains(.ended) && direction == .pending) {
        resetGesture()
      }
      guard forwards else { return event }
      parent.scrollWheel(with: event)
      return nil
    }
  }
}
#endif
