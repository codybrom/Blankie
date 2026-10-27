//
//  MainLoopSpin.swift
//  BlankieTests
//
//  Created by Cody Bromley on 10/12/26.
//
//  Fades and Now Playing debounces are run-loop timers and deferred work is main-actor tasks.
//  A sleeping test doesn't reliably run either, so race tests spin the run loop and yield.
//

import Foundation

/// Runs the main run loop and yields to queued main-actor tasks until
/// `condition` holds or `timeout` seconds pass.
@MainActor func spinMainLoop(
  timeout: TimeInterval, until condition: () -> Bool = { false }
) async {
  let deadline = Date(timeIntervalSinceNow: timeout)
  while !condition(), Date() < deadline {
    runMainLoopBriefly()
    await Task.yield()
  }
}

/// `RunLoop.run(until:)` is unavailable from async contexts, so it runs here.
@MainActor private func runMainLoopBriefly() {
  RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
