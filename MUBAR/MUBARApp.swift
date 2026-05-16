import SwiftUI

@main
struct MUBARApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // No window scene. The status item + popover are managed in AppDelegate.
        // Settings{} satisfies App's body requirement; with LSUIElement true the
        // Settings menu is unreachable, so it stays out of the way.
        Settings { EmptyView() }
    }
}
