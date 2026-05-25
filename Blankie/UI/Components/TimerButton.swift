//
//  TimerButton.swift
//  Blankie
//
//  Created by Cody Bromley on 1/29/25.
//

import SwiftUI

struct TimerButton: View {
  @StateObject private var timerManager = TimerManager.shared
  @State private var showingTimerView = false

  var body: some View {
    Button(action: {
      showingTimerView = true
    }) {
      Image(systemName: "timer")
        .font(.system(size: 18))
        .foregroundColor(
          timerManager.isTimerActive
            ? (GlobalSettings.shared.customAccentColor ?? .accentColor) : .primary)
    }
    .accessibilityLabel("Timer")
    .buttonStyle(.borderless)
    #if os(macOS)
      .popover(isPresented: $showingTimerView, arrowEdge: .bottom) {
        TimerView()
      }
    #else
      .sheet(isPresented: $showingTimerView) {
        TimerSheetView()
        .presentationDetents([.height(375)])
      }
    #endif
  }
}

struct CompactTimerButton: View {
  @StateObject private var timerManager = TimerManager.shared
  @State private var showingTimerView = false

  var body: some View {
    Button(action: {
      showingTimerView = true
    }) {
      Image(systemName: "timer")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 20, height: 20)
        .foregroundColor(
          timerManager.isTimerActive
            ? (GlobalSettings.shared.customAccentColor ?? .accentColor) : .primary)
    }
    .accessibilityLabel("Timer")
    .buttonStyle(.borderless)
    #if os(macOS)
      .popover(isPresented: $showingTimerView, arrowEdge: .top) {
        TimerView()
      }
    #else
      .sheet(isPresented: $showingTimerView) {
        TimerSheetView()
        .presentationDetents([.height(375)])
      }
    #endif
  }
}
