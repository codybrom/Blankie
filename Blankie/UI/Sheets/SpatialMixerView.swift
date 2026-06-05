//
//  SpatialMixerView.swift
//  Blankie
//
//  Created by Cody Bromley on 6/4/26.
//

import AVFAudio
import CoreMotion
import SwiftUI

#if os(iOS) || os(visionOS)

  /// Streams the listener's live head yaw from compatible headphones so the
  /// grid can show which way they're actually facing (yaw nil = wedge rests
  /// at "up"), and tracks the output route for the capability hints — the
  /// binaural render works on any headphones, only tracking needs AirPods.
  final class HeadPoseMonitor: ObservableObject {
    @Published var yawDegrees: Double?
    @Published var headphonesConnected = false
    @Published var trackingAvailable = false

    private let manager = CMHeadphoneMotionManager()
    private var routeObserver: NSObjectProtocol?

    func start() {
      guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
      manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
        // Queued updates can land after stop(); dropping them keeps the wedge
        // from freezing at the last head yaw when leaving Head Tracked mode.
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
      routeObserver = NotificationCenter.default.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.refreshRoute()
      }
    }

    func endRouteObservation() {
      if let routeObserver {
        NotificationCenter.default.removeObserver(routeObserver)
      }
      routeObserver = nil
    }

    private func refreshRoute() {
      let headphonePorts: Set<AVAudioSession.Port> = [
        .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE,
      ]
      headphonesConnected = AVAudioSession.sharedInstance().currentRoute.outputs
        .contains { headphonePorts.contains($0.portType) }
      trackingAvailable = manager.isDeviceMotionAvailable
    }
  }

  /// Experimental per-preset spatial mixer: a grid of the space around the
  /// listener with draggable dots for each sound in the mix. Tap a dot to lock
  /// it into space or keep it in your head; positions save to the preset.
  struct SpatialMixerView: View {
    @ObservedObject private var audioManager = AudioManager.shared
    @ObservedObject private var session = SpatialSessionManager.shared
    @StateObject private var headPose = HeadPoseMonitor()
    @Environment(\.dismiss) private var dismiss

    private var mixSounds: [Sound] {
      audioManager.sounds.filter { $0.isSelected }
    }

    /// Sounds placed in the field — the only ones shown on the grid.
    private var gridSounds: [Sound] {
      mixSounds.filter { session.isInField($0.fileName) && $0.isSpatialReady }
    }

    /// Taken-out or not-yet-prepared sounds, shown in the row below the grid.
    private var parkedSounds: [Sound] {
      mixSounds.filter { !(session.isInField($0.fileName) && $0.isSpatialReady) }
    }

    var body: some View {
      NavigationStack {
        VStack(spacing: 16) {
          controls

          // Every state renders the same fixed layout (the strip reserves its
          // space even when empty) so the map never resizes; pins and chips
          // are the only things that come and go. Off = dimmed empty field.
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

            Button {
              withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                spreadOutSounds()
              }
            } label: {
              Label(
                "Spread Out",
                systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .buttonStyle(.bordered)

            ParkedSoundsRow(sounds: session.isActive ? parkedSounds : [])
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
        .navigationTitle("Spatial Mix")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
          }
        }
      }
      .presentationDetents([.large])
      .presentationDragIndicator(.visible)
      .presentationBackground {
        // More translucent than a stock material: let the mixer glow through.
        Rectangle()
          .fill(.ultraThinMaterial)
          .opacity(0.8)
      }
    }

    /// Distributes every placed, spatial-ready sound evenly around the
    /// listener at 2m, so overlapping dots become visible at a glance.
    private func spreadOutSounds() {
      guard !gridSounds.isEmpty else { return }

      let step = 360.0 / Float(gridSounds.count)
      for (index, sound) in gridSounds.enumerated() {
        sound.setSpatialPlacement(
          angleDegrees: Float(index) * step, distance: 2.0, persist: true)
      }
    }

    /// Apple-style session control: Off | Fixed | Head Tracked.
    private var controls: some View {
      VStack(alignment: .leading, spacing: 10) {
        Picker(
          "Spatial Audio",
          selection: Binding(
            get: { session.mode },
            set: { session.setMode($0) }
          )
        ) {
          Text("Off").tag(SpatialSessionMode.off)
          Text("Fixed").tag(SpatialSessionMode.fixed)
          // Like Apple's control: the option only exists when tracking-capable
          // headphones are connected.
          if headPose.trackingAvailable {
            Text("Head Tracked").tag(SpatialSessionMode.headTracked)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: headPose.trackingAvailable) { _, available in
          // AirPods disconnected mid-session: downgrade to Fixed, keep playing.
          if !available, session.mode == .headTracked {
            session.setMode(.fixed)
          }
        }

        // Soft capability hints: the binaural render works on any headphones,
        // so we inform rather than gate.
        if session.isActive, !headPose.headphonesConnected {
          Label("Connect headphones to hear the spatial effect", systemImage: "headphones")
            .font(.caption)
            .foregroundColor(.secondary)
        } else if session.isActive, !headPose.trackingAvailable {
          Label("Head tracking needs compatible AirPods", systemImage: "headphones")
            .font(.caption)
            .foregroundColor(.secondary)
        }
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

        ZStack {
          // Glassy field backing: .regular glass reads opaque on surfaces
          // this large, so use clear glass + a slight dim + an accent rim.
          glassDisc(radius: radius)
            .position(center)

          gridBackground(center: center, scale: scale)

          // Live listening direction: head tracking anchors the SOUNDS in the
          // room, so turning right means you now face sounds placed clockwise
          // — the wedge sweeps over what you're pointed at.
          FacingWedge()
            .fill(.tint.opacity(0.13))
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
            .rotationEffect(
              .degrees(-(headYawDegrees ?? 0)), anchor: .center
            )
            .animation(.linear(duration: 0.1), value: headYawDegrees)
            .allowsHitTesting(false)

          ForEach(sounds, id: \.id) { sound in
            SpatialDot(sound: sound, center: center, scale: scale)
          }
        }
      }
    }

    @ViewBuilder
    private func glassDisc(radius: CGFloat) -> some View {
      Group {
        if #available(iOS 26.0, *) {
          Circle()
            .fill(.black.opacity(0.12))
            .glassEffect(.clear, in: Circle())
        } else {
          Circle()
            .fill(.ultraThinMaterial)
        }
      }
      .overlay(Circle().strokeBorder(.tint.opacity(0.3), lineWidth: 1))
      .frame(width: radius * 2, height: radius * 2)
    }

    private func gridBackground(center: CGPoint, scale: CGFloat) -> some View {
      Canvas { context, _ in
        let radius = CGFloat(Self.fieldRadius) * scale
        let bounds = CGRect(
          x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        // Graph-paper grid, one line per half meter, clipped to the field circle
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

        // Field boundary + 1m/2m reference rings
        context.stroke(clip, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
        for meters: CGFloat in [1, 2] {
          let ring = CGRect(
            x: center.x - meters * scale, y: center.y - meters * scale,
            width: meters * scale * 2, height: meters * scale * 2)
          context.stroke(
            Path(ellipseIn: ring), with: .color(.secondary.opacity(0.2)), lineWidth: 1)
        }

        // Dead zone: pins clamp to ≥0.5m from the listener, so disclose the
        // keep-out spot with a dashed ring (matches the actual drag clamp).
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

  /// Sounds that aren't on the spatial map: taken off by tap, or long ones
  /// that haven't rendered their mono variant yet. Tap to (prepare and) place.
  /// Always occupies its height so the map above never resizes.
  private struct ParkedSoundsRow: View {
    let sounds: [Sound]

    var body: some View {
      Group {
        if sounds.isEmpty {
          Color.clear
        } else {
          VStack(spacing: 4) {
            Text("Off the Map")
              .font(.caption2)
              .textCase(.uppercase)
              .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 12) {
                ForEach(sounds, id: \.id) { sound in
                  ParkedDot(sound: sound)
                }
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 6)
            }
            .modernGlassEffect(cornerRadius: 14)
            .padding(.horizontal, 16)
          }
        }
      }
      .frame(height: 72)
    }
  }

  private struct ParkedDot: View {
    @ObservedObject var sound: Sound
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

        Text(isPreparing ? "Preparing…" : sound.title)
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .frame(maxWidth: 64)
      }
      .onTapGesture { placeInField() }
      .accessibilityLabel("\(sound.title), in your head, tap to place in space")
    }

    /// Long sounds render their mono variant first ("Preparing for Spatial"),
    /// then everything locks into the field and jumps onto the grid.
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

  /// Classic map-pin teardrop: circular head flowing into a tapered tail, as
  /// one filled path (the tip is the precise placement point). Arc direction
  /// verified: clockwise=false sweeps over the top in SwiftUI's flipped space.
  private struct PinShape: Shape {
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

  /// A wide pie slice pointing "up" (the canonical forward direction); the
  /// grid rotates it to the live head yaw.
  private struct FacingWedge: Shape {
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
    @ObservedObject var sound: Sound
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
          // Take the sound out of the field; it moves to the parked row.
          SpatialSessionManager.shared.setInField(false, for: sound.fileName)
          sound.rebuildPlayerForSpatialChange()
        }
        .gesture(dragGesture)
    }

    /// Map-pin look: a single teardrop silhouette (head + tapering tail in one
    /// filled path) with the sound's icon in the head, label underneath.
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

        Text(sound.title)
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .frame(maxWidth: 64)
      }
      // Nudge up so the tail's tip sits on the placement point.
      .offset(y: -14)
      .accessibilityLabel("\(sound.title), placed in space")
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
