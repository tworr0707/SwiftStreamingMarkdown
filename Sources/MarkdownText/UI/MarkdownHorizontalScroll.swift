//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import SwiftUI

/// Scroll geometry stays local to the viewport; the host receives only overflow changes.
struct MarkdownHorizontalScrollMetrics: Equatable {
  var hasOverflow = false
  var hidesLeadingContent = false
  var hidesTrailingContent = false
  var visibleMinX: CGFloat = 0
  var visibleMaxX: CGFloat = 0

  init() {}

  init(contentWidth: CGFloat, viewportWidth: CGFloat, offsetX: CGFloat,
       contentInsets: EdgeInsets, visibleMinX: CGFloat,
       visibleMaxX: CGFloat, displayScale: CGFloat) {
    guard contentWidth.isFinite, viewportWidth.isFinite, viewportWidth > 0,
          offsetX.isFinite, contentInsets.leading.isFinite, contentInsets.trailing.isFinite,
          visibleMinX.isFinite, visibleMaxX.isFinite else { return }
    let tolerance = 1 / max(1, displayScale.isFinite ? displayScale : 1)
    let range = max(0, contentWidth + contentInsets.leading + contentInsets.trailing - viewportWidth)
    let progress = offsetX + contentInsets.leading
    hasOverflow = range > tolerance
    hidesLeadingContent = hasOverflow && progress > tolerance
    hidesTrailingContent = hasOverflow && range - progress > tolerance
    self.visibleMinX = visibleMinX
    self.visibleMaxX = visibleMaxX
  }
}

private struct MarkdownHorizontalScrollMetricsKey: EnvironmentKey {
  static let defaultValue = MarkdownHorizontalScrollMetrics()
}

extension EnvironmentValues {
  fileprivate var markdownHorizontalScrollMetrics: MarkdownHorizontalScrollMetrics {
    get { self[MarkdownHorizontalScrollMetricsKey.self] }
    set { self[MarkdownHorizontalScrollMetricsKey.self] = newValue }
  }
}

extension View {
  @ViewBuilder
  func markdownHorizontalScrollViewport() -> some View {
    if #available(iOS 18, macOS 15, *) {
      modifier(MarkdownHorizontalScrollViewportModifier())
    } else {
      self
    }
  }

  func markdownHorizontalScrollContent() -> some View {
    modifier(MarkdownHorizontalScrollContentModifier())
  }
}

@available(iOS 18, macOS 15, *)
private struct MarkdownHorizontalScrollViewportModifier: ViewModifier {
  @Environment(\.displayScale) private var displayScale
  @State private var metrics = MarkdownHorizontalScrollMetrics()

  func body(content: Content) -> some View {
    content
      .environment(\.markdownHorizontalScrollMetrics, metrics)
      .scrollIndicators(.automatic, axes: .horizontal)
      .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
      .onScrollGeometryChange(for: MarkdownHorizontalScrollMetrics.self) { geometry in
        MarkdownHorizontalScrollMetrics(
          contentWidth: geometry.contentSize.width,
          viewportWidth: geometry.containerSize.width,
          offsetX: geometry.contentOffset.x,
          contentInsets: geometry.contentInsets,
          visibleMinX: geometry.visibleRect.minX,
          visibleMaxX: geometry.visibleRect.maxX,
          displayScale: displayScale
        )
      } action: { _, next in
        metrics = next
      }
      #if os(iOS)
      .background {
        MarkdownHorizontalScrollAnchor(hasHorizontalOverflow: metrics.hasOverflow)
      }
      #endif
  }
}

private struct MarkdownHorizontalScrollContentModifier: ViewModifier {
  @Environment(\.markdownHorizontalScrollMetrics) private var metrics
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    content.mask {
      if metrics.hasOverflow && !reduceTransparency && contrast != .increased {
        GeometryReader { proxy in
          // The mask belongs to the content, leaving borders and native indicators intact.
          let width = max(1, proxy.size.width)
          let leading = min(max(0, metrics.visibleMinX), width)
          let trailing = min(max(leading, metrics.visibleMaxX), width)
          let fade = min(12, (trailing - leading) / 2)
          LinearGradient(stops: [
            .init(color: metrics.hidesLeadingContent ? .white.opacity(0.25) : .white, location: leading / width),
            .init(color: .white, location: min(trailing, leading + fade) / width),
            .init(color: .white, location: max(leading + fade, trailing - fade) / width),
            .init(color: metrics.hidesTrailingContent ? .white.opacity(0.25) : .white, location: trailing / width)
          ], startPoint: .leading, endPoint: .trailing)
        }
      } else {
        Rectangle().fill(.white)
      }
    }
  }
}
