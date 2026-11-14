import Foundation

enum AppConfig {
    /// Client ID of the "Mergeable" GitHub App (see docs/setup.md). Device flow needs no client secret.
    static let githubAppClientID = "REPLACE_WITH_MERGEABLE_APP_CLIENT_ID"
    static let keychainService = "com.pluth.mergeable"
    static let patPermissions = [
        "Pull requests: Read and write", "Contents: Read and write", "Metadata: Read",
        "Commit statuses: Read", "Checks: Read",
    ]
    static let pollingNote = "Checks every 15 minutes. On iPhone, iOS may check less often."
}
