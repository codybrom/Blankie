//
//  AnimatedArtworkPicker.swift
//  Blankie
//
//  Created by Codex on 7/3/25.
//

import SwiftUI

#if os(iOS)
  import AVFoundation
  import AVKit
  import PhotosUI
  import UIKit

  struct AnimatedArtworkPicker: View {
    @Binding var artwork: AnimatedArtworkRef?
    @Binding var staticArtworkPath: String?
    let onChange: () -> Void

    @State private var showingGallery = false
    @State private var selectedBundledIdentifier: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    init(
      artwork: Binding<AnimatedArtworkRef?>,
      staticArtworkPath: Binding<String?>,
      onChange: @escaping () -> Void
    ) {
      _artwork = artwork
      _staticArtworkPath = staticArtworkPath
      self.onChange = onChange
      _selectedBundledIdentifier = State(initialValue: artwork.wrappedValue?.bundledIdentifier)
    }

    var body: some View {
      Button {
        showingGallery = true
      } label: {
        HStack {
          Text("Lock Screen Animation", comment: "Button to select animated artwork")
          Spacer()
          if let identifier = selectedBundledIdentifier,
            let asset = BundledAnimatedLoop.allCases.first(where: { $0.id == identifier })
          {
            Text(asset.displayName)
              .foregroundColor(.secondary)
          } else {
            Text("None", comment: "No animated artwork selected")
              .foregroundColor(.secondary)
          }
          Image(systemName: "chevron.right")
            .foregroundStyle(.tertiary)
            .imageScale(.small)
        }
      }
      .buttonStyle(.plain)
      .sheet(isPresented: $showingGallery) {
        AnimatedArtworkGallery(
          selectedIdentifier: $selectedBundledIdentifier,
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
        // Request the video file from ODR (downloads if needed)
        let videoURL = try await OnDemandResourceManager.shared.requestVideoResource(asset.id)

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

        // Copy new files
        let assetId = UUID()
        let loopRel = AnimatedArtworkFileStore.makeRelativeLoopPath(
          for: assetId, fileExtension: videoURL.pathExtension
        )
        let previewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId, fileExtension: previewURL.pathExtension
        )
        let squarePreviewRel = AnimatedArtworkFileStore.makeRelativePreviewPath(
          for: assetId, fileExtension: squarePreviewURL.pathExtension, suffix: "Square"
        )

        _ = try AnimatedArtworkFileStore.copyItem(at: videoURL, to: loopRel)
        _ = try AnimatedArtworkFileStore.copyItem(at: previewURL, to: previewRel)
        _ = try AnimatedArtworkFileStore.copyItem(at: squarePreviewURL, to: squarePreviewRel)

        await MainActor.run {
          artwork = AnimatedArtworkRef(
            source: .bundled,
            loopPath: loopRel,
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

  // MARK: - Gallery View

  private struct AnimatedArtworkGallery: View {
    @Binding var selectedIdentifier: String?
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

      debugLog("🎨 AnimatedArtworkGallery: Restoring audio controls after video preview")

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
        VStack(spacing: 0) {
          // Category filter
          if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                CategoryPill(
                  label: "All",
                  icon: "square.grid.2x2",
                  isSelected: selectedCategory == nil,
                  onTap: { selectedCategory = nil }
                )
                ForEach(categories, id: \.id) { category in
                  CategoryPill(
                    label: category.displayName,
                    icon: category.icon,
                    isSelected: selectedCategory == category.id,
                    onTap: { selectedCategory = category.id }
                  )
                }
              }
              .padding()
            }
            .background(Color(uiColor: .systemBackground))
          }

          ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
              ForEach(filteredAssets) { asset in
                GalleryCard(
                  asset: asset,
                  isSelected: selectedIdentifier == asset.id,
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
    let onTap: () -> Void

    var body: some View {
      Button(action: onTap) {
        Label(label, systemImage: icon)
          .font(.subheadline)
          .foregroundColor(isSelected ? .white : .primary)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemFill))
          .cornerRadius(20)
      }
    }
  }

  // MARK: - Gallery Card

  private struct GalleryCard: View {
    let asset: BundledAnimatedLoop
    let isSelected: Bool
    let onTap: () -> Void
    let onUncache: () -> Void

    @StateObject private var odrManager = OnDemandResourceManager.shared
    @State private var showingUncacheConfirmation = false

    var resourceState: ResourceState {
      // Return the actual ODR state - this accurately reflects whether
      // the video needs to be downloaded from Apple's servers
      return odrManager.getResourceState(asset.id)
    }

    var isCached: Bool {
      // Can only uncache if the resource is actually in ODR storage
      // (not just selected/copied to Documents)
      let actualODRState = odrManager.getResourceState(asset.id)
      if case .available = actualODRState {
        return true
      }
      return false
    }

    var body: some View {
      Button(action: onTap) {
        ZStack(alignment: .bottomLeading) {
          if let previewURL = Bundle.main.url(
            forResource: asset.previewResourceName, withExtension: asset.previewExtension),
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
                  .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
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
                  .foregroundColor(.accentColor)
                  .font(.title2)
                  .padding(8)
                  .background(Color.black.opacity(0.5))
                  .clipShape(Circle())
                  .padding(8)
              }
              Spacer()
            }
          }
        }
      }
      .buttonStyle(.plain)
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
          odrManager.releaseResource(asset.id)
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
    let onSelect: () -> Void
    let onDismiss: () -> Void
    let onDelete: () -> Void

    @State private var player: AVPlayer?
    @State private var showInfo = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showingDeleteConfirmation = false
    @State private var setupTask: Task<Void, Never>?
    @StateObject private var odrManager = OnDemandResourceManager.shared

    var resourceState: ResourceState {
      odrManager.getResourceState(asset.id)
    }

    var isCached: Bool {
      if case .available = resourceState {
        return true
      }
      return false
    }

    var body: some View {
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
              VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .font(.largeTitle)
                  .foregroundColor(.red)

                Text("Failed to load video")
                  .foregroundColor(.white)
                  .font(.headline)

                Text(error.localizedDescription)
                  .foregroundColor(.secondary)
                  .font(.caption)
                  .multilineTextAlignment(.center)
                  .padding(.horizontal, 32)
              }
            }
          }
        }

        VStack {
          HStack {
            Button {
              onDismiss()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.title)
                .foregroundColor(.white)
                .shadow(radius: 4)
            }
            .padding()

            Spacer()

            if isCached {
              Button {
                showingDeleteConfirmation = true
              } label: {
                Image(systemName: "trash.circle.fill")
                  .font(.title)
                  .foregroundColor(.white)
                  .shadow(radius: 4)
              }
              .padding()
            }

            Button {
              withAnimation {
                showInfo.toggle()
              }
            } label: {
              Image(systemName: "info.circle.fill")
                .font(.title)
                .foregroundColor(.white)
                .shadow(radius: 4)
            }
            .padding()
          }

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
                      .foregroundColor(.accentColor)
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
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }

          Button {
            onSelect()
          } label: {
            if case .downloading = resourceState {
              Text("Downloading...", comment: "Button label while video is downloading")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray)
                .cornerRadius(12)
            } else {
              Text("Choose", comment: "Button to select animated artwork")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isCached ? Color.accentColor : Color.gray)
                .cornerRadius(12)
            }
          }
          .disabled(!isCached)
          .padding(.horizontal, 32)
          .padding(.bottom, 32)
        }
      }
      .onAppear {
        setupPlayer()
      }
      .onDisappear {
        setupTask?.cancel()
        setupTask = nil
        player?.pause()
        player = nil
      }
      .alert("Remove Downloaded Video?", isPresented: $showingDeleteConfirmation) {
        Button("Remove Download", role: .destructive) {
          odrManager.releaseResource(asset.id)
          onDelete()
          onDismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This will free up space on your device. You can download it again later.")
      }
    }

    private func setupPlayer() {
      setupTask?.cancel()
      setupTask = Task {
        do {
          // Request the video file from ODR (downloads if needed)
          let videoURL = try await OnDemandResourceManager.shared.requestVideoResource(asset.id)
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
            NotificationCenter.default.addObserver(
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
          // Handle download failure - show error UI
          await MainActor.run {
            self.loadError = error.localizedDescription
            self.isLoading = false
          }
          debugLog("Failed to load video for preview: \(error)")
        }
      }
    }
  }

  private enum AnimatedArtworkError: LocalizedError {
    case missingBundledAsset(String)

    var errorDescription: String? {
      switch self {
      case .missingBundledAsset(let name):
        return "Missing bundled asset: \(name)"
      }
    }
  }

  struct BundledAnimatedLoop: Identifiable, Codable {
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

    // Files are copied flat to bundle root with unique names
    var videoResourceName: String { id }
    var videoExtension: String { "mov" }
    var previewResourceName: String { id }
    var previewExtension: String { "jpg" }
    var squarePreviewResourceName: String { "\(id)Square" }
    var squarePreviewExtension: String { "jpg" }

    static var allCases: [BundledAnimatedLoop] {
      // Files are copied flat to bundle root, not in AnimatedArtwork subfolder
      guard let resourceURL = Bundle.main.resourceURL else {
        debugLog("⚠️ Failed to find bundle resource directory")
        return []
      }

      guard
        let contents = try? FileManager.default.contentsOfDirectory(
          at: resourceURL,
          includingPropertiesForKeys: [.isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
      else {
        debugLog("⚠️ Failed to read bundle resource contents")
        return []
      }

      var artworks: [BundledAnimatedLoop] = []

      // Find all *Metadata.json files
      let metadataFiles = contents.filter { $0.lastPathComponent.hasSuffix("Metadata.json") }

      for metadataURL in metadataFiles {
        guard let data = try? Data(contentsOf: metadataURL),
          let artwork = try? JSONDecoder().decode(BundledAnimatedLoop.self, from: data)
        else {
          debugLog("⚠️ Failed to load metadata from \(metadataURL.lastPathComponent)")
          continue
        }

        artworks.append(artwork)
      }

      debugLog("✅ Loaded \(artworks.count) artworks from bundle resources")
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
        debugLog("⚠️ Failed to load categories.json")
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
        "Animated artwork editing is available on iOS",
        comment: "Fallback text when feature unavailable"
      )
      .font(.subheadline)
      .foregroundColor(.secondary)
    }
  }
#endif
