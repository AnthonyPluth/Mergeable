import Foundation
import SwiftUI
import UserNotifications
import MergeableCore

/// Everything that has to outlive any one screen: the account store, the inbox, the poller, push registration, unread
/// state and the refresh log. One instance, because a background refresh on iPhone can launch the app with no UI at all
/// and the app delegate needs the same objects the views use.
@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let accounts: AccountStore
    let env: AppEnvironment
    let inbox: InboxModel
    let router: NotificationRouter
    let push: PushRegistration
    let relaySettings: RelaySettings
    let alertToggles: UserDefaultsAlertToggles
    let refreshLog: RefreshLog

    @Published private(set) var unreadCounts: [AccountID: Int] = [:]
    @Published private(set) var refreshEntries: [RefreshEntry] = []

    private let poller: InboxPoller
    private let unread: UnreadTracker
    private let notificationDelegate: NotificationDelegate
    private var timer: Timer?
    private var started = false
    private var observer: NSObjectProtocol?

    private init() {
        let store = AccountStore()
        let env = AppEnvironment(store: store)
        let toggles = UserDefaultsAlertToggles()
        let poller = InboxPoller(source: env.client, store: FilePollStateStore(), toggles: toggles, sink: LocalAlertCenter())
        let inbox = InboxModel()
        inbox.poller = poller
        let router = NotificationRouter()
        let relaySettings = RelaySettings(defaults: UbiquitousKeyValueStore())

        accounts = store
        self.env = env
        self.inbox = inbox
        self.poller = poller
        self.router = router
        self.alertToggles = toggles
        self.relaySettings = relaySettings
        push = PushRegistration(settings: relaySettings, client: RelayClient(transport: URLSessionTransport()))
        unread = UnreadTracker(store: UbiquitousKeyValueStore())
        refreshLog = RefreshLog(store: UserDefaultsKeyValueStore())
        notificationDelegate = NotificationDelegate(router: router)
        refreshEntries = refreshLog.entries
        inbox.onRefreshed = { [weak self] in self?.recomputeUnread() }
    }

    /// Called from the app delegate at launch. Does nothing under XCTest, so the test host never asks for permissions,
    /// registers background tasks or starts timers.
    func start() {
        guard !started, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        started = true
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Task { await push.requestAuthorizationAndRegister() }
        #if os(iOS)
        BackgroundRefresh.register { await AppServices.shared.refresh(.background) }
        BackgroundRefresh.schedule()
        #elseif os(macOS)
        timer = Timer.scheduledTimer(withTimeInterval: InboxPoller.interval, repeats: true) { _ in
            Task { @MainActor in await AppServices.shared.refresh(.timer) }
        }
        #endif
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.unread.reload(); self?.recomputeUnread() }
        }
    }

    /// One refresh of every account: updates the inbox screen, and for PAT accounts posts alerts.
    func refresh(_ source: RefreshSource) async {
        await inbox.refresh(accounts: accounts.accounts, client: env.client)
        refreshLog.record(source)
        refreshEntries = refreshLog.entries
    }

    func markRead(_ pr: PullRequestSummary) {
        unread.markOpened(pr)
        recomputeUnread()
    }

    func markAllRead() {
        for a in accounts.accounts { unread.markAllRead(account: a.id) }
        recomputeUnread()
    }

    var totalUnread: Int { unreadCounts.values.reduce(0, +) }

    func alertsEnabled(_ id: AccountID) -> Bool { alertToggles.isEnabled(id) }
    func setAlerts(_ on: Bool, for id: AccountID) { alertToggles.setEnabled(on, for: id); objectWillChange.send() }

    private func recomputeUnread() {
        var counts: [AccountID: Int] = [:]
        for a in accounts.accounts {
            guard let snap = inbox.snapshots[a.id] else { continue }
            unread.ensureMarker(for: a.id)
            counts[a.id] = unread.unreadCount(snap, account: a.id)
        }
        unreadCounts = counts
    }
}
