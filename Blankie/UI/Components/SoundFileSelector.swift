//
//  SoundFileSelector.swift
//  Blankie
//
//  Created by Cody Bromley on 5/30/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct SoundFileSelector: View {
  @Binding var selectedFile: URL?
  @Binding var soundName: String
  @Binding var isImporting: Bool
  var hideChangeButton: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Sound File")
        .font(.headline)

      if let selectedFile = selectedFile {
        HStack {
          Image(systemName: "doc.fill")
            .foregroundStyle(.tint)
          VStack(alignment: .leading) {
            Text(selectedFile.lastPathComponent)
              .lineLimit(1)
            Text(formatFileSize(selectedFile))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          if !hideChangeButton {
            Button {
              isImporting = true
            } label: {
              Text("Change")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        }
        .padding()
        .background(
          Group {
            #if os(macOS)
              Color(NSColor.controlBackgroundColor)
            #else
              Color(UIColor.systemBackground)
            #endif
          }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        Button {
          isImporting = true
        } label: {
          HStack {
            Image(systemName: "plus.circle.fill")
              .font(.title2)
            Text("Select Sound File")
              .font(.headline)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 20)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  // MARK: - Helper Methods

  private func formatFileSize(_ url: URL) -> String {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let fileSize = attributes[.size] as? Int64
    else {
      return "Unknown size"
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: fileSize)
  }
}

// MARK: - Previews

#Preview("Empty State") {
  struct PreviewWrapper: View {
    @State private var selectedFile: URL?
    @State private var soundName = ""
    @State private var isImporting = false

    var body: some View {
      SoundFileSelector(
        selectedFile: $selectedFile,
        soundName: $soundName,
        isImporting: $isImporting
      )
      .padding()
      .frame(width: 400)
    }
  }

  return PreviewWrapper()
}

#Preview("With File") {
  struct PreviewWrapper: View {
    @State private var selectedFile: URL? = URL(
      fileURLWithPath: "/Users/example/Music/ambient-sound.mp3")
    @State private var soundName = "Ambient Sound"
    @State private var isImporting = false

    var body: some View {
      SoundFileSelector(
        selectedFile: $selectedFile,
        soundName: $soundName,
        isImporting: $isImporting
      )
      .padding()
      .frame(width: 400)
    }
  }

  return PreviewWrapper()
}
