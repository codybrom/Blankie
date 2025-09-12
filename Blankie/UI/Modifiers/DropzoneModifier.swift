//
//  DropzoneModifier.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct DropzoneModifier: ViewModifier {
  @ObservedObject var dropzoneManager: DropzoneManager
  @Binding var isDragTargeted: Bool
  @ObservedObject var globalSettings: GlobalSettings

  func body(content: Content) -> some View {
    content
      .overlay(
        isDragTargeted
          ? RoundedRectangle(cornerRadius: 12)
            .stroke(globalSettings.customAccentColor ?? .accentColor, lineWidth: 3)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill((globalSettings.customAccentColor ?? .accentColor).opacity(0.1))
            )
            .overlay(
              VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                  .font(.system(size: 40))
                  .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
                Text("Drop audio file to import")
                  .font(.headline)
                  .foregroundColor(globalSettings.customAccentColor ?? .accentColor)
              }
            )
            .allowsHitTesting(false)
          : nil
      )
      .onDrop(
        of: [
          UTType.fileURL,
          UTType.audio,
          UTType.mp3,
          UTType.wav,
          UTType.mpeg4Audio,
        ], isTargeted: $isDragTargeted
      ) { providers in
        // Don't handle text-based drags (those are for sound reordering)
        let hasTextOnly = providers.allSatisfy { provider in
          provider.registeredTypeIdentifiers.contains("public.utf8-plain-text")
            && !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        if hasTextOnly {
          return false
        }

        return handleDroppedFiles(providers)
      }
  }

  private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
    for provider in providers {
      // Try to load using the first registered type identifier
      if let firstType = provider.registeredTypeIdentifiers.first {
        provider.loadItem(forTypeIdentifier: firstType, options: nil) { item, error in
          DispatchQueue.main.async {
            if let url = item as? URL, error == nil {
              handleDroppedURL(url)
            }
          }
        }
        return true
      }

      // Fallback: Try different approaches to get the URL
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
          item, error in
          DispatchQueue.main.async {
            if let url = item as? URL, error == nil {
              handleDroppedURL(url)
            }
          }
        }
        return true
      } else if provider.canLoadObject(ofClass: URL.self) {
        _ = provider.loadObject(ofClass: URL.self) { url, error in
          DispatchQueue.main.async {
            if let url = url, error == nil {
              handleDroppedURL(url)
            }
          }
        }
        return true
      }
    }
    return false
  }

  private func handleDroppedURL(_ url: URL) {
    if isAudioFile(url) {
      dropzoneManager.setFileURL(url)
      // Allow state to update before presenting sheet
      Task { @MainActor in
        await Task.yield()
        dropzoneManager.showSheet()
      }
    }
  }

  private func isAudioFile(_ url: URL) -> Bool {
    let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "mp4", "m4v"]
    let fileExtension = url.pathExtension.lowercased()
    return audioExtensions.contains(fileExtension)
  }
}

extension View {
  func dropzone(
    manager: DropzoneManager,
    isDragTargeted: Binding<Bool>,
    globalSettings: GlobalSettings
  ) -> some View {
    modifier(
      DropzoneModifier(
        dropzoneManager: manager,
        isDragTargeted: isDragTargeted,
        globalSettings: globalSettings
      ))
  }
}
