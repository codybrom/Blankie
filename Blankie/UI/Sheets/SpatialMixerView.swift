//
//  SpatialMixerView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFAudio
import CoreMotion
import SwiftUI

#if os(iOS) || os(visionOS) || os(macOS)

  /// Streams head yaw from motion-capable headphones (nil points the wedge up) and
  /// tracks the output route for the hints. macOS has no AVAudioSession, so it only tracks AirPods.
  final class HeadPoseMonitor: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    /// App-lifetime instance: CoreMotion delivers queued events after updates stop,
    /// so a deallocated manager or delegate crashes (EXC_BAD_ACCESS).
    static let shared = HeadPoseMonitor()

    @Published var yawDegrees: Double?
    @Published var headphonesConnected = false
    @Published var trackingAvailable = false

    private let manager = CMHeadphoneMotionManager()
    private var routeObserver: NSObjectProtocol?
    // Set by the connection delegate (motion-capable headphones only).
    // isDeviceMotionAvailable reports the device and stays true without headphones.
    private var trackingDeviceConnected = false

    private override init() {
      super.init()
      manager.delegate = self
    }

    func start() {
      guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
      manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
        // Drop updates queued after stop() so the wedge resets on leaving Head Tracked.
        guard let self, self.manager.isDeviceMotionActive, let motion else { return }
        self.yawDegrees = motion.attitude.yaw * 180 / .pi
      }
    }

    func stop() {
      manager.stopDeviceMotionUpdates()
      yawDegrees = nil
    }

    func beginRouteObservation() {
      refreshRoute()
      #if os(iOS) || os(visionOS)
        routeObserver = NotificationCenter.default.addObserver(
          forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.refreshRoute() }
        }
      #endif
      if manager.isDeviceMotionAvailable {
        manager.startConnectionStatusUpdates()
      }
    }

    func endRouteObservation() {
      if let routeObserver {
        NotificationCenter.default.removeObserver(routeObserver)
      }
      routeObserver = nil
      // Kept running during a head-tracked session to downgrade to Fixed on disconnect.
      if manager.isConnectionStatusActive,
        SpatialSessionManager.shared.mode != .headTracked
      {
        manager.stopConnectionStatusUpdates()
      }
    }

    // MARK: CMHeadphoneMotionManagerDelegate (motion-capable headphones only)

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
      DispatchQueue.main.async {
        self.trackingDeviceConnected = true
        self.refreshRoute()
      }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
      Task { @MainActor in
        self.trackingDeviceConnected = false
        self.refreshRoute()
        // Downgrade here, outside the sheet, so it works with the sheet closed.
        if SpatialSessionManager.shared.mode == .headTracked {
          SpatialSessionManager.shared.setMode(.fixed)
        }
      }
    }

    private func refreshRoute() {
      #if os(iOS) || os(visionOS)
        let headphonePorts: Set<AVAudioSession.Port> = [
          .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
        ]
        headphonesConnected = AVAudioSession.sharedInstance().currentRoute.outputs
          .contains { headphonePorts.contains($0.portType) }
      #endif
      trackingAvailable = manager.isDeviceMotionAvailable && trackingDeviceConnected
    }
  }

  /// Experimental spatial mixer: drag each sound's pin around the listener.
  /// Placements last for the session and are never written to presets.
  struct SpatialMixerView: View {
    private let audioManager = AudioManager.shared
    @ObservedObject private var session = SpatialSessionManager.shared
    @ObservedObject private var headPose = HeadPoseMonitor.shared
    @Environment(\.dismiss) private var dismiss

    private var mixSounds: [Sound] {
      audioManager.sounds.filter { $0.isSelected }
    }

    private var gridSounds: [Sound] {
      mixSounds.filter { session.isInField($0.fileName) && $0.isSpatialReady }
    }

    /// Removed or not-yet-prepared sounds, shown below the map.
    private var parkedSounds: [Sound] {
      mixSounds.filter { !(session.isInField($0.fileName) && $0.isSpatialReady) }
    }

    var body: some View {
      #if os(macOS)
        // Inline pane toggled from the window toolbar, so no Done button.
        mixerContent
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      #else
        NavigationStack {
          mixerContent
            .navigationTitle("Spatial Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              if session.isActive, !isSpreadOut {
                ToolbarItem(placement: .topBarLeading) { arrangeButton }
              }
              ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                  Text("Spatial Mix")
                    .font(.headline)
                  Text("Experimental")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
              }
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                  .tint(.primary)
              }
            }
        }
        // Page-sized on iPad. A `.large` detent would override `.page`.
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
        .presentationBackground {
          Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(0.8)
        }
      #endif
    }

    private var mixerContent: some View {
      VStack(spacing: 12) {
        controls

        // Same layout in every state so the map never resizes. Off dims an empty field.
        Group {
          SpatialGrid(
            sounds: session.isActive ? gridSounds : [],
            headYawDegrees: headPose.yawDegrees
          )
          .aspectRatio(1, contentMode: .fit)
          .padding(.horizontal)

          Text(
            "Drag pins to place. Tap a pin to remove it from the spatial map. Placements aren't saved between sessions."
          )
          .font(.caption)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)

          ParkedSoundsRow(sounds: session.isActive ? parkedSounds : [])
            .padding(.top, 10)
        }
        .disabled(!session.isActive)
        .opacity(session.isActive ? 1 : 0.35)
        .animation(.easeInOut(duration: 0.2), value: session.isActive)

        Spacer()
      }
      .padding(.top)
      .onAppear {
        headPose.beginRouteObservation()
        updatePoseMonitoring()
      }
      .onDisappear {
        headPose.stop()
        headPose.endRouteObservation()
      }
      .onChange(of: session.mode) { _, _ in updatePoseMonitoring() }
    }

    private var arrangeButton: some View {
      Button {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
          spreadOutSounds()
        }
      } label: {
        // Toolbars force Labels to icon-only, so an HStack keeps the text.
        HStack(spacing: 4) {
          Image(systemName: "move.3d")
          Text("Arrange")
        }
      }
      .tint(.primary)
    }

    /// True when pins already sit in the even spread, so Arrange is hidden.
    private var isSpreadOut: Bool {
      let sounds = gridSounds
      guard !sounds.isEmpty else { return true }
      return sounds.enumerated().allSatisfy { index, sound in
        let placement = sound.spatialPlacement()
        let slot = SpatialSessionManager.spreadSlot(index: index, count: sounds.count)
        // Circular compare: drags store (-180...180], slots use [0..360).
        let delta = abs((placement.angle - slot.angle).truncatingRemainder(dividingBy: 360))
        return min(delta, 360 - delta) < 0.5
          && abs(placement.distance - slot.distance) < 0.01
      }
    }

    private func spreadOutSounds() {
      guard !gridSounds.isEmpty else { return }

      for (index, sound) in gridSounds.enumerated() {
        let slot = SpatialSessionManager.spreadSlot(index: index, count: gridSounds.count)
        sound.setSpatialPlacement(
          angleDegrees: slot.angle, distance: slot.distance, persist: true)
      }
    }

    private var controls: some View {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 12) {
          Picker(
            "Spatial Audio",
            selection: Binding(
              get: { session.mode },
              set: { session.setMode($0) }
            )
          ) {
            Text("Off").tag(SpatialSessionMode.off)
            Text("Fixed").tag(SpatialSessionMode.fixed)
            // Shown only with tracking-capable headphones, like Apple's control.
            if headPose.trackingAvailable {
              Text("Head Tracked").tag(SpatialSessionMode.headTracked)
            }
          }
          .pickerStyle(.segmented)

          // No nav bar on macOS, so Arrange sits in this row.
          #if os(macOS)
            if session.isActive, !isSpreadOut {
              arrangeButton
            }
          #endif
        }

        // Hints only: the binaural render works on any headphones. macOS can't
        // read the route, so it shows only the tracking hint.
        #if os(iOS) || os(visionOS)
          if session.isActive, !headPose.headphonesConnected {
            Label("Connect headphones to hear the spatial effect", systemImage: "headphones")
              .font(.caption)
              .foregroundColor(.secondary)
          } else if session.isActive, !headPose.trackingAvailable {
            Label("Head tracking needs compatible AirPods", systemImage: "headphones")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        #else
          if session.isActive, !headPose.trackingAvailable {
            Label("Head tracking needs compatible AirPods", systemImage: "headphones")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        #endif
      }
      .padding(14)
      .modernGlassEffect(cornerRadius: 16)
      .padding(.horizontal, 16)
    }

    private func updatePoseMonitoring() {
      if session.mode == .headTracked {
        headPose.start()
      } else {
        headPose.stop()
      }
    }
  }

  // MARK: - Grid

  private struct SpatialGrid: View {
    let sounds: [Sound]
    var headYawDegrees: Double?

    /// Meters from the listener to the edge of the field.
    static let fieldRadius: Float = 3.0

    var body: some View {
      GeometryReader { geo in
        let side = min(geo.size.width, geo.size.height)
        let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        let scale = (side / 2 - 28) / CGFloat(Self.fieldRadius)  // points per meter
        let radius = CGFloat(Self.fieldRadius) * scale

        // The sheet transition passes through zero-size geometry, and a
        // non-positive scale crashes layout.
        if scale > 0 {
          gridContent(center: center, scale: scale, radius: radius)
        }
      }
    }

    private func gridContent(center: CGPoint, scale: CGFloat, radius: CGFloat) -> some View {
      ZStack {
        // .regular glass reads opaque at this size: clear glass, dim and accent rim.
        glassDisc(radius: radius)
          .position(center)

        gridBackground(center: center, scale: scale)

        // Sounds stay fixed in the room, so the wedge turns with the head.
        FacingWedge()
          .fill(.tint.opacity(0.13))
          .frame(width: radius * 2, height: radius * 2)
          .position(center)
          .rotationEffect(
            .degrees(-(headYawDegrees ?? 0)), anchor: .center
          )
          .animation(.linear(duration: 0.1), value: headYawDegrees)
          .allowsHitTesting(false)

        // Hub over the 0.5 m dead zone.
        Circle()
          .fill(.secondary.opacity(0.3))
          .overlay {
            Image(systemName: "headphones")
              .font(.system(size: scale * 0.4))
              .foregroundStyle(.secondary)
          }
          .frame(width: scale, height: scale)
          .position(center)
          .allowsHitTesting(false)

        ForEach(sounds, id: \.id) { sound in
          SpatialDot(sound: sound, center: center, scale: scale)
        }
      }
    }

    private func glassDisc(radius: CGFloat) -> some View {
      Circle()
        .fill(.black.opacity(0.12))
        .glassEffect(.clear, in: Circle())
        .overlay(Circle().strokeBorder(.tint.opacity(0.3), lineWidth: 1))
        .frame(width: radius * 2, height: radius * 2)
    }

    private func gridBackground(center: CGPoint, scale: CGFloat) -> some View {
      Canvas { context, _ in
        let radius = CGFloat(Self.fieldRadius) * scale
        let bounds = CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        // One line per half meter, clipped to the field.
        let clip = Path(ellipseIn: bounds)
        context.clip(to: clip)
        var grid = Path()
        var offset: CGFloat = 0
        while offset <= radius {
          for sign: CGFloat in (offset == 0 ? [1] : [1, -1]) {
            let position = offset * sign
            grid.move(to: CGPoint(x: center.x + position, y: center.y - radius))
            grid.addLine(to: CGPoint(x: center.x + position, y: center.y + radius))
            grid.move(to: CGPoint(x: center.x - radius, y: center.y + position))
            grid.addLine(to: CGPoint(x: center.x + radius, y: center.y + position))
          }
          offset += scale / 2
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)

        // Boundary plus 1 m and 2 m rings.
        context.stroke(clip, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
        for meters: CGFloat in [1, 2] {
          let ring = CGRect(
            x: center.x - meters * scale, y: center.y - meters * scale,
            width: meters * scale * 2, height: meters * scale * 2)
          context.stroke(
            Path(ellipseIn: ring), with: .color(.secondary.opacity(0.2)), lineWidth: 1)
        }

        // Dashed ring at the 0.5 m drag clamp.
        let exclusionRadius = 0.5 * scale
        let exclusion = CGRect(
          x: center.x - exclusionRadius, y: center.y - exclusionRadius,
          width: exclusionRadius * 2, height: exclusionRadius * 2)
        context.fill(
          Path(ellipseIn: exclusion), with: .color(.secondary.opacity(0.08)))
        context.stroke(
          Path(ellipseIn: exclusion), with: .color(.secondary.opacity(0.5)),
          style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
      }
    }

  }

  // MARK: - Parked Sounds (below the grid)

  /// Sounds off the map (removed, or long sounds without a mono variant yet).
  /// Keeps its height so the map never resizes.
  private struct ParkedSoundsRow: View {
    let sounds: [Sound]

    var body: some View {
      Group {
        if sounds.isEmpty {
          // Fixed height: a bare Color.clear would take the map's height.
          Color.clear
            .frame(height: 72)
        } else {
          VStack(spacing: 4) {
            Text("Off the Map")
              .font(.caption2)
              .textCase(.uppercase)
              .foregroundColor(.secondary)

            // Wraps. The map is width-sized, so extra rows only use the spacer.
            LazyVGrid(
              columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 8
            ) {
              ForEach(sounds, id: \.id) { sound in
                ParkedDot(sound: sound)
              }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .modernGlassEffect(cornerRadius: 14)
            .padding(.horizontal, 16)
          }
        }
      }
      .frame(minHeight: 72)
    }
  }

  private struct ParkedDot: View {
    let sound: Sound
    @State private var isPreparing = false

    var body: some View {
      VStack(spacing: 2) {
        ZStack {
          Circle()
            .fill(.gray.opacity(0.55))
            .frame(width: 36, height: 36)
          if isPreparing {
            ProgressView()
              .controlSize(.small)
          } else {
            Image(systemName: sound.systemIconName)
              .font(.system(size: 15))
              .foregroundStyle(.white)
          }
        }

        // A ternary String would pick Text's verbatim init and skip localization.
        Group {
          if isPreparing {
            Text("Preparing…")
          } else {
            Text(sound.localizedTitle)
          }
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .frame(maxWidth: 64)
      }
      .onTapGesture { placeInField() }
      .accessibilityLabel(Text("\(sound.localizedTitle), in your head, tap to place in space"))
    }

    /// Long sounds render a mono variant before joining the field.
    private func placeInField() {
      guard !isPreparing else { return }

      if sound.isSpatialReady {
        SpatialSessionManager.shared.setInField(true, for: sound.fileName)
        sound.rebuildPlayerForSpatialChange()
        return
      }

      isPreparing = true
      Task { @MainActor in
        let prepared = await sound.prepareForSpatial()
        isPreparing = false
        if prepared {
          SpatialSessionManager.shared.setInField(true, for: sound.fileName)
          sound.rebuildPlayerForSpatialChange()
        }
      }
    }
  }

  /// Map-pin teardrop whose tip is the placement point. `clockwise: false`
  /// sweeps over the top in SwiftUI's flipped space.
  private nonisolated struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      let headRadius = rect.width / 2
      let center = CGPoint(x: rect.midX, y: rect.minY + headRadius)
      let theta: CGFloat = .pi / 4  // where the tail leaves the head

      path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(
        to: CGPoint(
          x: center.x - headRadius * cos(theta), y: center.y + headRadius * sin(theta)))
      path.addArc(
        center: center, radius: headRadius,
        startAngle: .radians(.pi - theta), endAngle: .radians(theta), clockwise: false)
      path.closeSubpath()
      return path
    }
  }

  /// Pie slice pointing up (forward). The grid rotates it to the head yaw.
  private nonisolated struct FacingWedge: Shape {
    var spanDegrees: Double = 70

    func path(in rect: CGRect) -> Path {
      var path = Path()
      let center = CGPoint(x: rect.midX, y: rect.midY)
      let radius = min(rect.width, rect.height) / 2
      path.move(to: center)
      path.addArc(
        center: center, radius: radius,
        startAngle: .degrees(-90 - spanDegrees / 2),
        endAngle: .degrees(-90 + spanDegrees / 2),
        clockwise: false)
      path.closeSubpath()
      return path
    }
  }

  // MARK: - Sound Dot

  private struct SpatialDot: View {
    let sound: Sound
    @ObservedObject private var session = SpatialSessionManager.shared
    let center: CGPoint
    let scale: CGFloat

    @State private var dragPlacement: (angle: Float, distance: Float)?

    var body: some View {
      let placement = dragPlacement ?? sound.spatialPlacement()
      let distance = CGFloat(placement.distance)
      let radians = Double(placement.angle) * .pi / 180

      pin
        .position(
          x: center.x + CGFloat(sin(radians)) * distance * scale,
          y: center.y - CGFloat(cos(radians)) * distance * scale
        )
        .onTapGesture {
          SpatialSessionManager.shared.setInField(false, for: sound.fileName)

          // Last pin removed ends the session via setMode(.off), which rebuilds every player.
          let othersOnMap = AudioManager.shared.sounds.contains {
            $0.isSelected && $0.isSpatialReady
              && SpatialSessionManager.shared.isInField($0.fileName)
          }
          if othersOnMap {
            sound.rebuildPlayerForSpatialChange()
          } else {
            SpatialSessionManager.shared.setMode(.off)
          }
        }
        .gesture(dragGesture)
    }

    private var pin: some View {
      VStack(spacing: 2) {
        PinShape()
          .fill(.tint)
          .overlay(alignment: .top) {
            Image(systemName: sound.systemIconName)
              .font(.system(size: 13))
              .foregroundStyle(.white)
              .frame(height: 30)  // centered in the head circle
          }
          .frame(width: 30, height: 42)
          .shadow(color: .black.opacity(0.25), radius: 2, y: 1)

        Text(sound.localizedTitle)
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .frame(maxWidth: 64)
      }
      // Nudge up so the tail's tip sits on the placement point.
      .offset(y: -14)
      .accessibilityLabel(Text("\(sound.localizedTitle), placed in space"))
    }

    private var dragGesture: some Gesture {
      DragGesture()
        .onChanged { value in
          let xMeters = Float((value.location.x - center.x) / scale)
          let zMeters = Float((value.location.y - center.y) / scale)
          let distance = max(0.5, min(sqrt(xMeters * xMeters + zMeters * zMeters), 3))
          let angle = atan2(xMeters, -zMeters) * 180 / .pi
          dragPlacement = (angle, distance)
          sound.setSpatialPlacement(angleDegrees: angle, distance: distance, persist: false)
        }
        .onEnded { _ in
          if let placement = dragPlacement {
            sound.setSpatialPlacement(
              angleDegrees: placement.angle, distance: placement.distance, persist: true)
          }
          dragPlacement = nil
        }
    }
  }

#endif
