//
//  ContentView.swift
//  Blankie
//
//  Created by Cody Bromley on 12/30/24.
//

import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
  struct ContentView: View {
    @Binding var showingAbout: Bool
    @Binding var showingShortcuts: Bool
    @Binding var showingNewPresetPopover: Bool
    @Binding var presetName: String

    @ObservedObject private var appState = AppState.shared
    @ObservedObject var audioManager = AudioManager.shared
    @ObservedObject var globalSettings = GlobalSettings.shared
    @StateObject private var presetManager = PresetManager.shared

    @State private var showingVolumePopover = false
    @State private var showingColorPicker = false
    @State private var showingPreferences = false
    @State private var isDragTargeted = false
    @StateObject private var dropzoneManager = DropzoneManager()

    // Use appState.hideInactiveSounds and visibility filtering
    private var filteredSounds: [Sound] {
      let visibleSounds = audioManager.getVisibleSounds()
      return visibleSounds.filter { sound in
        !appState.hideInactiveSounds || sound.isSelected
      }
    }

    var textColor: Color {
      audioManager.isGloballyPlaying ? .primary : .secondary
    }

    // Define constant sizes based on icon size preference
    private var itemWidth: CGFloat {
      switch globalSettings.iconSize {
      case .small:
        return 100
      case .medium:
        return 120
      case .large:
        return 150
      }
    }

    private var minimumSpacing: CGFloat {
      switch globalSettings.iconSize {
      case .small:
        return 8
      case .medium:
        return 10
      case .large:
        return 12
      }
    }

    private var hideShowButton: some View {
      Button(action: {
        withAnimation {
          appState.hideInactiveSounds.toggle()
          UserDefaults.standard.set(appState.hideInactiveSounds, forKey: "hideInactiveSounds")
        }
      }) {
        Image(systemName: appState.hideInactiveSounds ? "eye.slash" : "eye")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 20, height: 20)
          .foregroundColor(.primary)
      }
      .buttonStyle(.borderless)
      .help(appState.hideInactiveSounds ? "Show All Sounds" : "Hide Inactive Sounds")
    }

    var body: some View {
      ZStack {
        VStack(spacing: 0) {
          if !audioManager.isGloballyPlaying {
            HStack {
              Image(systemName: "pause.circle.fill")
              Text("Playback Paused", comment: "Playback paused banner")
                .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .foregroundStyle(.secondary)
          }
          // Main content
          GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: true) {
              LazyVGrid(
                columns: calculateColumns(for: geometry.size.width),
                spacing: minimumSpacing
              ) {
                ForEach(Array(filteredSounds.enumerated()), id: \.element.id) { index, sound in
                  DraggableSoundIcon(
                    sound: sound,
                    maxWidth: itemWidth,
                    dragIndex: index,
                    onDrop: { sourceIndex in
                      audioManager.moveVisibleSound(from: sourceIndex, to: index)
                    }
                  )
                }
              }
              .padding()
              .animation(.easeInOut, value: filteredSounds.count)
            }
            .frame(maxHeight: .infinity)
          }

          // App bar
          VStack(spacing: 0) {
            Rectangle()
              .frame(height: 1)
              .foregroundColor(Color.gray.opacity(0.2))

            HStack(spacing: 24) {
              // Timer button
              CompactTimerButton()

              // Volume button with popover
              Button(action: {
                showingVolumePopover.toggle()
              }) {
                Image(systemName: "speaker.wave.2.fill")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 20, height: 20)
                  .foregroundColor(.primary)
              }
              .buttonStyle(.borderless)
              .popover(isPresented: $showingVolumePopover) {
                VolumeControlsView(style: .popover)
              }

              // Play/Pause button
              Button(action: {
                audioManager.togglePlayback()
              }) {
                ZStack {
                  Circle()
                    .fill(
                      globalSettings.customAccentColor?.opacity(0.2)
                        ?? Color.accentColor.opacity(0.2)
                    )
                    .frame(width: 50, height: 50)

                  Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
                    .contentTransition(
                      .symbolEffect(
                        .replace.magic(fallback: .downUp.byLayer), options: .nonRepeating
                      )
                    )
                    .offset(x: audioManager.isGloballyPlaying ? 0 : 2)
                }
              }
              .buttonStyle(.borderless)

              // Color picker menu
              Button(action: {
                showingColorPicker.toggle()
              }) {
                Image(systemName: "paintpalette.fill")
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .frame(width: 20, height: 20)
                  .foregroundColor(.primary)
              }
              .buttonStyle(.borderless)
              .popover(isPresented: $showingColorPicker) {
                ColorPickerView()
                  .padding()
              }

              hideShowButton
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
          }
          .frame(maxWidth: .infinity)
          .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
          .background(.ultraThinMaterial)
        }
        .background(.ultraThickMaterial)
        .background(Color.black.opacity(0.25))
        .dropzone(
          manager: dropzoneManager,
          isDragTargeted: $isDragTargeted,
          globalSettings: globalSettings
        )
      } // End of ZStack
      .ignoresSafeArea(.container, edges: .horizontal)
      .animation(.easeInOut(duration: 0.2), value: audioManager.isGloballyPlaying)
      .sheet(isPresented: $showingShortcuts) {
        ShortcutsView()
          .background(.ultraThinMaterial)
          .presentationBackground(.ultraThinMaterial)
      }
      .sheet(isPresented: $showingAbout) {
        AboutView()
      }
      .sheet(
        isPresented: $dropzoneManager.showingSoundSheet,
        onDismiss: {
          dropzoneManager.hideSheet()
        }
      ) {
        SoundSheet(mode: .add, preselectedFile: dropzoneManager.selectedFileURL)
      }
      .onAppear {
        setupResetHandler()
        if !audioManager.isGloballyPlaying {
          NSApp.dockTile.badgeLabel = "⏸"
        } else {
          NSApp.dockTile.badgeLabel = nil
        }
      }
      .onChange(of: audioManager.isGloballyPlaying) {
        if !audioManager.isGloballyPlaying {
          NSApp.dockTile.badgeLabel = "⏸"
        } else {
          NSApp.dockTile.badgeLabel = nil
        }
      }
      .modifier(AudioErrorHandler())
    }

    private func calculateColumns(for availableWidth: CGFloat) -> [GridItem] {
      let numberOfColumns = max(2, Int(availableWidth / (itemWidth + minimumSpacing)))
      return Array(
        repeating: GridItem(.fixed(itemWidth), spacing: minimumSpacing), count: numberOfColumns
      )
    }

    private func setupResetHandler() {
      audioManager.onReset = { @MainActor in
        showingVolumePopover = false
      }
    }
  }

  struct DraggableSoundIcon: View {
    @ObservedObject var sound: Sound
    let maxWidth: CGFloat
    let dragIndex: Int
    let onDrop: (Int) -> Void

    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero

    var body: some View {
      SoundIcon(sound: sound, maxWidth: maxWidth)
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .offset(dragOffset)
        .opacity(isDragging ? 0.8 : 1.0)
        .contentShape(Rectangle())
        .onDrag {
          DispatchQueue.main.async {
            isDragging = true
          }
          return NSItemProvider(object: "\(dragIndex)" as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
          guard let provider = providers.first else { return false }

          provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let sourceIndexString = object as? String,
                  let sourceIndex = Int(sourceIndexString)
            else { return }

            DispatchQueue.main.async {
              if sourceIndex != dragIndex {
                onDrop(sourceIndex)
              }
              isDragging = false
              dragOffset = .zero
            }
          }
          return true
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
    }
  }

  struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
      Group {
        ContentView(
          showingAbout: .constant(false),
          showingShortcuts: .constant(false),
          showingNewPresetPopover: .constant(false),
          presetName: .constant("")
        )
        .frame(width: 600, height: 400)
      }
      .previewDisplayName("Blankie")
    }
  }
#endif
