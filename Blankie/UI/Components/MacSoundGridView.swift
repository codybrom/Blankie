//
//  MacSoundGridView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/26/26.
//
//  macOS sound grid on `SortableGridView` with width-adaptive columns.
//  Reorder bridging mirrors the iOS `SoundGridView`.
//

#if os(macOS)
  import SwiftUI

  struct MacSoundGridView: View {
    let sounds: [Sound]
    var onMove: (IndexSet, Int) -> Void

    @State private var items: [SortableSoundMac]
    @State private var isDragging = false

    /// Minimum cell width.
    private let tileWidth: CGFloat = 120
    /// Maximum cell width in wide windows.
    private let maxTileWidth: CGFloat = 200
    private let spacing: CGFloat = 10

    init(sounds: [Sound], onMove: @escaping (IndexSet, Int) -> Void) {
      self.sounds = sounds
      self.onMove = onMove
      self._items = State(initialValue: sounds.map { SortableSoundMac(sound: $0) })
    }

    var body: some View {
      GeometryReader { geometry in
        // Column count is clamped to the item count so a small preset spreads
        // across the window.
        let fitting = max(2, Int(geometry.size.width / (tileWidth + spacing)))
        let count = max(2, min(fitting, items.count))
        let cellWidth = min(
          maxTileWidth,
          max(tileWidth, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
        )
        SortableGridView(
          isScrollable: true,
          config: .init(spacing: spacing, count: count),
          items: $items,
          minContentHeight: geometry.size.height
        ) { item in
          SoundIcon(sound: item.sound, maxWidth: cellWidth)
        } draggingPreview: { item in
          SoundIcon(sound: item.sound, maxWidth: cellWidth)
        } onDraggingChange: { _, _, dragging in
          if dragging {
            isDragging = true
          } else if isDragging {
            isDragging = false
            commitReorder()
            // onChange skips changes during a drag, so reconcile membership now.
            if Set(items.map(\.id)) != Set(sounds.map(\.id)) {
              let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
              items = sounds.map { SortableSoundMac(sound: $0, position: known[$0.id] ?? .zero) }
            }
          }
        }
        .onChange(of: sounds) { _, newSounds in
          guard !isDragging else { return }
          // Skip when the order matches: a rebuild resets positions to .zero.
          guard items.map(\.id) != newSounds.map(\.id) else { return }
          let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
          items = newSounds.map { SortableSoundMac(sound: $0, position: known[$0.id] ?? .zero) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sounds"))
        // Clicking empty space clears focus so the next Tab starts at the first tile.
        .contentShape(Rectangle())
        .onTapGesture {
          NSApp.keyWindow?.makeFirstResponder(nil)
        }
        // Clear AppKit's initial key focus so the first Tab starts at the first tile.
        .onAppear {
          DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
          }
        }
      }
    }

    /// A drag moves one tile, so the net change is a single move.
    private func commitReorder() {
      let originalIDs = sounds.map(\.id)
      let finalIDs = items.map(\.id)
      guard originalIDs != finalIDs else { return }

      guard
        let movedID = originalIDs.first(where: { id in
          originalIDs.filter { $0 != id } == finalIDs.filter { $0 != id }
        }),
        let from = originalIDs.firstIndex(of: movedID),
        let to = finalIDs.firstIndex(of: movedID)
      else { return }

      // `Array.move(fromOffsets:toOffset:)` inserts before the destination,
      // so a forward move needs +1.
      onMove(IndexSet(integer: from), to > from ? to + 1 : to)
    }
  }

  /// Gives a `Sound` the `position` the sortable grid tracks.
  private nonisolated struct SortableSoundMac: Identifiable, SortableGridProtocol {
    let sound: Sound
    var position: CGRect = .zero
    var id: Sound.ID { sound.id }
  }
#endif
