//
//  MixerView+UIComponents.swift
//  Blankie
//
//  Created by Cody Bromley on 6/8/25.
//

import SwiftUI

#if os(iOS) || os(visionOS)
    import TipKit

    // MARK: - UI Components Extension

    extension MixerView {
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
            GlassEffectContainer(spacing: 20) {
                bottomToolbarContent
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }

        @ViewBuilder
        var bottomToolbarContent: some View {
            HStack(spacing: 20) {
                // Back button (solo/quick mix modes only)
                if audioManager.soloModeSound != nil || audioManager.isQuickMix {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if audioManager.soloModeSound != nil {
                                audioManager.exitSoloMode()
                            } else if audioManager.isQuickMix {
                                audioManager.exitQuickMix()
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 22))
                            .foregroundColor(presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.glass)
                }

                // Back to Now Playing button (only when callback is present)
                if let onSwitchToNowPlaying = onSwitchToNowPlaying {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            onSwitchToNowPlaying()
                        }
                    } label: {
                        Image(systemName: "arrow.backward")
                            .font(.system(size: 22))
                            .foregroundColor(presetManager.currentPreset?.accentColor ?? globalSettings.customAccentColor ?? .accentColor)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
#endif
