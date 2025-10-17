import SwiftUI

struct SettingsView: View {
  @ObservedObject private var globalSettings = GlobalSettings.shared
  @Environment(\.dismiss) private var dismiss

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
      }
      .navigationTitle("Settings")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Button {
              dismiss()
            } label: {
              Text("Done", comment: "Settings done button")
            }
          }
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
