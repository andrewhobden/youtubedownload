import SwiftUI

#if targetEnvironment(macCatalyst)
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Download…") {
                NotificationCenter.default.post(name: .openAddSheet, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
        CommandGroup(after: .toolbar) {
            Button("Reveal Download Folder in Finder") {
                NotificationCenter.default.post(name: .revealRoot, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

extension Notification.Name {
    static let openAddSheet = Notification.Name("openAddSheet")
    static let revealRoot   = Notification.Name("revealRoot")
}
#endif
