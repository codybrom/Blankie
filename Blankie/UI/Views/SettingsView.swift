import SwiftUI

struct SettingsView: View {
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @State private var showingAbout = false
  @State private var showingOnboarding = false

  var body: some View {
    NavigationStack {
      Form {
        Section(
          header: Text("Sounds", comment: "Settings section header for sound management")
        ) {
          NavigationLink(destination: SoundManagementView()) {
            HStack {
              Text("Manage Sounds", comment: "Sound management label")
              Spacer()
            }
          }
        }

        Section(
          header: Text("Lock Screen", comment: "Settings section header for lock screen options")
        ) {
          Toggle(isOn: Binding(
            get: { globalSettings.lockScreenBackgroundEnabled },
            set: { globalSettings.setLockScreenBackgroundEnabled($0) }
          )) {
            Text("Animated Background", comment: "Toggle for lock-screen animated artwork")
          }
        }

        Section(
          header: Text("About", comment: "Settings section header for about")
        ) {
          Button {
            showingAbout = true
          } label: {
            HStack {
              Text("About Blankie", comment: "About button label")
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          }
        }

        #if DEBUG
          Section(
            header: Text("Debug", comment: "Settings section header for debug options")
          ) {
            Button {
              showingOnboarding = true
            } label: {
              HStack {
                Image(systemName: "ladybug.fill")
                  .foregroundColor(.orange)
                Text("Show Onboarding", comment: "Debug button to show onboarding")
                Spacer()
              }
            }
          }
        #endif
      }
      .navigationTitle("Settings")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .sheet(isPresented: $showingAbout) {
          AboutView()
        }
        .sheet(isPresented: $showingOnboarding) {
          PresetOnboardingSheet(isPresented: $showingOnboarding)
        }
    }
  }
}

// Preview Provider
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}
