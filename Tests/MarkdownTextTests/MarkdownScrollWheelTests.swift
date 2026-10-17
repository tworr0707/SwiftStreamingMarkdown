//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if os(macOS)
import AppKit
@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest

@MainActor
final class MarkdownScrollWheelTests: XCTestCase {
  func testVerticalWheelOverTableScrollsParent() async throws {
    for columns in [1, 4] {
      for localY in [20.0, 65.0, 180.0] {
        let fixture = try await Fixture(columns: columns)
        defer { fixture.close() }
        let horizontal = try XCTUnwrap(fixture.horizontal)
        let before = fixture.outer.contentView.bounds.minY
        let horizontalBefore = horizontal.contentView.bounds.minX
        NSApp.sendEvent(try fixture.event(x: 0, y: -3, localY: localY))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertGreaterThan(fixture.outer.contentView.bounds.minY, before, "columns=\(columns), y=\(localY)")
        XCTAssertEqual(horizontal.contentView.bounds.minX, horizontalBefore)
        XCTAssertEqual(fixture.outer.wheelCount, 1)
      }
    }
  }

  func testHorizontalShiftAndDiagonalWheelStayNative() async throws {
    for input in [(-3, 0, NSEvent.ModifierFlags()), (0, -3, .shift), (-3, -3, [])] {
      let fixture = try await Fixture()
      defer { fixture.close() }
      let horizontal = try XCTUnwrap(fixture.horizontal)
      NSApp.sendEvent(try fixture.event(x: Int32(input.0), y: Int32(input.1), flags: input.2))
      try await Task.sleep(for: .milliseconds(40))
      if input.1 == 0 { XCTAssertGreaterThan(horizontal.contentView.bounds.minX, 0) }
      XCTAssertEqual(fixture.outer.wheelCount, 0)
      XCTAssertEqual(fixture.outer.contentView.bounds.minY, 0)
    }
  }

  func testVerticalGestureKeepsDestinationThroughMomentum() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    let horizontal = try XCTUnwrap(fixture.horizontal)
    let began = try fixture.event(x: 0, y: -4, phase: .began)
    NSApp.sendEvent(began)
    // The dominant axis and pointer position both change, but ownership stays.
    NSApp.sendEvent(try fixture.event(x: -8, y: -1, phase: .changed))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, phase: .ended))
    let away = NSPoint(x: 460, y: 10)
    NSApp.sendEvent(try fixture.event(x: 0, y: -2, momentum: .began, point: away))
    NSApp.sendEvent(try fixture.event(x: 0, y: -1, momentum: .changed, point: away))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, momentum: .ended, point: away))
    XCTAssertEqual(fixture.outer.wheelCount, 6)
    XCTAssertTrue(fixture.outer.received.first === began)
    XCTAssertEqual(horizontal.contentView.bounds.minX, 0)
  }

  func testHorizontalGestureDoesNotChangeAxisAtAnEndpoint() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    NSApp.sendEvent(try fixture.event(x: 4, y: 0, phase: .began))
    NSApp.sendEvent(try fixture.event(x: 0, y: -8, phase: .changed))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, phase: .ended))
    NSApp.sendEvent(try fixture.event(x: 0, y: -4, momentum: .began))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, momentum: .ended))
    XCTAssertEqual(fixture.outer.wheelCount, 0)
  }

  func testZeroStartCancellationAndNewGesture() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, phase: .mayBegin))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, phase: .began))
    XCTAssertEqual(fixture.outer.wheelCount, 0)
    NSApp.sendEvent(try fixture.event(x: 0, y: -3, phase: .changed))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, phase: .cancelled))
    XCTAssertEqual(fixture.outer.wheelCount, 2)
    NSApp.sendEvent(try fixture.event(x: -3, y: 0, phase: .began))
    NSApp.sendEvent(try fixture.event(x: 0, y: -3, phase: .changed))
    NSApp.sendEvent(try fixture.event(x: 0, y: 0, phase: .cancelled))
    XCTAssertEqual(fixture.outer.wheelCount, 2)
  }

  func testCodeAndEquationUseTheSameForwarding() async throws {
    for kind in [Fixture.Kind.code, .equation] {
      let fixture = try await Fixture(kind: kind)
      defer { fixture.close() }
      NSApp.sendEvent(try fixture.event(x: 0, y: -3, localY: 10))
      try await Task.sleep(for: .milliseconds(40))
      XCTAssertEqual(fixture.outer.wheelCount, 1)
      XCTAssertGreaterThan(fixture.outer.contentView.bounds.minY, 0)
    }
  }

  func testSiblingViewportsForwardEachEventOnlyOnce() async throws {
    let fixture = try await Fixture(kind: .siblings)
    defer { fixture.close() }
    let scrolls = fixture.scrollViews(in: fixture.outer).filter { $0 !== fixture.outer }
    XCTAssertEqual(scrolls.count, 2)
    let first = try XCTUnwrap(scrolls.first)
    let second = try XCTUnwrap(scrolls.last)
    let firstPoint = first.convert(NSPoint(x: 50, y: 20), to: nil)
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: firstPoint, x: 0, y: -1, phase: .began))
    let secondPoint = second.convert(NSPoint(x: 50, y: 20), to: nil)
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: secondPoint, x: 0, y: -1, phase: .changed))
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: secondPoint, x: 0, y: 0, phase: .ended))
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: secondPoint, x: 0, y: -1, momentum: .began))
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: secondPoint, x: 0, y: 0, momentum: .ended))
    XCTAssertEqual(fixture.outer.wheelCount, 5)
    let newPoint = second.convert(NSPoint(x: 50, y: 20), to: nil)
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: newPoint, x: 0, y: -1))
    XCTAssertEqual(fixture.outer.wheelCount, 6)
    XCTAssertEqual(first.contentView.bounds.minX, 0)
    XCTAssertEqual(second.contentView.bounds.minX, 0)
  }

  func testVerticalWheelWorksInBothDirectionsAtParentBoundaries() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    let horizontal = try XCTUnwrap(fixture.horizontal)
    NSApp.sendEvent(try fixture.event(x: 0, y: 3))
    XCTAssertEqual(fixture.outer.wheelCount, 1)
    XCTAssertEqual(fixture.outer.contentView.bounds.minY, 0)
    try await Task.sleep(for: .milliseconds(200))
    NSApp.sendEvent(try fixture.event(x: 0, y: -3))
    try await Task.sleep(for: .milliseconds(40))
    XCTAssertEqual(fixture.outer.wheelCount, 2)
    XCTAssertGreaterThan(fixture.outer.contentView.bounds.minY, 0)
    NSApp.sendEvent(try fixture.event(x: 0, y: 3))
    try await Task.sleep(for: .milliseconds(40))
    XCTAssertEqual(fixture.outer.wheelCount, 3)
    XCTAssertEqual(fixture.outer.contentView.bounds.minY, 0)
    XCTAssertEqual(horizontal.contentView.bounds.minX, 0)
  }

  func testOtherWindowAndOverlayAreNotIntercepted() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    let other = try await Fixture()
    defer { other.close() }
    NSApp.sendEvent(try other.event(x: 0, y: -3))
    XCTAssertEqual(other.outer.wheelCount, 1)
    XCTAssertEqual(fixture.outer.wheelCount, 0)
    let blocker = NSView(frame: fixture.outer.bounds)
    fixture.outer.addSubview(blocker)
    NSApp.sendEvent(try fixture.event(x: 0, y: -3))
    XCTAssertEqual(fixture.outer.wheelCount, 0)
  }

  func testMissingVerticalParentLeavesNativeDispatch() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    let host = try XCTUnwrap(fixture.outer.documentView)
    fixture.outer.documentView = nil
    fixture.window.contentView = host
    host.frame.size = NSSize(width: 480, height: 400)
    host.layoutSubtreeIfNeeded()
    let scroll = try XCTUnwrap(fixture.scrollViews(in: host).first)
    let point = scroll.convert(NSPoint(x: 50, y: 20), to: nil)
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: point, x: 0, y: -3))
    XCTAssertEqual(fixture.outer.wheelCount, 0)
  }

  func testReparentingClearsTheOldGestureDestination() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    NSApp.sendEvent(try fixture.event(x: 0, y: -1, phase: .began))
    let host = try XCTUnwrap(fixture.outer.documentView)
    fixture.outer.documentView = nil
    let replacement = CountingScrollView(frame: fixture.outer.frame)
    replacement.hasVerticalScroller = true
    replacement.documentView = host
    fixture.window.contentView = replacement
    replacement.layoutSubtreeIfNeeded()
    let scroll = try XCTUnwrap(fixture.scrollViews(in: replacement).last)
    let point = scroll.convert(NSPoint(x: 100, y: 30), to: nil)
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: point, x: 0, y: -1, momentum: .changed))
    XCTAssertEqual(fixture.outer.wheelCount, 1)
    XCTAssertEqual(replacement.wheelCount, 0)
    NSApp.sendEvent(try WheelEvent(window: fixture.window, point: point, x: 0, y: -3))
    XCTAssertEqual(replacement.wheelCount, 1)
  }

  func testDetachRemovesMonitorAndReattachInstallsOnlyOne() async throws {
    let fixture = try await Fixture()
    defer { fixture.close() }
    let anchor = try XCTUnwrap(fixture.anchors.first)
    let event = try fixture.event(x: 0, y: -3)
    let content = try XCTUnwrap(fixture.window.contentView)
    fixture.window.contentView = nil
    XCTAssertNil(anchor.window)
    NSApp.sendEvent(event)
    XCTAssertEqual(fixture.outer.wheelCount, 0)
    fixture.window.contentView = content
    content.layoutSubtreeIfNeeded()
    NSApp.sendEvent(try fixture.event(x: 0, y: -3))
    XCTAssertEqual(fixture.outer.wheelCount, 1)
    XCTAssertFalse(anchor.isAccessibilityElement())
    XCTAssertNil(anchor.hitTest(.zero))
  }

  private final class CountingScrollView: NSScrollView {
    var wheelCount = 0
    var received: [NSEvent] = []
    override func scrollWheel(with event: NSEvent) {
      wheelCount += 1
      received.append(event)
      super.scrollWheel(with: event)
    }
  }

  @MainActor
  private final class Fixture {
    enum Kind { case table, code, equation, siblings }
    let window: NSWindow
    let outer: CountingScrollView
    var horizontal: NSScrollView? {
      scrollViews(in: outer).first { $0 !== outer }
    }

    var anchors: [MarkdownScrollWheelBridge.AnchorView] {
      descendants(in: outer).compactMap { $0 as? MarkdownScrollWheelBridge.AnchorView }
    }

    init(columns: Int = 4, kind: Kind = .table) async throws {
      _ = NSApplication.shared
      window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 480, height: 400),
                        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      outer = CountingScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 400))
      outer.hasVerticalScroller = true
      outer.scrollerStyle = .overlay
      let headings = (0..<columns).map { NSMutableAttributedString(string: "Header \($0)") }
      let rows = (0..<4).map { row in
        (0..<columns).map { _ in NSMutableAttributedString(string: "Cell \(row) long content for scrolling") }
      }
      let equation = try CompiledLatex.compile(String(repeating: "x+", count: 60) + "1").get()
      let host = NSHostingView(rootView: VStack(spacing: 0) {
        switch kind {
        case .table: TableView(headings: headings, rows: rows)
        case .siblings:
          TableView(headings: headings, rows: rows)
          TableView(headings: headings, rows: rows)
        case .code: CodeBlockView(language: "swift", code: String(repeating: "let x = 1; ", count: 60))
        case .equation: SingleBlockView(renderable: .latex(id: "wheel-test", content: equation))
        }
        Spacer(minLength: 1200)
      }.frame(width: 480, height: 1600, alignment: .top))
      host.frame = NSRect(x: 0, y: 0, width: 480, height: 1600)
      outer.documentView = host
      window.contentView = outer
      window.orderFrontRegardless()
      for _ in 0..<5 {
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
      }
      XCTAssertNotNil(horizontal, "Expected a native horizontal viewport")
    }

    func event(x: Int32, y: Int32, phase: NSEvent.Phase = [], momentum: NSEvent.Phase = [],
               flags: NSEvent.ModifierFlags = [], point: NSPoint? = nil, localY: CGFloat = 30) throws -> NSEvent {
      let scroll = try XCTUnwrap(horizontal)
      let location = point ?? scroll.convert(NSPoint(x: 100, y: localY), to: nil)
      return try WheelEvent(window: window, point: location, x: x, y: y, phase: phase, momentum: momentum, flags: flags)
    }

    func close() {
      window.contentView = nil
      window.close()
    }

    func scrollViews(in view: NSView) -> [NSScrollView] {
      descendants(in: view).compactMap { $0 as? NSScrollView }
    }

    private func descendants(in view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap(descendants)
    }
  }

  // CG-created events have no destination window. Supply one while keeping a
  // real scroll CGEvent behind the properties AppKit uses during dispatch.
  private final class WheelEvent: NSEvent {
    let target: NSWindow
    let targetNumber: Int
    let point: NSPoint
    let source: NSEvent
    let backingEvent: CGEvent

    @MainActor
    init(window: NSWindow, point: NSPoint, x: Int32, y: Int32, phase: NSEvent.Phase = [],
         momentum: NSEvent.Phase = [], flags: NSEvent.ModifierFlags = []) throws {
      target = window
      targetNumber = window.windowNumber
      self.point = point
      backingEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: phase.isEmpty && momentum.isEmpty ? .line : .pixel,
                                          wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0))
      if !phase.isEmpty || !momentum.isEmpty {
        backingEvent.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
      }
      backingEvent.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
      let phaseValue: Int64 = phase.contains(.mayBegin) ? 128 : phase.contains(.began) ? 1
        : phase.contains(.changed) ? 2 : phase.contains(.ended) ? 4 : phase.contains(.cancelled) ? 8 : 0
      backingEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phaseValue)
      let momentumValue: Int64 = momentum.contains(.began) ? 1 : momentum.contains(.changed) ? 2 : momentum.contains(.ended) ? 3 : 0
      backingEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumValue)
      source = try XCTUnwrap(NSEvent(cgEvent: backingEvent))
      super.init()
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
    override var type: NSEvent.EventType { .scrollWheel }
    override var window: NSWindow? { target }
    override var windowNumber: Int { targetNumber }
    override var locationInWindow: NSPoint { point }
    override var cgEvent: CGEvent? { backingEvent }
    override var phase: NSEvent.Phase { source.phase }
    override var momentumPhase: NSEvent.Phase { source.momentumPhase }
    override var scrollingDeltaX: CGFloat { source.scrollingDeltaX }
    override var scrollingDeltaY: CGFloat { source.scrollingDeltaY }
    override var deltaX: CGFloat { source.deltaX }
    override var deltaY: CGFloat { source.deltaY }
    override var hasPreciseScrollingDeltas: Bool { source.hasPreciseScrollingDeltas }
    override var modifierFlags: NSEvent.ModifierFlags { source.modifierFlags }
    override var timestamp: TimeInterval { source.timestamp }
  }
}
#endif
