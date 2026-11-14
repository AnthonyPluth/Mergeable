import SwiftUI
#if os(macOS)
import AppKit

/// Contents of the menu bar item: unread count per account, refresh, open the window, quit.
struct MenuBarContent: View {
    @ObservedObject var services: AppServices
    @ObservedObject var accounts: AccountStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if accounts.accounts.isEmpty {
            Text("No accounts yet")
        }
        ForEach(accounts.accounts) { a in
            Text("@\(a.login): \(services.unreadCounts[a.id] ?? 0) unread")
        }
        Divider()
        Button("Open Mergeable") {
            if let w = NSApp.windows.first(where: { $0.canBecomeMain }) { w.makeKeyAndOrderFront(nil) } else { openWindow(id: "main") }
            NSApp.activate()
        }
        Button("Check now") { Task { await services.refresh(.foreground) } }
        Button("Mark all as read") { services.markAllRead() }
        Divider()
        Button("Quit Mergeable") { NSApp.terminate(nil) }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var services: AppServices
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.pull")
            if services.totalUnread > 0 { Text("\(services.totalUnread)") }
        }
    }
}
#endif
