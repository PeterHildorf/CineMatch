import SwiftUI

@main struct MyApp: App {
    /// `-demo` som launch-argument → mockdata i hele appen (se `AppContainer.demo()`).
    private let container = ProcessInfo.processInfo.arguments.contains("-demo") ? AppContainer.demo() : AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                .tint(Theme.accent)
        }
    }
}
