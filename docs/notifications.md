# Notifications and background work

## What runs where

| | GitHub App accounts (personal) | Token (PAT) accounts (work) |
|---|---|---|
| Alerts come from | The relay, through Apple push (seconds) | The app, as local notifications |
| Checked | On open and pull-to-refresh, for the screen only | Every 900 seconds (see below), plus on open and pull-to-refresh |
| Alert copy | `relay/src/copy.ts` | `NotificationCopy.render` (same strings) |

The poller fetches every account's inbox in one pass, so the inbox screen and the alerts always agree. For GitHub App accounts it fetches and
shows but never alerts, so a PR is never announced twice.

- **iPhone:** a background refresh (`com.pluth.mergeable.refresh`) is requested 900 seconds ahead and re-requested on every run. iOS decides
  when it really runs and often does so less often. Each refresh is logged under Settings, Accounts, Notifications, Diagnostics.
- **Mac:** a 900-second timer while the app runs. The app stays running after its window closes (the menu bar item), and can start at login.
- **Menu bar (Mac):** unread count per account. Unread means updated after you last opened the PR, or after the account's marker (set the first
  time the account is seen, or by "Mark all as read"). Markers sync through iCloud key-value storage.
- **First run after install:** the first check only records what is already there. Already-ready PRs are remembered so they don't alert later. Poll
  state is kept on the device (Application Support), not in iCloud, so a reinstall starts with a fresh baseline and no flood.
- **Tapping an alert** (local or push) opens the PR from the payload's `mergeable` object (`{v:1, kind, owner, repo, number, url}`), or the
  GitHub page if it is not in the inbox.

## Your steps

1. Deploy the relay (`docs/setup.md`) and note its registration secret.
2. In the app: Accounts, Notifications. Enter the relay URL (`https://push.pluth.org`) and the registration secret, then Save and register. The
   secret goes in the Keychain. Do this on each device.
3. Push only works in a signed build with the Push Notifications capability and your team's provisioning. In Xcode, select your team, add the
   capability on both platforms, and run a Debug build (registers as `sandbox`) or a Release/TestFlight build (registers as `production`). The push
   entitlement key differs by platform (`aps-environment` on iOS, `com.apple.developer.aps-environment` on macOS); `App/Entitlements/` has one file
   for each and `project.yml` picks the right one per SDK.
4. Allow notifications when asked. Turn alerts off per work account under Alerts on this device if you want.
5. Mac: turn on Start at login if you want the menu bar item after a restart.

CI builds are unsigned, so they compile and test all of this but cannot register for push.
