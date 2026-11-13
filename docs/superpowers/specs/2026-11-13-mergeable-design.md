# Mergeable — multi-account GitHub app design

Nov 13, 2026 · Anthony Pluth · Exported from the design doc: https://claude.ai/artifact/BU9HaVqvKyeQb8iJaET69h

## Intent and why

Mergeable is an iPhone and Mac app that shows your personal and work GitHub pull requests in one place and makes every action as the account that owns the repo.

You keep separate work and personal GitHub accounts and want them to stay separate when you comment on, review and merge PRs. Today that means switching accounts in GitHub Mobile or the browser, with the risk of acting as the wrong one. The closest existing app, Pulldog, is Mac-only; nothing does this on iPhone.

## Goals, non-goals, anti-goals

**Goals**

- One inbox of PRs across both accounts: a tab per account plus an All tab where every PR carries its account's badge.
- Comment, review and merge from the app, always as the account that owns the repo, with no manual switching.
- Push within seconds for accounts connected through your own GitHub App; a check every 15 minutes for accounts connected with a token (PAT). The headline alert: a PR is merge-ready.
- One SwiftUI codebase for iPhone and Mac.

**Not in v1**

- Issues, code browsing, repo settings, Actions management.
- GitHub Enterprise Server and GitLab.
- Line-by-line review comments (top-level comments and reviews only).
- App Store release; it's for your own devices.

**Anti-goals: failures even if everything else works**

- Any action made as the wrong account, even once.
- A GitHub token stored anywhere but your own devices' Keychain (one exception: the relay's read-only notifier key), or showing up in a log, crash report or push.
- Work PR content passing through any server, including your own relay.

## Constraints

Work connects with a PAT because org approval for an app isn't realistic; personal connects through your own GitHub App, which needs nobody's approval.

- **Work org** is on standard github.com. An org can require an owner to approve each fine-grained PAT; classic PATs are never subject to approval unless the org blocks them ([GitHub docs](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization)). If the org uses SSO, a classic token is authorized for it once, by you ([GitHub docs](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/authorizing-a-personal-access-token-for-use-with-single-sign-on)).
- **PAT permissions:** Pull requests read/write (comment, review), Contents read/write (merge), Metadata read, Commit statuses and Checks read. A fine-grained token covers one owner, so a work account spanning several orgs needs one token per org.
- **GitHub App sign-in** uses device flow. Refreshing a device-flow token needs no client secret, so no secret ships in the app ([GitHub docs](https://docs.github.com/en/enterprise-server@3.15/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)). User tokens last 8 hours; refresh tokens last 6 months.
- **A GitHub App only reaches repos it's installed on**, so it covers your personal repos and any org you own, never the work org.
- **No server holds your tokens.** The only server is a small push relay for personal repos. It holds one read-only key, from a separate notifier GitHub App, so a leaked key can't change anything.
- **Background refresh on iPhone is scheduled by iOS.** Asking for every 15 minutes doesn't guarantee it.
- **Building:** the Swift apps need Xcode on your Mac, so they're built in your local Claude Code. The relay can be built and tested anywhere.

## Approaches

You picked a native app on both devices calling GitHub directly, with push for personal through your own GitHub App and 15-minute polling for work.

| Approach | Trade-off | Outcome |
| --- | --- | --- |
| Native SwiftUI app, iPhone + Mac, direct API calls | Tokens stay on your devices; most work to build | Picked |
| Mac only | [Pulldog](https://setapp.com/apps/pulldog) already does multi-account PR review on Mac | Dropped |
| Self-hosted web app | Works on any device, but the work token would live on a server | Dropped |
| Push via your own GitHub App + webhook relay | Alerts in seconds; needs a small relay; only works where you can install the app | Picked for personal |
| Poll on the device every 15 minutes | No server; slower, and iOS controls iPhone timing | Picked for work |
| Mac relays work alerts to iPhone through iCloud | Token stays on devices; only while the Mac is awake | Not now |
| Work notification emails to a Cloudflare Email Worker | Alerts 24/7, but work content passes through your domain and orgs can block it | Dropped |

## Accounts and routing

The app has no "current account": every write picks its token from the PR's repo at the moment of the call.

| Account field | What it holds |
| --- | --- |
| Connection | GitHub App (device-flow sign-in, push) or PAT (pasted, polled); a PAT account can hold one token per org |
| Login | Read from the API when you connect |
| Label and color | For example Personal (blue) and Work (orange), shown on every badge and action button |
| Owners | Its own login, the orgs it belongs to, plus any you add by hand |

1. **Owner map first.** The repo's owner decides the account. An owner claimed by two accounts must be assigned by hand before any write there is allowed.
2. **Unmapped owner** (say, an open-source repo): the account whose query returned the PR acts on it.
3. **Returned by both, owner unmapped:** the app asks once and remembers.
4. **Every action button says who it acts as**, for example "Approve as @login". Merge always opens a confirm sheet showing account, method and target branch.
5. **Never fall back.** A token that fails marks its account as needing attention; the app never retries with the other account's token.
6. **No owning account:** the PR is shown read-only with the reason.

## What the app does

An inbox, a PR detail screen and a handful of actions, on both iPhone and Mac.

**Look:** match GitHub's own styling closely, in light and dark mode. Use GitHub's Primer colors and spacing, its Octicons icon set (both open source), and GitHub's PR state colors: open green, draft gray, merged purple, closed red. Checks and review states use the same icons as github.com. The app icon and name stay its own, with no GitHub logo. You sign off on mockups of the inbox and PR screens before they're built.

- **Inbox:** tabs for All, Personal and Work (one per account). Each tab has three sections: Needs your review, Your PRs, Assigned or mentioned. Each row shows repo, title, author, checks status, review state, age and the account badge.
- **PR detail:** description, conversation, checks, and files changed with read-only diffs.
- **Actions:** comment; submit a review (approve, request changes, comment); merge (merge, squash or rebase, remembered per repo); mark ready for review; close or reopen; open in Linear, for accounts where you turn it on (the PR link with github.com swapped for linear.review).
- **Mac:** a main window plus a menu bar item with unread counts per account. It starts at login, so polling and push keep working with the window closed.
- **Settings:** add an account (GitHub App sign-in, or paste a PAT with the required permissions listed beside the field), label and color, owner map, notification toggles per account.
- **PAT accounts show this note:** "Checks every 15 minutes. On iPhone, iOS may check less often."

## Notifications

Personal gets real push within seconds through a small relay; work is checked on the device every 15 minutes and never touches the relay.

**Push path (GitHub App accounts)**

1. A separate, read-only notifier app installed on your personal account sends webhooks to a Cloudflare Worker at push.pluth.org. The Mergeable app you sign in with sends none.
2. The Worker checks the webhook signature and drops events you caused yourself, except PRs opened under your account, so PRs your agents open still alert you.
3. It sends a short message through Apple's push service to every registered iPhone and Mac. Tapping it opens the PR.

Events: merge-ready (below), PR opened, ready for review, review requested, review submitted, new comment, checks failed, merged or closed.

**Merge-ready** means open, not a draft, every check and status passing, and no merge conflicts. It alerts once per new commit, for PRs you opened plus every PR in repos you own. Work PRs get it from the 15-minute check.

Webhooks report each check finishing, not that all of them have, so after each one the relay asks GitHub for the PR's overall status, using a short-lived read-only token from the notifier app.

The Worker stores only device push tokens (Workers KV). Its secrets: the webhook secret, the notifier app's private key, your Apple push key (.p8 from your developer account), and a registration secret the app uses to register devices.

**Polling path (PAT accounts)**

- **Mac:** a timer every 15 minutes while the app runs; the menu bar item keeps it alive.
- **iPhone:** background refresh requested every 15 minutes, run when iOS allows. The app also refreshes on open and on pull-to-refresh.
- Each check runs the inbox queries, compares them with the last result, and shows local notifications for the same event types. Nothing leaves the device.

## Security

GitHub tokens live only in your devices' Keychain and are only ever sent to GitHub.

- Tokens sync between your iPhone and Mac through iCloud Keychain (end-to-end encrypted), so you add each one once. Any account can be switched to this-device-only.
- Tokens go only to api.github.com and github.com. They never appear in logs, crash reports or push payloads.
- The relay's only GitHub credential is the notifier app's key: read-only, personal repos only. Work data never reaches it.
- The relay rejects webhooks without a valid signature and device registrations without the registration secret.
- Least privilege: the work PAT is limited to the work org with only the permissions under Constraints; the GitHub App asks for the same set on your personal account.

## Calls I made for you to check

These are my defaults, not things you agreed to; flip any of them.

1. **Name:** Mergeable, after the alert it's built around.
2. **Relay on Cloudflare Workers at push.pluth.org:** pluth.org is already on Cloudflare and the free plan covers this. Fallback: a small container at home behind Traefik.
3. **Self-triggered events:** no push for your own comments, reviews or merges, but yes for PRs opened under your account, so agent-opened PRs alert you.
4. **Single-user relay:** every registered device gets every personal push; no per-user accounts.
5. **iCloud Keychain sync on by default** for tokens and the relay's registration secret.
6. **Unread** means activity since you last opened the PR in Mergeable, synced between devices through iCloud.
7. **v1 has top-level comments and reviews only**, no line comments.
8. **Merge always asks for confirmation.**
9. **Latest iOS and macOS only**, installed on your devices through Xcode or TestFlight.
10. **Repo:** a new public AnthonyPluth/Mergeable, managed by Terraform in your Infrastructure repo, with the same agent setup as your other app repos.

## Left to the builder, and what to check first

Four quick checks come before the main build, because each one could change the design.

1. **Push from a Worker:** send one push from a Cloudflare Worker to a real iPhone and Mac. Apple's push service requires HTTP/2 ([Apple docs](https://developer.apple.com/documentation/usernotifications/establishing-a-connection-to-apns)); a Workers library exists for it ([cloudflare-apns2](https://npmjs.com/package/@fivesheepco/cloudflare-apns2)), but confirm it works before building on it. If it doesn't, move the relay home.
2. **Work PAT:** create it and confirm it can list, comment and merge on a test PR. Try fine-grained first; fall back to classic if approval blocks it.
3. **Inbox queries:** confirm the search queries return every section's PRs with a fine-grained token.
4. **iPhone background refresh:** measure how often it actually runs for this app over a few days.

**Left to the builder:** screen layout and styling, local caching, query shapes, how polling detects changes, Worker code structure, error and empty states, bundle IDs. One rule: account routing gets unit tests for every rule above, since it's the part that must never be wrong.

**Sources:** [PAT policies for orgs](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization) · [PATs with SSO](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/authorizing-a-personal-access-token-for-use-with-single-sign-on) · [Refreshing GitHub App user tokens](https://docs.github.com/en/enterprise-server@3.15/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens) · [APNs connection](https://developer.apple.com/documentation/usernotifications/establishing-a-connection-to-apns) · [cloudflare-apns2](https://npmjs.com/package/@fivesheepco/cloudflare-apns2) · [Pulldog](https://setapp.com/apps/pulldog)
