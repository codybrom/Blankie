//
//  AdaptiveContentView+UIComponents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
    import TipKit

    // MARK: - UI Components Extension

    extension AdaptiveContentView {
        // MARK: - Navigation Elements

        var navigationTitle: String {
            if let soloSound = audioManager.soloModeSound {
                return soloSound.title
            }

            if audioManager.isQuickMix {
                return "Quick Mix"
            }

            if let preset = presetManager.currentPreset {
                return preset.isDefault ? "Blankie" : preset.name
            }

            return "Blankie"
        }

        // MARK: - Toolbar Components

        var bottomToolbar: some View {
            GlassEffectContainer(spacing: 8) {
                bottomToolbarContent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }

        @ViewBuilder
        var bottomToolbarContent: some View {
            VStack(spacing: 8) {
                // 3-Button Toolbar with connected glass tissue
                GlassEffectContainer(spacing: 20) {
                    HStack(spacing: 20) {
                        // Grid/List toggle OR Back button (solo/quick mix)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if audioManager.soloModeSound != nil {
                                    audioManager.exitSoloMode()
                                } else if audioManager.isQuickMix {
                                    audioManager.exitQuickMix()
                                } else {
                                    showingListView.toggle()
                                }
                            }
                        } label: {
                            Image(
                                systemName: audioManager.soloModeSound != nil || audioManager.isQuickMix
                                    ? "arrow.backward"
                                    : (showingListView ? "list.bullet" : "square.grid.3x3")
                            )
                            .font(.system(size: 22))
                            .foregroundColor(.primary)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 56, height: 56)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: .circle)
                        .sensoryFeedback(.selection, trigger: showingListView)

                        // Play/Pause button (larger, more prominent)
                        playPauseButton

                        // Appearance button
                        appearanceButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background {
                        Capsule(style: .continuous)
                            .fill(.clear)
                    }
                }
            }
        }

        var playPauseButton: some View {
            Button(action: {
                if audioManager.hasSelectedSounds {
                    playPauseTrigger += 1
                    audioManager.togglePlayback()
                }
            }) {
                Image(systemName: audioManager.isGloballyPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundColor(
                        audioManager.hasSelectedSounds
                            ? (globalSettings.customAccentColor ?? .accentColor)
                            : .secondary
                    )
                    .contentTransition(
                        .symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating)
                    )
                    .offset(x: audioManager.isGloballyPlaying ? 0 : 1)
                    .frame(width: 68, height: 68)
                    .contentShape(Circle())
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .disabled(!audioManager.hasSelectedSounds)
            .sensoryFeedback(.selection, trigger: playPauseTrigger)
        }

        var appearanceButton: some View {
            Button {
                showingViewSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22))
                    .foregroundColor(.primary)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: .circle)
            .sensoryFeedback(.selection, trigger: showingViewSettings)
        }
    }
#endif
