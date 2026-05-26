//
//  MacSoundGridView.swift
//  Blankie
//
//  Created by Cody Bromley on 5/26/26.
//
//  macOS sound grid that reuses the same long-press lift-and-reorder engine as
//  iOS (`SortableGridView`), with `SoundIcon` tiles and width-adaptive columns.
//  Mirrors the iOS `SoundGridView` bridging (a local `SortableSound` copy
//  reordered live during the drag, with the single net move recovered on
//  release) so the reorder feels identical across platforms.
//

#if os(macOS)
  import SwiftUI

  struct MacSoundGridView: View {
    let sounds: [Sound]
    var onMove: (IndexSet, Int) -> Void

    @State private var items: [SortableSoundMac]
    @State private var isDragging = false

    private let tileWidth: CGFloat = 120
    private let spacing: CGFloat = 10

    init(sounds: [Sound], onMove: @escaping (IndexSet, Int) -> Void) {
      self.sounds = sounds
      self.onMove = onMove
      self._items = State(initialValue: sounds.map { SortableSoundMac(sound: $0) })
    }

    var body: some View {
      GeometryReader { geometry in
        let count = max(2, Int(geometry.size.width / (tileWidth + spacing)))
        SortableGridView(
          isScrollable: true,
          config: .init(spacing: spacing, count: count),
          items: $items
        ) { item in
          SoundIcon(sound: item.sound, maxWidth: tileWidth)
        } draggingPreview: { item in
          SoundIcon(sound: item.sound, maxWidth: tileWidth)
        } onDraggingChange: { _, _, dragging in
          if dragging {
            isDragging = true
          } else if isDragging {
            isDragging = false
            commitReorder()
            // A membership change that arrived mid-drag was skipped (see
            // onChange below); reconcile now if the set of tiles differs. A pure
            // reorder keeps the same set and is left for commitReorder/onChange.
            if Set(items.map(\.id)) != Set(sounds.map(\.id)) {
              let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
              items = sounds.map { SortableSoundMac(sound: $0, position: known[$0.id] ?? .zero) }
            }
          }
        }
        .onChange(of: sounds) { _, newSounds in
          guard !isDragging else { return }
          // After our own move commits, `sounds` returns in the order `items`
          // already holds; rebuilding would reset every position to .zero and
          // leave the next drag with no valid origin. Skip when order matches.
          guard items.map(\.id) != newSounds.map(\.id) else { return }
          let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
          items = newSounds.map { SortableSoundMac(sound: $0, position: known[$0.id] ?? .zero) }
        }
      }
    }

    /// SortableGridView reorders by repeatedly moving one tile, so the net
    /// change is always a single element's move. Recover that (source,
    /// destination) and forward it through the shared `onMove` handler.
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

      // `Array.move(fromOffsets:toOffset:)` inserts before the destination, so a
      // forward move needs +1 to land past the target.
      onMove(IndexSet(integer: from), to > from ? to + 1 : to)
    }
  }

  /// Gives a `Sound` the mutable `position` the sortable grid tracks, without
  /// touching the `Sound` model.
  private struct SortableSoundMac: Identifiable, SortableGridProtocol {
    let sound: Sound
    var position: CGRect = .zero
    var id: Sound.ID { sound.id }
  }
#endif
