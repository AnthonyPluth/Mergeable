import Foundation
#if os(iOS)
import BackgroundTasks

/// iPhone background refresh. iOS decides when (and whether) to run it; we ask for 900 seconds from now each time.
enum BackgroundRefresh {
    static let identifier = "com.pluth.mergeable.refresh"

    /// Call exactly once, before the app finishes launching. `work` runs the refresh on the main actor.
    static func register(work: @escaping @MainActor () async -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()   // reschedule first, so a crash or expiry doesn't end the chain
            let job = Task { @MainActor in
                await work()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { job.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: InboxPoller.interval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif
