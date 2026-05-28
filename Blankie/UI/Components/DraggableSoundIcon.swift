//
//  DraggableSoundIcon.swift
//  Blankie
//
//  Created by Cody Bromley on 1/2/25.
//

import SwiftUI

// Animation trigger struct for drag operations
private struct DragAnimationTrigger: Equatable {
  let draggedIndex: Int?
  let hoveredIndex: Int?
}

#if os(iOS) || os(visionOS)
  // Custom draggable sound icon that only applies drag gesture to the icon area
  struct DraggableSoundIcon: View {
    @ObservedObject var sound: Sound
    let maxWidth: CGFloat
    let index: Int
    @Binding var draggedIndex: Int?
    @Binding var hoveredIndex: Int?
    let onDragStart: () -> Void
    let onDrop: (Int) -> Void
    let onEditSound: (Sound) -> Void
    var onEnterEditMode: (() -> Void)?
    var isSoloMode: Bool = false
    var editMode: EditMode = .inactive
    @ObservedObject var globalSettings = GlobalSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State var jiggleAnimation = false
    @State private var longPressTrigger = 0
    @State private var dragStartTrigger = 0
    @State private var hoverTrigger = 0

    private var filteredSounds: [Sound] {
      AudioManager.shared.getVisibleSounds()
    }

    private var shouldShowProgressBorder: Bool {
      globalSettings.showProgressBorder && sound.isSelected && AudioManager.shared.isGloballyPlaying
        && editMode == .inactive
    }

    private var rotationDegrees: Double {
      editMode == .active && jiggleAnimation ? 2.5 : 0
    }

    private var jiggleAnimationValue: Animation? {
      editMode == .active && jiggleAnimation
        ? Animation.easeInOut(duration: 0.13).repeatForever(autoreverses: true) : nil
    }

    @ViewBuilder
    private var contextMenuContent: some View {
      if editMode == .inactive {
        // Title with credits
        Text(
          isCustomSound(sound)
            ? "\(sound.title) (Custom • Added By You)"
            : "\(sound.title) (Built-in\(getSoundAuthor(for: sound).map { " • By \($0)" } ?? ""))"
        )
        .font(.title2)
        .fontWeight(.bold)

        // Solo Mode - only show if not already in solo mode
        if AudioManager.shared.soloModeSound?.id != sound.id {
          Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
              AudioManager.shared.toggleSoloMode(for: sound)
            }
          }) {
            Label("Solo", systemImage: "headphones")
          }
          .sensoryFeedback(
            .selection, trigger: AudioManager.shared.soloModeSound?.id
          )
        }

        // Customize Sound
        Button(action: {
          onEditSound(sound)
        }) {
          Label("Customize", systemImage: "paintbrush")
        }

        Divider()

        // Reorder - only show when not already in edit mode
        if editMode == .inactive, let onEnterEditMode = onEnterEditMode {
          Button(action: {
            onEnterEditMode()
          }) {
            Label("Reorder", systemImage: "arrow.up.arrow.down")
          }
        }
      }
    }

    @ViewBuilder
    private var iconView: some View {
      ZStack {
        if isSoloMode {
          // Clear glass for solo mode - interactive without heavy blur
          Circle()
            .fill(.clear)
            .frame(width: iconSize, height: iconSize)
            .glassEffect(.clear.interactive(), in: .circle)
        } else {
          Circle()
            .fill(backgroundFill)
            .frame(width: iconSize, height: iconSize)
        }

        Image(systemName: sound.systemIconName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: iconSize * innerIconScale, height: iconSize * innerIconScale)
          .foregroundColor(iconColor)
      }
    }

    @ViewBuilder
    private var mainIconView: some View {
      ZStack {
        iconView

        // Progress border (inner border) - hide in edit mode
        if shouldShowProgressBorder {
          let borderSize = iconSize - borderWidth

          // Background track
          Circle()
            .stroke(Color.gray.opacity(0.3), lineWidth: borderWidth)
            .frame(width: borderSize, height: borderSize)

          // Progress indicator
          ProgressBorderView(
            iconSize: borderSize,
            borderWidth: borderWidth,
            sound: sound,
            color: accentColor
          )
        }

        // Dashed border in edit mode
        if editMode == .active {
          Circle()
            .stroke(
              Color.primary.opacity(0.3),
              style: StrokeStyle(lineWidth: 2, dash: [5, 5])
            )
            .frame(width: iconSize, height: iconSize)
        }
      }
      .frame(width: iconSize, height: iconSize)
      .contentShape(Circle())
      .scaleEffect(draggedIndex == index ? 0.85 : 1.0)
      .overlay(dropOverlay)
      .rotationEffect(.degrees(rotationDegrees))
      .animation(jiggleAnimationValue, value: jiggleAnimation)
    }

    var body: some View {
      VStack(spacing: globalSettings.iconSize == .small ? 2 : 6) {
        // Icon area with drag gesture
        mainIconView
          .onTapGesture {
            // Disable tap when in edit mode
            guard editMode == .inactive else { return }

            // Tapping the soloed sound toggles playback — it does NOT exit solo.
            // Solo is left by choosing another sound or preset.
            if AudioManager.shared.soloModeSound?.id == sound.id {
              AudioManager.shared.togglePlayback()
            } else {
              // If global playback is paused and this sound is already selected,
              // start global playback instead of deselecting the sound
              if !AudioManager.shared.isGloballyPlaying && sound.isSelected {
                AudioManager.shared.setGlobalPlaybackState(true)
              } else {
                // Normal behavior: toggle sound selection
                sound.toggle()
              }
            }
          }
          .sensoryFeedback(.selection, trigger: sound.isSelected) { _, _ in
            editMode == .inactive
          }
          .contextMenu {
            contextMenuContent
          }
          .onLongPressGesture(
            minimumDuration: 0.5, maximumDistance: .infinity,
            pressing: { pressing in
              // Only provide haptic feedback when not in edit mode
              if pressing, editMode == .inactive {
                longPressTrigger += 1
              }
            }, perform: {}
          )
          .onDrag {
            if editMode == .active {
              // Update state for drag start
              if draggedIndex != index {
                dragStartTrigger += 1
                onDragStart()
              }

              return NSItemProvider(object: "\(index)" as NSString)
            } else {
              return NSItemProvider()
            }
          } preview: {
            if editMode == .active {
              // Custom drag preview - just the icon without background
              iconView
                .opacity(0.8)
            } else {
              EmptyView()
            }
          }
          .onDrop(
            of: [.text],
            delegate: SoundDropDelegate(
              audioManager: AudioManager.shared,
              targetIndex: index,
              sounds: filteredSounds,
              draggedIndex: $draggedIndex,
              hoveredIndex: $hoveredIndex,
              cancelTimer: { draggedIndex = nil }
            )
          )
          .sensoryFeedback(.selection, trigger: longPressTrigger)
          .sensoryFeedback(.levelChange, trigger: dragStartTrigger)
          .sensoryFeedback(.alignment, trigger: hoverTrigger)
          .sensoryFeedback(.success, trigger: draggedIndex) { oldValue, newValue in
            // Trigger when drop completes
            oldValue != nil && newValue == nil
          }
          .onChange(of: hoveredIndex) { oldValue, newValue in
            // Trigger alignment feedback when this icon becomes the hover target
            if oldValue != index && newValue == index && draggedIndex != nil {
              hoverTrigger += 1
            }
          }

        // Title (not draggable) - hidden in solo mode since it's shown in navigation title
        if AudioManager.shared.soloModeSound == nil && globalSettings.showSoundNames {
          Text(LocalizedStringKey(sound.title))
            .font(
              globalSettings.iconSize == .small
                ? .caption2.weight(
                  Locale.current.scriptCategory == .standard ? .regular : .thin)
                : .callout.weight(Locale.current.scriptCategory == .standard ? .regular : .thin)
            )
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundColor(.primary)
            .frame(maxWidth: maxWidth - 20)
            .padding(.top, 2)
        }

        // Slider (not draggable) - hide in solo mode and edit mode
        if !isSoloMode && editMode == .inactive {
          VolumeSliderView(
            sound: sound,
            width: sliderWidth,
            tintColor: sliderTintColor,
            isEnabled: isSliderEnabled
          )
        }
      }
      .opacity(draggedIndex == index ? 0.5 : (editMode == .active ? 0.85 : 1.0))
      .padding(.vertical, globalSettings.iconSize == .small ? 2 : 4)
      .padding(.horizontal, 10)
      .frame(width: maxWidth)
      .zIndex(draggedIndex == index ? 1 : 0)
      .animation(
        .easeInOut(duration: 0.3),
        value: DragAnimationTrigger(
          draggedIndex: draggedIndex,
          hoveredIndex: hoveredIndex
        )
      )
      .onAppear { handleJiggle() }
      .onChange(of: editMode) { _, _ in handleJiggle() }
      .onDisappear { stopJiggle() }
    }

    @ViewBuilder
    private var dropOverlay: some View {
      if hoveredIndex == index && draggedIndex != index && editMode == .active {
        RoundedRectangle(cornerRadius: 50)
          .stroke(accentColor, lineWidth: 3)
          .background(
            RoundedRectangle(cornerRadius: 50)
              .fill(accentColor.opacity(0.2))
          )
          .allowsHitTesting(false)
      }
    }
  }
#endif
