//
//  ReorderableGrid.swift
//  Blankie
//
//  Created by Claude Code on 6/10/25.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(iOS) || os(visionOS)
  /// Reorderable grid - items move in real-time as you drag, can drop in empty cells
  struct ReorderableGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    let spacing: CGFloat
    let isReorderEnabled: Bool
    let onMove: (Int, Int) -> Void
    @ViewBuilder let content: (Item, Bool) -> Content

    @State private var draggingItem: Item?

    var body: some View {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
        spacing: spacing
      ) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, _ in
          content(items[index], isReorderEnabled)
            .opacity(draggingItem?.id == items[index].id ? 0.5 : 1.0)
            .onDrag {
              if isReorderEnabled {
                draggingItem = items[index]
                // Use plain text to avoid system drop UI
                let provider = NSItemProvider(object: "" as NSString)
                provider.suggestedName = String(describing: items[index].id)
                return provider
              }
              return NSItemProvider()
            }
            .onDrop(of: [.plainText], delegate: ReorderDelegate(
              item: items[index],
              items: items,
              draggingItem: $draggingItem,
              onMove: onMove
            ))
        }

        // Add empty cells - always show full extra row when reordering
        if isReorderEnabled {
          let itemCount = items.count
          let remainder = itemCount % columns
          let emptyCellsCount = remainder == 0 ? columns : (columns - remainder) + columns

          ForEach(0 ..< emptyCellsCount, id: \.self) { _ in
            EmptyCell(
              items: items,
              draggingItem: $draggingItem,
              onMove: onMove
            )
          }
        }
      }
      .onDrop(of: [.plainText], delegate: CleanupDelegate(draggingItem: $draggingItem))
    }
  }

  // MARK: - Empty Cell

  private struct EmptyCell<Item: Identifiable>: View {
    let items: [Item]
    @Binding var draggingItem: Item?
    let onMove: (Int, Int) -> Void

    @State private var isTargeted = false

    var body: some View {
      RoundedRectangle(cornerRadius: 16)
        .stroke(
          isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
          style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [8, 4] : [4, 4])
        )
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .frame(height: 120)
        .onDrop(of: [.plainText], delegate: EmptyDropDelegate(
          items: items,
          draggingItem: $draggingItem,
          isTargeted: $isTargeted,
          onMove: onMove
        ))
    }
  }

  // MARK: - Reorder Delegate (for filled cells)

  private struct ReorderDelegate<Item: Identifiable>: DropDelegate {
    let item: Item
    let items: [Item]
    @Binding var draggingItem: Item?
    let onMove: (Int, Int) -> Void

    func dropEntered(info _: DropInfo) {
      guard let draggingItem = draggingItem,
            draggingItem.id != item.id,
            let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id }),
            let toIndex = items.firstIndex(where: { $0.id == item.id })
      else { return }

      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        onMove(fromIndex, toIndex)
      }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
      // Return .move to avoid copy/plus icon
      DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
      draggingItem = nil
      return true
    }
  }

  // MARK: - Empty Drop Delegate (for empty cells)

  private struct EmptyDropDelegate<Item: Identifiable>: DropDelegate {
    let items: [Item]
    @Binding var draggingItem: Item?
    @Binding var isTargeted: Bool
    let onMove: (Int, Int) -> Void

    func dropEntered(info _: DropInfo) {
      isTargeted = true

      guard let draggingItem = draggingItem,
            let fromIndex = items.firstIndex(where: { $0.id == draggingItem.id })
      else { return }

      // Move to the end of the list
      let toIndex = items.count
      if fromIndex != toIndex {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
          onMove(fromIndex, toIndex)
        }
      }
    }

    func dropExited(info _: DropInfo) {
      isTargeted = false
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
      // Return .move to avoid copy/plus icon
      DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
      isTargeted = false
      draggingItem = nil
      return true
    }
  }

  // MARK: - Cleanup Delegate (catches cancelled drags)

  private struct CleanupDelegate<Item: Identifiable>: DropDelegate {
    @Binding var draggingItem: Item?

    func performDrop(info _: DropInfo) -> Bool {
      // Reset state if dropped outside valid targets
      draggingItem = nil
      return false
    }
  }
#endif
