//
//  AnimatedArtworkPicker.swift
//  Blankie
//
//  Created by Cody Bromley on 7/3/25.
//

import SwiftUI
import os

#if os(iOS)
  import AVFoundation
  import AVKit
  import PhotosUI
  import UIKit

  struct AnimatedArtworkPicker: View {
    /// How the picker renders its entrance: an inline form row (Settings'
    /// "Default Animation") or a preview tile (the preset editor's Lock Screen
    /// tile). Both open the same gallery.
    enum Presentation {
      case row
      case tile
    }

    @Binding var artwork: AnimatedArtworkRef?
    @Binding var staticArtworkPath: String?
    /// Row label. Defaults to the per-preset wording; the app-wide default in
    /// Settings passes "Default Animation" instead. Unused by the tile style.
    let label: LocalizedStringKey
    let presentation: Presentation
    /// Accent used by the gallery (pills, selection, Choose button). Passed in
    /// by the call site so Settings uses the app-wide accent and Edit Preset
    /// uses the edited preset's accent — never the unrelated playing preset's.
    let accent: Color
    let onChange: () -> Void

    @State private var showingGallery = false
    @State private var selectedBundledIdentifier: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    init(
      artwork: Binding<AnimatedArtworkRef?>,
      staticArtworkPath: Binding<String?>,
      label: LocalizedStringKey = "Lock Screen Animation",
      presentation: Presentation = .row,
      accent: Color = GlobalSettings.shared.customAccentColor ?? .accentColor,
      onChange: @escaping () -> Void
    ) {
      _artwork = artwork
      _staticArtworkPath = staticArtworkPath
      self.label = label
      self.presentation = presentation
      self.accent = accent
      self.onChange = onChange
      _selectedBundledIdentifier = State(initialValue: artwork.wrappedValue?.bundledIdentifier)
    }

    var body: some View {
      content
        .sheet(isPresented: $showingGallery) {
          AnimatedArtworkGallery(
            selectedIdentifier: $selectedBundledIdentifier,
            accent: accent,
            onSelect: { asset in
              Task {
                await applyBundledAsset(asset)
                showingGallery = false
              }
            },
            onClear: {
              removeAnimatedArtwork()
              showingGallery = false
            }
          )
        }
        .onAppear {
          selectedBundledIdentifier = artwork?.bundledIdentifier
        }
        .onChange(of: artwork?.bundledIdentifier) { _, newValue in
          selectedBundledIdentifier = newValue
        }
    }

    @ViewBuilder
    private var content: some View {
      switch presentation {
      case .row:
        rowLabel
      case .tile:
        tileLabel
      }
    }

    private var rowLabel: some View {
      Button {
        showingGallery = true
      } label: {
        HStack {
          Text(label)
          Spacer()
          if let asset = selectedAsset {
            Text(asset.displayName)
              .foregroundColor(.secondary)
          } else {
            Text("None")
              .foregroundColor(.secondary)
          }
          Image(systemName: "chevron.right")
            .foregroundStyle(.tertiary)
            .imageScale(.small)
            .accessibilityHidden(true)
        }
      }
      .buttonStyle(.plain)
    }

    private var tileLabel: some View {
      ArtworkTile(
        caption: "Lock Screen",
        valueLabel: selectedAsset.map { "\($0.displayName)" } ?? "None",
        isSet: selectedAsset != nil,
        placeholderIcon: "moon.stars",
        placeholderLabel: "Browse",
        accent: accent,
        onTap: { showingGallery = true },
        onRemove: selectedBundledIdentifier == nil ? nil : { removeAnimatedArtwork() },
        thumbnail: {
          LockScreenTileThumbnail(asset: selectedAsset)
        }
      )
    }

    /// The currently selected bundled loop, if any.
    private var selectedAsset: BundledAnimatedLoop? {
      guard let identifier = selectedBundledIdentifier else { return nil }
      return BundledAnimatedLoop.allCases.first { $0.id == identifier }
    }

    @MainActor
    private func removeAnimatedArtwork() {
      guard !isProcessing else { return }
      // Only remove animated artwork files, keep staticArtworkPath unchanged
      if let loopPath = artwork?.loopPath {
        AnimatedArtworkFileStore.removeItemIfExists(relativePath: loopPath)
      }
      if let previewPath = artwork?.previewPath, previewPath != staticArtworkPath {
        AnimatedArtworkFileStore.removeItemIfExists(relativePath: previewPath)
      }
      artwork = nil
      selectedBundledIdentifier = nil
      onChange()
    }

    private func applyBundledAsset(_ asset: BundledAnimatedLoop) async {
      guard !isProcessing else { return }
      isProcessing = true
      defer { isProcessing = false }

      do {
        // Ensure the video's Background Assets pack is downloaded.
        _ = try await BackgroundResourceManager.shared.resourceURL(for: asset.preferredPackID)

        // Preview images remain bundled for fast gallery display
        guard
          let previewURL = Bundle.main.url(
            forResource: asset.previewResourceName, withExtension: asset.previewExtension)
        else {
          throw AnimatedArtworkError.missingBundledAsset("\(asset.id)/preview")
        }

        guard
          let squarePreviewURL = Bundle.main.url(
            forResource: asset.squarePreviewResourceName,
            withExtension: asset.squarePreviewExtension
          )
        else {
          throw AnimatedArtworkError.missingBundledAsset("\(asset.id)/preview-square")
        }

        // Clean up old files
        if let oldLoop = artwork?.loopPath {
          AnimatedArtworkFileStore.removeItemIfExists(relativePath: oldLoop)
        }
        if let oldPreview = artwork?.previewPath, oldPreview != staticArtworkPath {
          AnimatedArtworkFileStore.removeItemIfExists(relativePath: oldPreview)
        }
        if let oldSquarePreview = artwork?.squarePreviewPath, oldSquarePreview != staticArtworkPath
        {
          AnimatedArtworkFileStore.removeItemIfExists(relativePath: oldSquarePreview)
        }

        // Copy only the small preview images into Documents (used as the static
        // artwork fallback). The video stays in its Background Assets pack.
        let assetId = UUID()
        let previewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId, fileExtension: previewURL.pathExtension
        )
        let squarePreviewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId, fileExtension: squarePreviewURL.pathExtension, suffix: "Square"
        )

        _ = try AnimatedArtworkFileStore.copyItem(at: previewURL, to: previewRel)
        _ = try AnimatedArtworkFileStore.copyItem(at: squarePreviewURL, to: squarePreviewRel)

        await MainActor.run {
          artwork = AnimatedArtworkRef(
            source: .bundled,
            loopPath: nil,
            previewPath: previewRel,
            squarePreviewPath: squarePreviewRel,
            preferredAspect: "3x4",
            bundledIdentifier: asset.id
          )
          selectedBundledIdentifier = asset.id
          onChange()
        }
      } catch {
        await MainActor.run {
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  // MARK: - Lock Screen Tile Thumbnail

  /// The Lock Screen tile's fill: the selected loop's still square preview,
  /// with the muted looping video layered on top once it is confirmed on the
  /// device. It never triggers a download for a thumbnail — a selected asset is
  /// already downloaded, so this animates in practice; if the download was
  /// evicted it stays a still until the user re-picks it.
  private struct LockScreenTileThumbnail: View {
    let asset: BundledAnimatedLoop?

    @StateObject private var resourceManager = BackgroundResourceManager.shared
    @State private var videoURL: URL?

    var body: some View {
      ZStack {
        stillPreview
        if let videoURL {
          LoopingPlayerView(url: videoURL)
        }
      }
      .task(id: asset?.id) {
        await loadVideoIfAvailable()
      }
    }

    @ViewBuilder private var stillPreview: some View {
      if let asset,
        let url = Bundle.main.url(
          forResource: asset.squarePreviewResourceName,
          withExtension: asset.squarePreviewExtension),
        let uiImage = UIImage(contentsOfFile: url.path)
      {
        Image(uiImage: uiImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        Color.secondary.opacity(0.12)
      }
    }

    private func loadVideoIfAvailable() async {
      videoURL = nil
      guard let asset else { return }
      // Play only what is already on the device; don't fetch a pack for a tile.
      guard case .available = resourceManager.state(for: asset.preferredPackID) else { return }
      videoURL = try? await BackgroundResourceManager.shared.resourceURL(for: asset.preferredPackID)
    }
  }

  // MARK: - Looping Player View

  /// A muted, seamlessly-looping, aspect-fill video layer for tile-sized
  /// previews. Uses `AVPlayerLooper` for gapless loops and the `.pauses`
  /// background policy so it never claims the Now Playing controls.
  private struct LoopingPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerContainerView {
      let view = LoopingPlayerContainerView()
      view.configure(url: url)
      return view
    }

    func updateUIView(_ uiView: LoopingPlayerContainerView, context: Context) {
      uiView.configure(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerContainerView, coordinator: Coordinator) {
      uiView.teardown()
    }
  }

  private final class LoopingPlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    func configure(url: URL) {
      guard url != currentURL else { return }
      currentURL = url
      teardown()

      let item = AVPlayerItem(url: url)
      let queue = AVQueuePlayer()
      queue.isMuted = true
      // Keep this preview from taking over background audio / Now Playing.
      queue.audiovisualBackgroundPlaybackPolicy = .pauses
      queue.preventsDisplaySleepDuringVideoPlayback = false

      looper = AVPlayerLooper(player: queue, templateItem: item)
      playerLayer.player = queue
      playerLayer.videoGravity = .resizeAspectFill
      player = queue
      queue.play()
    }

    func teardown() {
      player?.pause()
      looper?.disableLooping()
      looper = nil
      player = nil
      playerLayer.player = nil
    }

    deinit {
      teardown()
    }
  }

  // MARK: - Gallery View

  private struct AnimatedArtworkGallery: View {
    @Binding var selectedIdentifier: String?
    let accent: Color
    let onSelect: (BundledAnimatedLoop) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var previewingAsset: BundledAnimatedLoop?
    @State private var selectedCategory: String?

    private func handleUncache(asset: BundledAnimatedLoop) {
      // If uncaching the currently selected video, unselect it
      if selectedIdentifier == asset.id {
        onClear()
      }
    }

    private func restoreAudioControlsAfterVideoPreview() {
      // CRITICAL: After video preview, iOS may have disconnected remote command handlers
      // even though we configured the preview player with .pauses policy.
      // We must re-establish media controls to ensure play/pause/next/previous work.
      let audioManager = AudioManager.shared

      Logger.ui.debug("AnimatedArtworkGallery: Restoring audio controls after video preview")

      Task { @MainActor in
        // Re-register remote command handlers (play, pause, next, previous)
        audioManager.setupMediaControls()

        // Refresh Now Playing info to ensure it's current
        let currentPreset = PresetManager.shared.currentPreset
        audioManager.nowPlayingManager.updateInfo(
          preset: currentPreset,
          presetName: currentPreset?.name,
          creatorName: currentPreset?.creatorName,
          artworkId: currentPreset?.artworkId,
          isPlaying: audioManager.isGloballyPlaying
        )
      }
    }

    var categories: [ArtworkCategory] {
      return ArtworkCategory.allCategories
    }

    var filteredAssets: [BundledAnimatedLoop] {
      let all = BundledAnimatedLoop.allCases
      let filtered = selectedCategory == nil ? all : all.filter { $0.category == selectedCategory }

      // Sort so selected item is always first
      guard let selectedId = selectedIdentifier else { return filtered }
      return filtered.sorted { asset1, asset2 in
        let isAsset1Selected = asset1.id == selectedId
        let isAsset2Selected = asset2.id == selectedId

        if isAsset1Selected { return true }
        if isAsset2Selected { return false }

        // Maintain original order for non-selected items
        return false
      }
    }

    var body: some View {
      NavigationStack {
        ScrollView {
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            ForEach(filteredAssets) { asset in
              GalleryCard(
                asset: asset,
                isSelected: selectedIdentifier == asset.id,
                accent: accent,
                onTap: {
                  previewingAsset = asset
                },
                onUncache: {
                  handleUncache(asset: asset)
                }
              )
            }
          }
          .padding()
        }
        .safeAreaBar(edge: .top, spacing: 0) {
          // Category filter floats over the scrolling grid with the system scroll edge effect
          if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                CategoryPill(
                  label: "All",
                  icon: "square.grid.2x2",
                  isSelected: selectedCategory == nil,
                  accent: accent,
                  onTap: { selectedCategory = nil }
                )
                ForEach(categories, id: \.id) { category in
                  CategoryPill(
                    label: category.displayName,
                    icon: category.icon,
                    isSelected: selectedCategory == category.id,
                    accent: accent,
                    onTap: { selectedCategory = category.id }
                  )
                }
              }
              .padding()
            }
          }
        }
        .navigationTitle("Lock Screen Animation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              dismiss()
            }
          }
          ToolbarItem(placement: .primaryAction) {
            if selectedIdentifier != nil {
              Button("Clear") {
                onClear()
              }
            }
          }
        }
        .sheet(item: $previewingAsset) { asset in
          FullScreenPreview(
            asset: asset,
            accent: accent,
            onSelect: {
              onSelect(asset)
            },
            onDismiss: {
              previewingAsset = nil
              // Re-establish audio session and media controls after video preview
              restoreAudioControlsAfterVideoPreview()
            },
            onDelete: {
              handleUncache(asset: asset)
            }
          )
          .presentationDragIndicator(.visible)
        }
      }
    }
  }

  // MARK: - Category Pill

  private struct CategoryPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
      let pill = Button(action: onTap) {
        Label(label, systemImage: icon)
          .font(.subheadline)
      }
      if isSelected {
        // Prominent glass fills with the accent and picks a legible label automatically.
        pill.buttonStyle(.glassProminent).tint(accent)
      } else {
        pill.buttonStyle(.glass)
      }
    }
  }

  // MARK: - Gallery Card

  private struct GalleryCard: View {
    let asset: BundledAnimatedLoop
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void
    let onUncache: () -> Void

    @StateObject private var resourceManager = BackgroundResourceManager.shared
    @State private var showingUncacheConfirmation = false

    var resourceState: BackgroundResourceState {
      // Reflects whether the video's asset pack is on the device.
      return resourceManager.state(for: asset.preferredPackID)
    }

    var isCached: Bool {
      // Can only remove if the asset pack is actually downloaded.
      if case .available = resourceState {
        return true
      }
      return false
    }

    var body: some View {
      Button(action: onTap) {
        ZStack(alignment: .bottomLeading) {
          if let previewURL = Bundle.main.url(
            forResource: asset.preferredPreviewResourceName, withExtension: asset.previewExtension),
            let uiImage = UIImage(contentsOfFile: previewURL.path)
          {
            Image(uiImage: uiImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(height: 220)
              .clipped()
              .cornerRadius(12)
              .overlay(
                RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(isSelected ? accent : Color.clear, lineWidth: 3)
              )
          }

          // Download state indicator overlay (top left)
          VStack {
            HStack {
              downloadStateIndicator
                .padding(8)
              Spacer()
            }
            Spacer()
          }

          // Credit overlay at bottom
          VStack(alignment: .leading, spacing: 2) {
            Text(asset.displayName)
              .font(.caption)
              .fontWeight(.medium)
            if !asset.credit.artist.isEmpty {
              Text(asset.credit.artist)
                .font(.caption2)
                .foregroundColor(.secondary)
            }
          }
          .foregroundColor(.white)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            LinearGradient(
              colors: [.black.opacity(0.6), .clear],
              startPoint: .bottom,
              endPoint: .top
            )
          )
          .cornerRadius(12, corners: [.bottomLeft, .bottomRight])

          // Checkmark overlay at top right
          if isSelected {
            VStack {
              HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(accent)
                  .font(.title2)
                  .padding(8)
                  .background(Color.black.opacity(0.5))
                  .clipShape(Circle())
                  .padding(8)
              }
              Spacer()
            }
            .accessibilityHidden(true)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(asset.displayName))
      .accessibilityAddTraits(isSelected ? [.isSelected] : [])
      .contextMenu {
        if isCached {
          Button(role: .destructive) {
            showingUncacheConfirmation = true
          } label: {
            Label("Remove Download", systemImage: "trash")
          }
        }
      }
      .alert("Remove Downloaded Video?", isPresented: $showingUncacheConfirmation) {
        Button("Remove Download", role: .destructive) {
          Task { await resourceManager.removeResource(asset.preferredPackID) }
          onUncache()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        if isSelected {
          Text(
            "This video is currently selected for your lock screen. Removing it will also unselect it. You can download it again later."
          )
        } else {
          Text("This will free up space on your device. You can download it again later.")
        }
      }
    }

    @ViewBuilder
    private var downloadStateIndicator: some View {
      switch resourceState {
      case .notDownloaded:
        Image(systemName: "icloud.and.arrow.down")
          .font(.caption)
          .foregroundColor(.white)
          .padding(6)
          .background(Color.blue.opacity(0.8))
          .clipShape(Circle())
          .shadow(radius: 2)

      case .downloading(let progress):
        ZStack {
          Circle()
            .stroke(Color.white.opacity(0.3), lineWidth: 2)
            .frame(width: 24, height: 24)

          Circle()
            .trim(from: 0, to: progress)
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(-90))

          Text("\(Int(progress * 100))")
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.white)
        }
        .padding(6)
        .background(Color.blue.opacity(0.8))
        .clipShape(Circle())
        .shadow(radius: 2)

      case .available:
        EmptyView()

      case .failed:
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundColor(.white)
          .padding(6)
          .background(Color.red.opacity(0.8))
          .clipShape(Circle())
          .shadow(radius: 2)
      }
    }
  }

  // Helper for corner radius on specific corners
  extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
      clipShape(RoundedCorner(radius: radius, corners: corners))
    }
  }

  struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
      let path = UIBezierPath(
        roundedRect: rect,
        byRoundingCorners: corners,
        cornerRadii: CGSize(width: radius, height: radius)
      )
      return Path(path.cgPath)
    }
  }

  // MARK: - Full Screen Preview

  private struct FullScreenPreview: View {
    let asset: BundledAnimatedLoop
    let accent: Color
    let onSelect: () -> Void
    let onDismiss: () -> Void
    let onDelete: () -> Void

    @State private var player: AVPlayer?
    @State private var showInfo = false
    @State private var isLoading = true
    @State private var showingDeleteConfirmation = false
    @State private var setupTask: Task<Void, Never>?
    @State private var loopObserver: NSObjectProtocol?
    @StateObject private var resourceManager = BackgroundResourceManager.shared

    var resourceState: BackgroundResourceState {
      resourceManager.state(for: asset.preferredPackID)
    }

    var isCached: Bool {
      if case .available = resourceState {
        return true
      }
      return false
    }

    private var accentColor: Color { accent }

    var body: some View {
      NavigationStack {
        ZStack {
          Color.black.ignoresSafeArea()

          if let player = player {
            VideoPlayer(player: player)
              .ignoresSafeArea()
              .disabled(true)
          }

          // Loading indicator while downloading/loading
          if isLoading {
            VStack(spacing: 16) {
              switch resourceState {
              case .notDownloaded:
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                  .scaleEffect(1.5)

                Text("Preparing download...")
                  .foregroundColor(.white)
                  .font(.subheadline)

              case .downloading(let progress):
                ZStack {
                  Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 4)
                    .frame(width: 80, height: 80)

                  Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: progress)

                  Text(Double(progress).formatted(.percent.precision(.fractionLength(0))))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                }

                Text("Downloading video...")
                  .foregroundColor(.white)
                  .font(.subheadline)

              case .available:
                // Video is available but player not ready yet
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .white))
                  .scaleEffect(1.5)

                Text("Loading video...")
                  .foregroundColor(.white)
                  .font(.subheadline)

              case .failed(let error):
                let isOffline = (error as? BackgroundResourceError)?.isOffline ?? false
                VStack(spacing: 12) {
                  Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(isOffline ? .white : .red)

                  Text(error.localizedDescription)
                    .foregroundColor(.white)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }
              }
            }
          }

          VStack {
            Spacer()

            // Info overlay
            if showInfo {
              VStack(alignment: .leading, spacing: 8) {
                Text(asset.displayName)
                  .font(.title2)
                  .fontWeight(.semibold)

                Text(asset.description)
                  .font(.subheadline)
                  .foregroundColor(.secondary)

                if !asset.credit.artist.isEmpty || !asset.credit.source.isEmpty {
                  Divider()
                    .padding(.vertical, 4)

                  if !asset.credit.artist.isEmpty {
                    Label(asset.credit.artist, systemImage: "person.fill")
                      .font(.caption)
                  }

                  if !asset.credit.source.isEmpty, let url = URL(string: asset.credit.source) {
                    Link(destination: url) {
                      Label(asset.credit.source, systemImage: "link")
                        .font(.caption)
                        .foregroundColor(accentColor)
                    }
                  }

                  if !asset.credit.license.isEmpty {
                    Text(asset.credit.license)
                      .font(.caption2)
                      .foregroundColor(.secondary)
                  }
                }
              }
              .padding()
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.thickMaterial)
              .cornerRadius(16)
              .padding(.horizontal, 32)
              .padding(.bottom, 16)
              .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Button {
              onSelect()
            } label: {
              Group {
                if case .downloading = resourceState {
                  Text("Downloading...")
                } else {
                  Text("Choose")
                }
              }
              .font(.headline)
              .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(accentColor)
            .disabled(!isCached)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
          }
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) {
              onDismiss()
            }
          }
          if isCached {
            ToolbarItem(placement: .topBarTrailing) {
              Button(role: .destructive) {
                showingDeleteConfirmation = true
              } label: {
                Label("Remove Download", systemImage: "trash")
              }
            }
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button {
              withAnimation {
                showInfo.toggle()
              }
            } label: {
              Label("Information", systemImage: "info.circle")
            }
          }
        }
        .onAppear {
          setupPlayer()
        }
        .onDisappear {
          setupTask?.cancel()
          setupTask = nil
          if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
          }
          loopObserver = nil
          player?.pause()
          player = nil
        }
        .alert("Remove Downloaded Video?", isPresented: $showingDeleteConfirmation) {
          Button("Remove Download", role: .destructive) {
            Task { await resourceManager.removeResource(asset.preferredPackID) }
            onDelete()
            onDismiss()
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("This will free up space on your device. You can download it again later.")
        }
      }
    }

    private func setupPlayer() {
      setupTask?.cancel()
      setupTask = Task {
        do {
          // Ensure the video's Background Assets pack is downloaded, then play it.
          let videoURL = try await BackgroundResourceManager.shared.resourceURL(
            for: asset.preferredPackID)
          // If the sheet dismissed during the download, stop here.
          if Task.isCancelled { return }

          await MainActor.run {
            let player = AVPlayer(url: videoURL)
            player.isMuted = true

            // CRITICAL: Prevent this preview player from taking over Now Playing controls
            // This ensures background audio playback controls remain active
            player.audiovisualBackgroundPlaybackPolicy = .pauses
            player.preventsDisplaySleepDuringVideoPlayback = false

            self.player = player

            // Loop the video
            self.loopObserver = NotificationCenter.default.addObserver(
              forName: .AVPlayerItemDidPlayToEndTime,
              object: player.currentItem,
              queue: .main
            ) { _ in
              player.seek(to: .zero)
              player.play()
            }

            player.play()

            // Hide loading indicator once player is ready
            self.isLoading = false
          }
        } catch is CancellationError {
          // Sheet dismissed before download finished; nothing to do.
        } catch {
          // Keep `isLoading` true so the overlay's `.failed` branch (driven by
          // resourceState) stays on screen. Setting it false here collapsed the
          // view to a black background instead of showing the error.
          Logger.ui.error("Failed to load video for preview: \(error, privacy: .public)")
        }
      }
    }
  }

  private enum AnimatedArtworkError: LocalizedError {
    case missingBundledAsset(String)

    var errorDescription: String? {
      switch self {
      case .missingBundledAsset(let name):
        return String(localized: "Missing bundled asset: \(name)")
      }
    }
  }

  nonisolated struct BundledAnimatedLoop: Identifiable, Codable {
    let id: String
    let displayName: String
    let description: String
    let category: String
    let credit: ArtworkCredit

    struct ArtworkCredit: Codable {
      let artist: String
      let source: String
      let license: String
    }

    // Preview images + metadata are bundled and resolved by name; the video is
    // delivered separately as a Background Assets pack (id == asset-pack id).
    var previewResourceName: String { id }
    var previewExtension: String { "jpg" }
    var squarePreviewResourceName: String { "\(id)Square" }
    var squarePreviewExtension: String { "jpg" }

    /// Asset-pack id for this device's variant (square on iPad, portrait on
    /// iPhone), matching what the lock screen serves. The gallery downloads,
    /// plays, and removes this pack so a device only ever fetches one variant.
    var preferredPackID: String {
      BackgroundResourceManager.preferredPackID(for: id)
    }
    /// Bundled preview image name for this device's variant.
    var preferredPreviewResourceName: String {
      AnimatedArtworkKey.preferredForDevice == .square
        ? squarePreviewResourceName : previewResourceName
    }

    static var allCases: [BundledAnimatedLoop] {
      // Files are copied flat to bundle root, not in AnimatedArtwork subfolder
      guard let resourceURL = Bundle.main.resourceURL else {
        Logger.ui.error("Failed to find bundle resource directory")
        return []
      }

      guard
        let contents = try? FileManager.default.contentsOfDirectory(
          at: resourceURL,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      else {
        Logger.ui.error("Failed to read bundle resource contents")
        return []
      }

      var artworks: [BundledAnimatedLoop] = []

      // Find all *Metadata.json files
      let metadataFiles = contents.filter { $0.lastPathComponent.hasSuffix("Metadata.json") }

      for metadataURL in metadataFiles {
        guard let data = try? Data(contentsOf: metadataURL),
          let artwork = try? JSONDecoder().decode(BundledAnimatedLoop.self, from: data)
        else {
          Logger.ui.error(
            "Failed to load metadata from \(metadataURL.lastPathComponent, privacy: .public)")
          continue
        }

        artworks.append(artwork)
      }

      Logger.ui.debug("Loaded \(artworks.count) artworks from bundle resources")
      return artworks.sorted { $0.id < $1.id }  // Sort alphabetically by ID
    }
  }

  struct ArtworkCategory: Codable {
    let id: String
    let displayName: String
    let icon: String

    static var allCategories: [ArtworkCategory] {
      // Files are copied flat to bundle root, not in AnimatedArtwork subfolder
      guard
        let categoriesURL = Bundle.main.url(
          forResource: "categories",
          withExtension: "json"
        ),
        let data = try? Data(contentsOf: categoriesURL),
        let config = try? JSONDecoder().decode(CategoriesConfig.self, from: data)
      else {
        Logger.ui.error("Failed to load categories.json")
        return []
      }
      return config.categories
    }
  }

  private struct CategoriesConfig: Codable {
    let categories: [ArtworkCategory]
  }
#else
  struct AnimatedArtworkPicker: View {
    @Binding var artwork: AnimatedArtworkRef?
    @Binding var staticArtworkPath: String?
    let onChange: () -> Void

    var body: some View {
      Text(
        "Animated artwork editing is available on iOS"
      )
      .font(.subheadline)
      .foregroundColor(.secondary)
    }
  }
#endif
