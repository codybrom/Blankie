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
        guard let videoURL = Bundle.main.url(forResource: asset.videoResourceName, withExtension: asset.videoExtension) else {
          throw AnimatedArtworkError.missingBundledAsset(asset.videoResourceName)
        }

        guard let previewURL = Bundle.main.url(forResource: asset.previewResourceName, withExtension: asset.previewExtension) else {
          throw AnimatedArtworkError.missingBundledAsset(asset.previewResourceName)
        }

        guard let squarePreviewURL = Bundle.main.url(forResource: asset.squarePreviewResourceName, withExtension: asset.squarePreviewExtension) else {
          throw AnimatedArtworkError.missingBundledAsset(asset.squarePreviewResourceName)
        }

        // Clean up old files
        if let oldLoop = artwork?.loopPath {
          AnimatedArtworkFileStore.removeItemIfExists(relativePath: oldLoop)
        }
        if let oldPreview = artwork?.previewPath, oldPreview != staticArtworkPath {
          AnimatedArtworkFileStore.removeItemIfExists(relativePath: oldPreview)
        }
        if let oldSquarePreview = artwork?.squarePreviewPath, oldSquarePreview != staticArtworkPath {
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

    var categories: [ArtworkCategory] {
      guard let url = Bundle.main.url(forResource: "AnimatedArtwork", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(AnimatedArtworkConfig.self, from: data)
      else {
        return []
      }
      return config.categories
    }

    var filteredAssets: [BundledAnimatedLoop] {
      let all = BundledAnimatedLoop.allCases
      guard let category = selectedCategory else { return all }
      return all.filter { $0.category == category }
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
        .fullScreenCover(item: $previewingAsset) { asset in
          FullScreenPreview(
            asset: asset,
            onSelect: {
              onSelect(asset)
            },
            onDismiss: {
              previewingAsset = nil
            }
          )
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

    var body: some View {
      Button(action: onTap) {
        ZStack(alignment: .bottomLeading) {
          if let previewURL = Bundle.main.url(forResource: asset.previewResourceName, withExtension: asset.previewExtension),
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

    @State private var player: AVPlayer?
    @State private var showInfo = false

    var body: some View {
      ZStack {
        Color.black.ignoresSafeArea()

        if let player = player {
          VideoPlayer(player: player)
            .ignoresSafeArea()
            .disabled(true)
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

                if !asset.credit.source.isEmpty {
                  Label(asset.credit.source, systemImage: "link")
                    .font(.caption)
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
            Text("Choose", comment: "Button to select animated artwork")
              .font(.headline)
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .padding()
              .background(Color.accentColor)
              .cornerRadius(12)
          }
          .padding(.horizontal, 32)
          .padding(.bottom, 32)
        }
      }
      .onAppear {
        setupPlayer()
      }
      .onDisappear {
        player?.pause()
        player = nil
      }
    }

    private func setupPlayer() {
      guard let videoURL = Bundle.main.url(forResource: asset.videoResourceName, withExtension: asset.videoExtension) else {
        return
      }

      let player = AVPlayer(url: videoURL)
      player.isMuted = true
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
    }
  }

  private enum AnimatedArtworkError: LocalizedError {
    case missingBundledAsset(String)

    var errorDescription: String? {
      switch self {
      case let .missingBundledAsset(name):
        return "Missing bundled asset: \(name)"
      }
    }
  }

  struct BundledAnimatedLoop: Identifiable, Codable {
    let id: String
    let displayName: String
    let description: String
    let category: String
    let videoFile: String
    let previewFile: String
    let squarePreviewFile: String
    let credit: ArtworkCredit

    struct ArtworkCredit: Codable {
      let artist: String
      let source: String
      let license: String
    }

    var videoResourceName: String {
      videoFile.replacingOccurrences(of: ".mov", with: "")
    }

    var videoExtension: String { "mov" }
    var previewResourceName: String {
      previewFile.replacingOccurrences(of: ".jpg", with: "")
    }

    var previewExtension: String { "jpg" }
    var squarePreviewResourceName: String {
      squarePreviewFile.replacingOccurrences(of: ".jpg", with: "")
    }

    var squarePreviewExtension: String { "jpg" }

    static var allCases: [BundledAnimatedLoop] {
      guard let url = Bundle.main.url(forResource: "AnimatedArtwork", withExtension: "json") else {
        print("⚠️ Failed to find AnimatedArtwork.json in bundle")
        return []
      }

      guard let data = try? Data(contentsOf: url) else {
        print("⚠️ Failed to read AnimatedArtwork.json from \(url)")
        return []
      }

      guard let config = try? JSONDecoder().decode(AnimatedArtworkConfig.self, from: data) else {
        print("⚠️ Failed to decode AnimatedArtwork.json")
        if let jsonString = String(data: data, encoding: .utf8) {
          print("JSON content preview: \(jsonString.prefix(200))")
        }
        return []
      }

      print("✅ Loaded \(config.artworks.count) artworks from AnimatedArtwork.json")
      return config.artworks
    }
  }

  struct AnimatedArtworkConfig: Codable {
    let artworks: [BundledAnimatedLoop]
    let categories: [ArtworkCategory]
  }

  struct ArtworkCategory: Codable {
    let id: String
    let displayName: String
    let icon: String
  }
#else
  struct AnimatedArtworkPicker: View {
    @Binding var artwork: AnimatedArtworkRef?
    @Binding var staticArtworkPath: String?
    let onChange: () -> Void

    var body: some View {
      Text("Animated artwork editing is available on iOS", comment: "Fallback text when feature unavailable")
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }
#endif
