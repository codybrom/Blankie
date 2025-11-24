//
//  HomeView.swift
//  Blankie
//
//  Main navigation view with tabs for Home, Presets, and Sounds
//

import SwiftUI

#if os(iOS) || os(visionOS)

  enum HomeTab: String, CaseIterable {
    case home
    case quickMix
    case settings

    var title: String {
      switch self {
      case .home: return "Home"
      case .quickMix: return "Quick Mix"
      case .settings: return "Settings"
      }
    }

    var icon: String {
      switch self {
      case .home: return "house.fill"
      case .quickMix: return "square.grid.2x2.fill"
      case .settings: return "gearshape.fill"
      }
    }
  }

  struct HomeView: View {
    @State private var selectedTab: HomeTab = .home
    @State private var expandPlayer = false
    @State private var showingMixer = false
    @State private var showingTimer = false
    @State private var presetToEdit: Preset?
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared

    var body: some View {
      tabView
    }

    // MARK: - Tab View

    private var shouldHideMiniPlayer: Bool {
      selectedTab == .quickMix || showingTimer || presetToEdit != nil || expandPlayer
    }

    private var tabView: some View {
      TabView(selection: $selectedTab) {
        // Home tab
        HomeOverviewView(
          expandPlayer: $expandPlayer,
          showingMixer: $showingMixer
        )
        .tabItem {
          Label(HomeTab.home.title, systemImage: HomeTab.home.icon)
        }
        .tag(HomeTab.home)

        // Quick Mix tab
        QuickMixView()
          .tabItem {
            Label(HomeTab.quickMix.title, systemImage: HomeTab.quickMix.icon)
          }
          .tag(HomeTab.quickMix)

        // Settings tab
        SettingsView()
          .tabItem {
            Label(HomeTab.settings.title, systemImage: HomeTab.settings.icon)
          }
          .tag(HomeTab.settings)
      }
      .tabBarMinimizeBehavior(.onScrollDown)
      .tabViewBottomAccessory {
        if !shouldHideMiniPlayer {
          NowPlayingAccessoryView(expandPlayer: $expandPlayer)
        }
      }
      .sheet(isPresented: $showingTimer) {
        TimerSheetView()
      }
      .sheet(item: $presetToEdit) { preset in
        EditPresetSheet(preset: preset, isPresented: $presetToEdit)
      }
      .sheet(isPresented: $expandPlayer) {
        NowPlayingSheet()
          .presentationDetents([.large])
          .presentationDragIndicator(.visible)
      }
      .fullScreenCover(isPresented: $showingMixer) {
        mixerView
      }
    }

    // MARK: - Shared Views

    private var mixerView: some View {
      ZStack(alignment: .topLeading) {
        AdaptiveContentView(showingAbout: .constant(false))

        // Back button to return to home
        Button {
          showingMixer = false
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
            Text("Home")
          }
          .font(.body)
          .foregroundColor(.primary)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
        }
        .padding()
        .padding(.top, 40)
      }
    }
  }

  // MARK: - Home Overview

  struct HomeOverviewView: View {
    @Binding var expandPlayer: Bool
    @Binding var showingMixer: Bool
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var navigationTrigger = 0

    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
              Text("Blankie")
                .font(.system(size: 32, weight: .bold))
            }
            .padding(.horizontal)
            .padding(.top, 16)

            // Library navigation
            List {
              NavigationLink(destination: PresetsLibraryView(expandPlayer: $expandPlayer, showingMixer: $showingMixer)) {
                HStack(spacing: 16) {
                  Image(systemName: "rectangle.stack.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)

                  Text("Presets")
                    .font(.body)
                    .foregroundColor(.primary)
                }
              }
              .listRowInsets(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 16))
              .listRowSeparator(.visible, edges: .bottom)
              .simultaneousGesture(TapGesture().onEnded { _ in
                navigationTrigger += 1
              })
              .sensoryFeedback(.selection, trigger: navigationTrigger)

              NavigationLink(destination: SoundsLibraryView(expandPlayer: $expandPlayer, showingMixer: $showingMixer)) {
                HStack(spacing: 16) {
                  Image(systemName: "waveform")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)

                  Text("Sounds")
                    .font(.body)
                    .foregroundColor(.primary)
                }
              }
              .listRowInsets(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 16))
              .listRowSeparator(.hidden, edges: .bottom)
              .simultaneousGesture(TapGesture().onEnded { _ in
                navigationTrigger += 1
              })
              .sensoryFeedback(.selection, trigger: navigationTrigger)
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(height: 100)

            // Recent presets grid
            if !recentPresets.isEmpty {
              VStack(alignment: .leading, spacing: 16) {
                Text("Recent Presets")
                  .font(.title2)
                  .fontWeight(.bold)
                  .padding(.horizontal)

                LazyVGrid(columns: [
                  GridItem(.flexible(), spacing: 16),
                  GridItem(.flexible(), spacing: 16),
                ], spacing: 16) {
                  ForEach(recentPresets) { preset in
                    PresetCard(preset: preset, expandPlayer: $expandPlayer)
                  }
                }
                .padding(.horizontal)
              }
            }

            // Recent solo sounds grid
            if !recentSoloSounds.isEmpty {
              VStack(alignment: .leading, spacing: 16) {
                Text("Recent Solo Sounds")
                  .font(.title2)
                  .fontWeight(.bold)
                  .padding(.horizontal)

                LazyVGrid(columns: [
                  GridItem(.flexible(), spacing: 16),
                  GridItem(.flexible(), spacing: 16),
                ], spacing: 16) {
                  ForEach(recentSoloSounds) { sound in
                    SoloSoundCard(sound: sound, expandPlayer: $expandPlayer)
                  }
                }
                .padding(.horizontal)
              }
            }
          }
          .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
      }
    }

    private var recentPresets: [Preset] {
      // Get recently used presets (would track usage in real implementation)
      presetManager.presets
        .filter { !$0.isDefault }
        .prefix(4)
        .map { $0 }
    }

    private var recentSoloSounds: [Sound] {
      // Get recently played solo sounds (would track usage in real implementation)
      audioManager.sounds
        .filter { !$0.isCustom }
        .prefix(4)
        .map { $0 }
    }
  }

  // MARK: - Solo Sound Card

  struct SoloSoundCard: View {
    @ObservedObject var sound: Sound
    @Binding var expandPlayer: Bool
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var playTrigger = 0

    private var isPlaying: Bool {
      audioManager.soloModeSound?.id == sound.id
    }

    var body: some View {
      Button {
        playTrigger += 1
        audioManager.enterSoloMode(for: sound)
        withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
          expandPlayer = true
        }
      } label: {
        VStack(spacing: 12) {
          // Icon with filled circle when playing
          ZStack {
            Circle()
              .fill(isPlaying ? (globalSettings.customAccentColor ?? .accentColor) : Color.secondary.opacity(0.15))

            Image(systemName: sound.systemIconName)
              .font(.system(size: 48))
              .foregroundColor(isPlaying ? .white : (globalSettings.customAccentColor ?? .accentColor))
          }
          .frame(width: 120, height: 120)

          // Title
          Text(sound.title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.center)
        }
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: playTrigger)
    }
  }

  // MARK: - Preset Card

  struct PresetCard: View {
    let preset: Preset
    @Binding var expandPlayer: Bool
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var audioManager = AudioManager.shared
    @StateObject private var globalSettings = GlobalSettings.shared
    @State private var artworkImage: UIImage?
    @State private var playTrigger = 0

    private var isCurrentPreset: Bool {
      presetManager.currentPreset?.id == preset.id && audioManager.soloModeSound == nil && !audioManager.isQuickMix
    }

    var body: some View {
      Button {
        playTrigger += 1
        Task {
          do {
            if audioManager.soloModeSound != nil {
              audioManager.exitSoloModeWithoutResuming()
            }
            if audioManager.isQuickMix {
              audioManager.exitQuickMix()
            }
            try presetManager.applyPreset(preset)
            // Expand player to show now playing
            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
              expandPlayer = true
            }
          } catch {
            print("Error applying preset: \(error)")
          }
        }
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          // Artwork with play overlay when current
          ZStack {
            Group {
              if let image = artworkImage {
                Image(uiImage: image)
                  .resizable()
                  .aspectRatio(contentMode: .fill)
              } else {
                Rectangle()
                  .fill(Color.secondary.opacity(0.2))
                  .overlay {
                    BrandedBlankieIcon(size: 60)
                  }
              }
            }
          }
          .aspectRatio(1, contentMode: .fill)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

          // Title
          Text(preset.displayName)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: playTrigger)
      .task {
        artworkImage = await PresetArtworkManager.shared.loadBackgroundImageAsync(for: preset)
      }
    }
  }

  #Preview {
    HomeView()
  }

#endif
