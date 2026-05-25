//
//  SortableGridView.swift
//  Blankie
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
//    • The reorder gesture ignores touches that begin on a `UIControl`
//      (the volume `Slider` is UISlider-backed), so adjusting volume never
//      starts a tile move.
//

import SwiftUI

#if os(iOS) || os(visionOS)
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
          }
        } else {
          gridContent
        }
      }
      .overlay(alignment: .topLeading) {
        if let draggingItem, let draggingStartRect {
          draggingPreview(draggingItem)
            .disabled(true)
            .allowsHitTesting(false)
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
              y: draggingStartRect.minY - gridOrigin.y)
            .offset(draggingOffset)
        }
      }
      // Block interaction with the grid while a tile is in flight.
      .allowsHitTesting(draggingItem == nil)
      .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: {
        gridOrigin = $0
      }
    }

    @ViewBuilder
    private var gridContent: some View {
      let columns: [GridItem] = Array(
        repeating: GridItem(spacing: config.spacing), count: config.count)

      LazyVGrid(columns: columns, spacing: config.spacing) {
        ForEach($items) { $item in
          content(item)
            .opacity(draggingItem?.id == item.id ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGRect.self) {
              $0.frame(in: .global)
            } action: { newValue in
              item.position = newValue
            }
            .gesture(
              ReorderLongPressGesture(
                onChanged: { location in
                  if draggingItem == nil {
                    draggingItem = item
                    draggingStartRect = item.position
                    draggingStartLocation = location
                    DispatchQueue.main.async {
                      isDragging = true
                    }
                  }

                  // `location` and the cell rects are both in .global, so the
                  // preview offset is just the global delta since pickup; the
                  // overlay localizes it via `gridOrigin`.
                  if let start = draggingStartLocation {
                    draggingOffset = CGSize(
                      width: location.x - start.x,
                      height: location.y - start.y
                    )
                  }
                  reorderData(location: location)
                  onDraggingChange(location, draggingOffset, true)
                },
                onEnd: {
                  onDraggingChange(.zero, .zero, false)
                  // Settle the lifted preview back onto the grid, then drop it.
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
              )
            )
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

  /// Long-press recognizer that reports the finger location in window/global
  /// space. It declines touches that land on a `UIControl` so the inline
  /// volume slider stays draggable.
  private struct ReorderLongPressGesture: UIGestureRecognizerRepresentable {
    var duration: CGFloat = 0.16
    var onChanged: (_ location: CGPoint) -> Void
    var onEnd: () -> Void

    func makeCoordinator(converter _: CoordinateSpaceConverter) -> Coordinator {
      Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
      let gesture = UILongPressGestureRecognizer()
      gesture.minimumPressDuration = duration
      gesture.numberOfTapsRequired = 0
      gesture.numberOfTouchesRequired = 1
      gesture.delegate = context.coordinator
      return gesture
    }

    func updateUIGestureRecognizer(
      _ recognizer: UILongPressGestureRecognizer, context: Context
    ) {}

    func handleUIGestureRecognizerAction(
      _ recognizer: UILongPressGestureRecognizer, context: Context
    ) {
      // Let SwiftUI convert the recognizer's *current location* into the global
      // SwiftUI coordinate space. Reading the raw UIKit `location(in: nil)` is
      // wrong here: in landscape it's the screen-fixed (portrait) space, rotated
      // 90° from SwiftUI's rendering space. `converter.location(in:)` accounts
      // for orientation/scale and matches the cells' `frame(in: .global)`.
      switch recognizer.state {
      case .began, .changed:
        onChanged(context.converter.location(in: .global))
      default:
        onEnd()
      }
    }

    /// Lets the volume slider win: a touch starting on any `UIControl`
    /// (UISlider-backed) is not delivered to the reorder gesture.
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
      ) -> Bool {
        var view = touch.view
        while let current = view {
          if current is UIControl { return false }
          view = current.superview
        }
        return true
      }
    }
  }
#endif
