//
//  SortableGridView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/24/26.
//
//  Long-press-to-reorder grid, adapted from Balaji Venkatesh's "Sortable Grid"
//  (28/01/26). The dragged tile is lifted into an overlay preview while the
//  underlying cells swap live as it passes over them; the host commits the
//  final order once, on release.
//
//  Two deviations from the original recipe:
//    • Elements don't have to carry their own `position` — callers wrap their
//      model in a tiny `SortableGridProtocol` value (see SortableSound) so the
//      `Sound` model stays untouched.
//    • The reorder gesture is attached per-tile via `.reorderHandle()` on just
//      the tile's icon/tap-zone, never the whole cell. A brief long-press
//      preroll alone wasn't enough to protect an inline volume slider: the
//      composed long-press→drag still claimed the touch in the gesture arena
//      and starved the slider's own drag (the slider would grab but not move,
//      while the tile never actually reordered). Scoping the gesture off the
//      slider region is the real fix. `SortableGridView` injects the per-cell
//      callbacks through the environment, so the generic content API and its
//      callers stay unchanged.
//
//  Pure SwiftUI and identical on every platform (long-press → drag), so the
//  lift/swap/commit behavior is shared.
//

import SwiftUI

protocol SortableGridProtocol: Identifiable {
  var position: CGRect { get set }
}

struct SortableGridView<
  Content: View, DraggingPreview: View, Data: RandomAccessCollection
>: View
where
  Data.Element: SortableGridProtocol, Data: MutableCollection, Data: RangeReplaceableCollection
{
  /// Captured once on init — we don't want a scroll/no-scroll flip mid-drag.
  @State var isScrollable: Bool
  var config: SortableGridConfig
  @Binding var items: Data
  /// Scrollable grids only: content shorter than this is centered vertically.
  /// Pass the viewport height to center sparse grids (cell rects are tracked
  /// in .global coordinates, so the shift doesn't disturb reordering).
  var minContentHeight: CGFloat? = nil
  @ViewBuilder var content: (Data.Element) -> Content
  @ViewBuilder var draggingPreview: (Data.Element) -> DraggingPreview
  var onDraggingChange: (_ location: CGPoint, _ offset: CGSize, _ isDragging: Bool) -> Void

  @State private var isDragging: Bool = false
  @State private var draggingItem: Data.Element?
  @State private var draggingStartRect: CGRect?
  @State private var draggingStartLocation: CGPoint?
  @State private var gridOrigin: CGPoint = .zero
  @State private var draggingOffset: CGSize = .zero
  @State private var swapLock: Bool = false

  var body: some View {
    Group {
      if isScrollable {
        ScrollView(.vertical) {
          gridContent
            .frame(minHeight: minContentHeight)
        }
        .scrollDisabled(isDragging)
      } else {
        gridContent
      }
    }
    .overlay(alignment: .topLeading) {
      if let draggingItem, let draggingStartRect {
        draggingPreview(draggingItem)
          .disabled(true)
          .allowsHitTesting(false)
          // Transient floating copy of the lifted tile. Hide duplicate from assistive technologies
          .accessibilityHidden(true)
          .frame(width: draggingStartRect.width, height: draggingStartRect.height)
          .animation(.snappy(duration: 0.3, extraBounce: 0)) { content in
            content
              .scaleEffect(isDragging ? config.previewScale : 1)
          }
          // Cell rects and the finger are tracked in .global (reliable inside
          // the iPad split-view detail pane, where a custom named space did
          // not resolve). Localize to this overlay by subtracting the grid's
          // own global origin.
          .offset(
            x: draggingStartRect.minX - gridOrigin.x,
            y: draggingStartRect.minY - gridOrigin.y
          )
          .offset(draggingOffset)
      }
    }
    // Block interaction with the grid while a tile is in flight.
    .onGeometryChange(for: CGPoint.self) {
      $0.frame(in: .global).origin
    } action: {
      gridOrigin = $0
    }

  }

  @ViewBuilder
  private var gridContent: some View {
    let columns: [GridItem] = Array(
      repeating: GridItem(spacing: config.spacing), count: config.count)

    LazyVGrid(columns: columns, spacing: config.spacing) {
      ForEach($items) { $item in
        // Captured at render time, while the element binding's index is valid.
        // The geometry action below can fire AFTER `items` shrinks (preset
        // switch relayouts every cell); writing through the positional `$item`
        // binding then traps out-of-bounds, so it writes by id lookup instead.
        let itemID = item.id
        content(item)
          // Hand each tile its reorder callbacks via the environment; the tile
          // attaches the gesture to just its icon/tap-zone with `.reorderHandle()`
          // so it never overlaps the inline volume slider.
          .environment(
            \.reorderHandlers,
            ReorderHandlers(
              onStart: { handleReorderStart(item: item) },
              onChanged: { location in handleReorderChange(location, item: item) },
              onEnd: { handleReorderEnd() }
            )
          )
          .opacity(draggingItem?.id == item.id ? 0 : 1)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
          } action: { newValue in
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            items[index].position = newValue
          }
      }
    }
  }

  // MARK: - Shared reorder handlers

  private func handleReorderStart(item: Data.Element) {
    if draggingItem == nil {
      draggingItem = item
      draggingStartRect = item.position
      draggingStartLocation = CGPoint(x: item.position.midX, y: item.position.midY)
      isDragging = true
    }
  }

  /// Called continuously while a tile is being dragged. `location` is in
  /// `.global` space.
  private func handleReorderChange(_ location: CGPoint, item: Data.Element) {
    if draggingItem == nil {
      draggingItem = item
      draggingStartRect = item.position
      draggingStartLocation = location
      isDragging = true
    }

    // `location` and the cell rects are both in .global, so the preview offset
    // is just the global delta since pickup; the overlay localizes it via
    // `gridOrigin`.
    if let start = draggingStartLocation {
      draggingOffset = CGSize(
        width: location.x - start.x,
        height: location.y - start.y
      )
    }
    reorderData(location: location)
    onDraggingChange(location, draggingOffset, true)
  }

  /// Called when the drag gesture ends: settle the lifted preview, then drop it.
  private func handleReorderEnd() {
    guard draggingItem != nil else { return }
    onDraggingChange(.zero, .zero, false)
    DispatchQueue.main.async {
      withAnimation(
        .snappy(duration: 0.3, extraBounce: 0),
        completionCriteria: .logicallyComplete
      ) {
        isDragging = false
        draggingOffset = .zero
        if let sourceIndex = items.firstIndex(where: {
          $0.id == draggingItem?.id
        }) {
          draggingStartRect = items[sourceIndex].position
        }
      } completion: {
        draggingItem = nil
        draggingStartRect = nil
        draggingStartLocation = nil
      }
    }
  }

  private func reorderData(location: CGPoint) {
    guard let draggingItem,
      let sourceIndex = items.firstIndex(where: { $0.id == draggingItem.id }), !swapLock
    else { return }

    let destIndex = items.firstIndex(where: { $0.position.contains(location) })

    guard let destIndex, destIndex != sourceIndex else { return }

    swapLock = true
    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
      let item = items.remove(at: sourceIndex)
      items.insert(item, at: destIndex)
    }

    // Debounce so a single pass over a cell triggers one swap, not many.
    DispatchQueue.main.async {
      swapLock = false
    }
  }

}

struct SortableGridConfig {
  var spacing: CGFloat = 10
  var count: Int = 2
  var previewScale: CGFloat = 1.06
}

// MARK: - Scoped reorder handle

/// Per-cell reorder callbacks, injected by `SortableGridView` into each cell's
/// environment so a tile can attach the long-press→drag gesture to just its
/// drag-region (the icon/tap-zone), leaving sibling controls like the inline
/// volume slider fully interactive.
struct ReorderHandlers {
  var onStart: () -> Void = {}
  var onChanged: (CGPoint) -> Void = { _ in }
  var onEnd: () -> Void = {}
}

private struct ReorderHandlersKey: EnvironmentKey {
  static let defaultValue = ReorderHandlers()
}

extension EnvironmentValues {
  var reorderHandlers: ReorderHandlers {
    get { self[ReorderHandlersKey.self] }
    set { self[ReorderHandlersKey.self] = newValue }
  }
}

#if os(iOS)
  import UIKit

  struct ReorderLongPressGesture: UIGestureRecognizerRepresentable {
    typealias UIGestureRecognizerType = UILongPressGestureRecognizer

    var minimumPressDuration: TimeInterval = 0.35
    var allowableMovement: CGFloat = 15.0

    var onStart: () -> Void
    var onChanged: (CGPoint) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
      let recognizer = UILongPressGestureRecognizer()
      recognizer.minimumPressDuration = minimumPressDuration
      recognizer.allowableMovement = allowableMovement
      return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
      recognizer.minimumPressDuration = minimumPressDuration
      recognizer.allowableMovement = allowableMovement
    }

    func handleUIGestureRecognizerAction(
      _ recognizer: UILongPressGestureRecognizer, context: Context
    ) {
      let globalLocation = context.converter.location(in: .global)

      switch recognizer.state {
      case .began:
        onStart()
        onChanged(globalLocation)
      case .changed:
        onChanged(globalLocation)
      case .ended, .cancelled, .failed:
        onEnd()
      default:
        break
      }
    }
  }
#endif

struct ReorderHandleModifier: ViewModifier {
  @Environment(\.reorderHandlers) private var handlers
  @State private var hasStartedDragging = false

  func body(content: Content) -> some View {
    #if os(iOS)
      content
        .gesture(
          ReorderLongPressGesture(
            onStart: { handlers.onStart() },
            onChanged: { handlers.onChanged($0) },
            onEnd: { handlers.onEnd() }
          )
        )
    #else
      content
        .gesture(
          DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
              if !hasStartedDragging {
                handlers.onStart()
                hasStartedDragging = true
              }
              handlers.onChanged(value.location)
            }
            .onEnded { _ in
              if hasStartedDragging {
                handlers.onEnd()
                hasStartedDragging = false
              }
            }
        )
    #endif
  }
}

extension View {
  /// Attaches the reorder gesture (long-press preroll → drag) to *this* region
  /// only, pulling the per-cell callbacks from the environment that
  /// `SortableGridView` set. Put it on a tile's icon/tap-zone so the gesture
  /// never overlaps an inline volume slider — the slider's own drag stays
  /// uncontested in the gesture arena. The finger is reported in `.global`
  /// (matching the cells' `frame(in: .global)`). Pure SwiftUI, identical on
  /// every platform.
  func reorderHandle() -> some View {
    modifier(ReorderHandleModifier())
  }
}
