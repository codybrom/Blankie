//
//  SoundGridView.swift
//  Blankie
//
//  Two-column tile grid with long-press-to-reorder, built on SortableGridView.
//
//  The dragged tile lifts into an overlay and the cells it passes over swap in
//  real time; the move is committed to the host exactly once, on release.
//
//  Bridging details:
//    • Sounds are wrapped in `SortableSound` so the `Sound` model needn't carry
//      layout state (`position`).
//    • A local `items` copy is reordered live during the drag. `onMove` is the
//      same (IndexSet, Int) callback the List view uses, so the reorder handler
//      in MixerView is shared unchanged. The single net move is recovered by
//      diffing the original order against the dropped order (see commitReorder).
//    • `onChange(of: sounds)` re-syncs `items` when the preset/order changes,
//      but only while no drag is in flight, so an in-progress reorder is never
//      yanked out from under the user.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct SoundGridView: View {
    let sounds: [Sound]
    var onMove: (IndexSet, Int) -> Void

    @State private var items: [SortableSound]
    @State private var isDragging = false

    init(sounds: [Sound], onMove: @escaping (IndexSet, Int) -> Void) {
      self.sounds = sounds
      self.onMove = onMove
      self._items = State(initialValue: sounds.map { SortableSound(sound: $0) })
    }

    var body: some View {
      SortableGridView(
        isScrollable: true,
        config: .init(spacing: 16, count: 2),
        items: $items
      ) { item in
        GridSoundButton(sound: item.sound)
      } draggingPreview: { item in
        GridSoundButton(sound: item.sound)
      } onDraggingChange: { _, _, dragging in
        if dragging {
          isDragging = true
        } else if isDragging {
          isDragging = false
          commitReorder()
        }
      }
      .safeAreaPadding(16)
      .onChange(of: sounds) { _, newSounds in
        guard !isDragging else { return }
        // After our own move commits, `sounds` returns in the order `items`
        // already holds. Rebuilding here would hand every tile a fresh struct
        // with `position == .zero`, and `onGeometryChange` won't re-fire when
        // nothing actually moves on screen — leaving the next drag with no
        // valid origin. So skip when the order already matches.
        guard items.map(\.id) != newSounds.map(\.id) else { return }
        // External change (preset switch, sound added/removed, reorder
        // elsewhere): rebuild, but carry over the last-known position for any
        // surviving tile so a cell whose geometry doesn't change still has a
        // valid drag origin. Genuinely new tiles get `.zero` and are filled in
        // by `onGeometryChange` as they lay out.
        let knownPositions = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
        items = newSounds.map { SortableSound(sound: $0, position: knownPositions[$0.id] ?? .zero) }
      }
    }

    /// SortableGridView reorders by repeatedly moving a single tile, so the net
    /// change from start to drop is always one element's move. Recover that
    /// (source, destination) by finding the one id whose removal reconciles the
    /// two orders, then forward it through the shared `onMove` handler.
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

      // `Array.move(fromOffsets:toOffset:)` (used by the host) inserts before
      // the destination, so a forward move needs +1 to land past the target.
      onMove(IndexSet(integer: from), to > from ? to + 1 : to)
    }
  }

  /// Lightweight wrapper that gives a `Sound` the mutable `position` the
  /// sortable grid tracks, without touching the `Sound` model itself.
  private struct SortableSound: Identifiable, SortableGridProtocol {
    let sound: Sound
    var position: CGRect = .zero
    var id: Sound.ID { sound.id }
  }

  #if DEBUG
    private func previewSounds() -> [Sound] {
      let specs: [(String, String, String)] = [
        ("Rain", "cloud.rain", "rain"),
        ("Waves", "water.waves", "waves"),
        ("Wind", "wind", "wind"),
        ("Birds", "bird", "birds"),
        ("Stream", "drop", "stream"),
        ("Storm", "cloud.bolt.rain", "storm"),
      ]
      return specs.enumerated().map { index, spec in
        Sound(
          title: spec.0,
          systemIconName: spec.1,
          fileName: spec.2,
          fileExtension: "m4a",
          defaultOrder: index + 1,
          lufs: nil,
          normalizationFactor: nil,
          truePeakdBTP: nil,
          needsLimiter: false,
          isCustom: false,
          fileURL: nil,
          dateAdded: nil,
          customSoundDataID: nil
        )
      }
    }

    #Preview {
      SoundGridView(
        sounds: previewSounds(),
        onMove: { _, _ in }
      )
    }
  #endif
#endif
