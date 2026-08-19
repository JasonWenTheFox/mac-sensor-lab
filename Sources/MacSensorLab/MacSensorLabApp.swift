import SensorCore
import SwiftUI

@main
struct MacSensorLabApp: App {
  @StateObject private var model = SensorDashboardModel()

  var body: some Scene {
    WindowGroup("Mac Sensor Lab") {
      RootView(model: model)
        .frame(minWidth: 940, minHeight: 640)
        .task { await model.runLiveUpdates() }
    }
    .windowStyle(.titleBar)
    .defaultSize(width: 1120, height: 760)

    Settings {
      SettingsView()
    }
  }
}

private struct SettingsView: View {
  var body: some View {
    Form {
      Section("Safety") {
        Text(
          "Mac Sensor Lab reads sensors locally and does not request administrator access in this build."
        )
        Text(
          "Permission-gated providers are opt-in and will explain their purpose before requesting access."
        )
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 220)
    .padding()
  }
}
