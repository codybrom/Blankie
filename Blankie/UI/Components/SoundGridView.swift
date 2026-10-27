//
//  SoundGridView.swift
//  Blankie
//
//  Created by Cody Bromley on 2/22/26.
//
//  Two-column tile grid with long-press-to-reorder, built on SortableGridView.
//  Reorders a local copy during the drag and commits one `onMove` on release.
//

import SwiftUI

#if os(iOS) || os(visionOS)
  struct SoundGridView: View {
    let sounds: [Sound]
    var onMove: (IndexSet, Int) -> Void
    var tile: (Sound) -> GridSoundButton
    var columns = 2

    @State private var items: [SortableSound]
    @State private var isDragging = false
    @State private var fold = FoldInfo.none
    /// Set by the nightstand, whose bar sits below the tiles.
    @Environment(\.soundTileHeight) private var tileHeight
    @State private var width: CGFloat = 0

    init(
      sounds: [Sound],
      onMove: @escaping (IndexSet, Int) -> Void,
      tile: @escaping (Sound) -> GridSoundButton = { GridSoundButton(sound: $0) },
      columns: Int = 2
    ) {
      self.columns = columns
      self.sounds = sounds
      self.onMove = onMove
      self.tile = tile
      self._items = State(initialValue: sounds.map { SortableSound(sound: $0) })
    }

    /// On a bent iPhone Duo the column gap becomes the crease band. The fold
    /// frame and the measured width share this view's local space.
    private var creaseInsets: (leading: CGFloat, trailing: CGFloat, columnSpacing: CGFloat) {
      columns == 2
        ? CreaseInsets.twoColumn(containerWidth: width, margin: 16, spacing: 16, fold: fold)
        : (16, 16, 16)
    }

    var body: some View {
      let insets = creaseInsets
      SortableGridView(
        isScrollable: true,
        config: .init(spacing: 16, count: columns, columnSpacing: insets.columnSpacing),
        items: $items
      ) { item in
        tile(item.sound)
      } draggingPreview: { item in
        tile(item.sound)
      } onDraggingChange: { _, _, dragging in
        if dragging {
          isDragging = true
        } else if isDragging {
          isDragging = false
          commitReorder()
          // `onChange(of: sounds)` skips changes during a drag, so reconcile
          // membership changes now. A pure reorder is left to `commitReorder`.
          if Set(items.map(\.id)) != Set(sounds.map(\.id)) {
            let known = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
            items = sounds.map { SortableSound(sound: $0, position: known[$0.id] ?? .zero) }
          }
        }
      }
      .safeAreaPadding(.vertical, 16)
      .safeAreaPadding(.leading, insets.leading)
      .safeAreaPadding(.trailing, insets.trailing)
      // The Now Playing bar's safe-area inset doesn't reach this nested
      // ScrollView, so reserve room for it.
      .contentMargins(.bottom, tileHeight == nil ? 72 : 0, for: .scrollContent)
      .onFoldChange { fold = $0 }
      .onGeometryChange(for: CGFloat.self) {
        $0.size.width
      } action: {
        width = $0
      }
      .onChange(of: sounds) { _, newSounds in
        guard !isDragging else { return }
        // Skip when the order already matches: rebuilt tiles get a `.zero`
        // position, and `onGeometryChange` doesn't re-fire if nothing moved.
        guard items.map(\.id) != newSounds.map(\.id) else { return }
        // Carry over known positions so unmoved cells keep a valid drag origin.
        let knownPositions = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.position) })
        items = newSounds.map { SortableSound(sound: $0, position: knownPositions[$0.id] ?? .zero) }
      }
    }

    /// A drag moves one tile, so the net change is a single move: find the id
    /// whose removal makes both orders match.
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
  private nonisolated struct SortableSound: Identifiable, SortableGridProtocol {
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
