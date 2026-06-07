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

    /// Floor for a tile cell — icons never render smaller than this allows.
    private let tileWidth: CGFloat = 120
    /// Cap for icon growth in roomy windows (a few sounds in a wide window
    /// spread out rather than ballooning past this).
    private let maxTileWidth: CGFloat = 200
    private let spacing: CGFloat = 10

    init(sounds: [Sound], onMove: @escaping (IndexSet, Int) -> Void) {
      self.sounds = sounds
      self.onMove = onMove
      self._items = State(initialValue: sounds.map { SortableSoundMac(sound: $0) })
    }

    var body: some View {
      GeometryReader { geometry in
        // Columns that fit at the floor width, clamped to the item count so a
        // small preset spreads across the window instead of clustering left
        // (the grid's flexible columns share the full width). Tiles then grow
        // with their column — never below the floor, capped for sanity.
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
        // Announce the grid as one container ("Sounds, N items") so VoiceOver can
        // summarize it; .contain keeps each tile individually navigable.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Sounds"))
        // Clicking empty grid space drops keyboard focus (tiles' own taps win
        // hit-testing); the next Tab then walks from the first tile again.
        .contentShape(Rectangle())
        .onTapGesture {
          NSApp.keyWindow?.makeFirstResponder(nil)
        }
        // AppKit gives the first focusable view initial key focus on launch;
        // drop it so the first Tab starts the walk from the first tile.
        .onAppear {
          DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
          }
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
