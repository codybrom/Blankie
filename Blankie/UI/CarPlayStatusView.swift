// CarPlayStatusView.swift
// Blankie
//
// Created by Cody Bromley on 4/18/25.
//
#if CARPLAY_ENABLED && canImport(CarPlay)

  import SwiftUI

  struct CarPlayStatusView: View {
    @ObservedObject private var carPlayInterface = CarPlayInterface.shared

    var body: some View {
      if carPlayInterface.isConnected {
        HStack {
          Image(systemName: "car.fill")
          Text("Connected to CarPlay")
            .font(.system(.subheadline, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .foregroundStyle(.secondary)
      }
    }
  }

  // Modifier to add CarPlay status to any view
  struct CarPlayStatusModifier: ViewModifier {
    func body(content: Content) -> some View {
      VStack(spacing: 0) {
        CarPlayStatusView()
        content
      }
    }
  }

  extension View {
    func withCarPlayStatus() -> some View {
      self.modifier(CarPlayStatusModifier())
    }
  }
#endif
