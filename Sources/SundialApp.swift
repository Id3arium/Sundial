import SwiftUI
import ServiceManagement

@main
struct SundialApp: App {
    @StateObject private var appState = AppState()
    private let controller = DDCController(cliPath: "/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay", displayName: "GIGABYTE")
    private let scheduler = Scheduler()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .onAppear {
                    controller.cliPath = appState.cliPath
                    controller.displayName = appState.displayName
                    scheduler.start(state: appState, controller: controller)
                    appState.onPreviewEnded = { [scheduler] in
                        scheduler.reapplyForCurrentTime()
                    }
                    appState.onScheduleChanged = { [scheduler] in
                        scheduler.recompute()
                    }
                }
        } label: {
            Label("Sundial", systemImage: "sun.max")
        }
        .menuBarExtraStyle(.window)
    }
}
