# Mergeable Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Mergeable, an iPhone + Mac app that shows personal and work GitHub PRs together, acts on each PR as the account that owns its repo, and alerts you when a PR is merge-ready.

**Architecture:** One repo with three parts. `relay/` is a Cloudflare Worker that turns webhooks from a read-only "Mergeable Notifier" GitHub App into Apple pushes and decides merge-readiness itself. `MergeableCore/` is a Foundation-only Swift package holding everything testable without a device: routing, the GitHub client, merge-readiness, device flow, polling change detection and alert copy. `App/` is the SwiftUI app for iOS and macOS (XcodeGen), holding Keychain, UI, notifications and background work.

**Tech Stack:** TypeScript, Wrangler, Vitest (relay) · Swift 6, SwiftPM, Swift Testing (core) · SwiftUI, XcodeGen, Security, UserNotifications, BackgroundTasks, ServiceManagement (app) · GitHub GraphQL + REST · APNs token auth · `@primer/primitives` and `@primer/octicons` from npm (MIT).

**Spec:** "Mergeable — multi-account GitHub app design" (https://claude.ai/artifact/BU9HaVqvKyeQb8iJaET69h). Task 0 commits it as `docs/superpowers/specs/2026-11-13-mergeable-design.md`.

**Where each part builds:** `relay/` and `tools/` need Node 20+ and run anywhere. `MergeableCore` tests run with `swift test` on the Mac (Linux works too). `App/` needs Xcode, so Part 3 runs in your local Claude Code on the Mac.

**How it runs:** in Claude Code, as two parallel tracks in separate worktrees, each on its own branch and ending in its own PR. The main session does Task 0's agent setup and Task 2 with you, then one whole-branch review of each PR. Part 3 starts later, after both PRs merge.

| Track | Branch | Tasks |
|---|---|---|
| A: relay | `relay` | 1, 3, 4, 5, 6 |
| B: core | `core` | 7, 8, 9, 10 |

## Global Constraints

- iPhone and Mac from one SwiftUI codebase. Deployment target = the newest major iOS/macOS in the installed Xcode SDK; no older-OS support.
- Bundle ID `com.pluth.mergeable` on both platforms; the APNs topic is the same string.
- Personal accounts connect through the "Mergeable" GitHub App with device flow; no client secret ships in the app. Work accounts connect with a PAT (fine-grained, one per org, or classic).
- PAT permissions, listed beside the paste field: Pull requests read/write, Contents read/write, Metadata read, Commit statuses read, Checks read.
- Tokens live only in the Keychain, iCloud-synced by default, with a per-account "This device only" switch. They are sent only to api.github.com and github.com and never appear in logs, crash reports or push payloads.
- The relay (Cloudflare Worker at `https://push.pluth.org`) holds the Notifier app's private key and no other GitHub credential. Work data never reaches it.
- Every write resolves its account from the PR at the moment of the call and never falls back to another account's token.
- Action buttons name the acting account: "Comment as @login", "Approve as @login", "Request changes as @login", "Merge as @login", "Mark ready as @login".
- Merge always opens a confirm sheet showing account, method and target branch, and sends `expectedHeadOid`.
- Merge-ready = state OPEN, not a draft, check rollup SUCCESS or no checks at all, mergeable not CONFLICTING. Alert once per (PR, head commit), for PRs you authored plus every PR in repos your login owns.
- Self filter: no alert for your own comments, reviews, ready-for-review, merges or closes. PRs opened under your account, and merge-ready, always alert.
- Polling interval 900 seconds. PAT account settings show exactly: "Checks every 15 minutes. On iPhone, iOS may check less often."
- Look: Primer functional color tokens (light and dark) and Octicons. PR state colors: open `fgColor.open`, draft `fgColor.muted`, merged `fgColor.done`, closed `fgColor.closed`. No GitHub logo anywhere.
- Not in v1: line comments, issues, code browsing, GitHub Enterprise Server, GitLab, App Store release.
- Alert copy, shared by relay and app. Subtitle is always `{owner}/{repo} #{number}`; body is the PR title.

| kind | title |
|---|---|
| mergeReady | Ready to merge |
| opened | New pull request |
| readyForReview | Ready for review |
| reviewRequested | Review requested |
| reviewSubmitted | {actor} approved · {actor} requested changes · {actor} reviewed |
| comment | {actor} commented |
| checksFailed | Checks failed |
| merged | Merged by {actor} |
| closed | Closed by {actor} |

## Review Focus

1. **Your own account makes a PR ready.** An agent marks your PR ready for review (sender = you) after checks already passed → the merge-ready alert still fires, once. Test in Task 6.
2. **Repo with no CI.** A PR with no checks (rollup null) is merge-ready as soon as it is open and not a draft. Tests in Tasks 5, 6, 7.
3. **PR changed after you looked.** A commit lands between opening the PR and tapping Merge → merge is refused with "This PR changed since you opened it", never merging unseen code. Tests in Tasks 8, 13.
4. **First check after install or reinstall.** The first poll is a baseline and sends no alerts. Test in Task 10.
5. **Xcode build vs TestFlight build.** A device registered from a Debug build gets pushes from the APNs sandbox host, and a device is never deleted because of an error from the other environment's host. Test in Task 6.

---

## Part 0 — Setup and checks

### Task 0: Repo and docs

**Files:** Create `README.md`, `.gitignore` (Node, Xcode, `.dev.vars`, `*.p8`, `*.pem`), `docs/superpowers/specs/2026-11-13-mergeable-design.md`, `docs/superpowers/plans/2026-11-13-mergeable.md`.

- [x] Create the public repo `AnthonyPluth/Mergeable` through the Infrastructure repo's Terraform (Infrastructure #19 and #20).
- [x] Export the spec doc to Markdown at the spec path; copy this plan to the plan path; commit `docs: add Mergeable design and plan` to `main`.
- [ ] Add the agent build setup the same way as Darkroom, Waypoint and Runway (from the shared agent tooling repo, fleet), on a branch with its own PR.

### Task 1: APNs from a Worker (check that becomes `apns.ts`)

Needs from you: an APNs auth key (.p8), its Key ID, and your Team ID.

**Files:** Create `relay/package.json`, `relay/tsconfig.json`, `relay/wrangler.toml`, `relay/src/apns.ts`, `relay/test/apns.test.ts`.

**Interfaces — Produces:**
- `type ApnsEnvironment = "sandbox" | "production"`
- `apnsHost(env: ApnsEnvironment): string` → `api.sandbox.push.apple.com` / `api.push.apple.com`
- `interface ApnsConfig { keyId: string; teamId: string; p8Pem: string; topic: string }`
- `providerToken(cfg: ApnsConfig, nowSeconds: number): Promise<string>` — ES256 JWT, header `{alg:"ES256", kid: keyId}`, claims `{iss: teamId, iat: nowSeconds}`
- `sendPush(cfg: ApnsConfig, deviceToken: string, environment: ApnsEnvironment, body: object): Promise<{ status: number; reason?: string }>` — POST `https://<host>/3/device/<token>` with `apns-topic: com.pluth.mergeable`, `apns-push-type: alert`, `apns-priority: 10`, `authorization: bearer <providerToken>`

- [ ] **Write failing tests:** `providerToken` with a P-256 key generated in the test (decode header and claims, verify the signature with WebCrypto); `sendPush` with stubbed `fetch` (sandbox URL, the four headers, body passed through, `reason` parsed from a 400 body).
- [ ] **Run** `cd relay && npx vitest run test/apns.test.ts` → FAIL.
- [ ] **Implement** with WebCrypto (`ECDSA`, `P-256`, `SHA-256`).
- [ ] **Run** → PASS.
- [ ] **Live check:** add a temporary `/probe` route that calls `sendPush` with a bogus 64-hex token, `wrangler deploy`, call it. PASS = status 400 with reason `BadDeviceToken` (the Worker reached APNs over HTTP/2 and the key works). 403 `InvalidProviderToken` = wrong key or team. A network or protocol error = Workers can't reach APNs: stop and run the relay as a Node container behind Traefik (same code) before Task 3.
- [ ] Remove `/probe`; commit `feat(relay): APNs client`.

### Task 2: Work token check

**Files:** Create `tools/check-token.sh`, `tools/queries/inbox.graphql`, `tools/queries/pr-status.graphql`.

- [ ] Script reads `GITHUB_TOKEN` and `LOGIN`, runs the five inbox searches from Task 8 and the PR-status query on the first result, prints a count per section and the status JSON, and exits non-zero on any GraphQL error.
- [ ] **You run it with the work token**, fine-grained first and classic if the org's approval blocks fine-grained. PASS = every search returns without errors and the status has `statusCheckRollup` and `mergeable`.
- [ ] **You prove write access:** add and then delete one comment on your own open work PR with `gh api` and the token.
- [ ] Commit `chore: token check script`.

---

## Part 1 — Relay (`relay/`)

### Task 3: Webhook signature, device registry, routes

**Files:** Create `relay/src/env.ts`, `relay/src/verify.ts`, `relay/src/devices.ts`, `relay/src/index.ts`; tests `relay/test/verify.test.ts`, `relay/test/devices.test.ts`, `relay/test/routes.test.ts` (Map-backed fake KV).

**Interfaces — Consumes:** `ApnsEnvironment` (Task 1). **Produces:**
- `interface Env { MERGEABLE: KVNamespace; WEBHOOK_SECRET: string; REGISTRATION_SECRET: string; NOTIFIER_APP_ID: string; NOTIFIER_PRIVATE_KEY: string; APNS_KEY_ID: string; APNS_TEAM_ID: string; APNS_PRIVATE_KEY: string; SELF_LOGIN: string }`
- `verifySignature(secret: string, rawBody: string, header: string | null): Promise<boolean>` — `X-Hub-Signature-256`, HMAC-SHA256, constant-time compare
- `interface Device { token: string; platform: "ios" | "macos"; environment: ApnsEnvironment }`
- `registerDevice(kv: KVNamespace, d: Device): Promise<void>`, `removeDevice(kv, token: string): Promise<void>`, `listDevices(kv): Promise<Device[]>` — KV keys `device:<token>`
- Routes: `POST /devices` (JSON `Device`, `Authorization: Bearer <REGISTRATION_SECRET>`) → 204 · `DELETE /devices/:token` (same auth) → 204 · `POST /webhook` → 401 on bad signature, else 202 with the work in `ctx.waitUntil` · `GET /health` → 200 `ok` · anything else → 404

- [ ] **Write failing tests:** valid, invalid and missing signature; register → list → remove; wrong bearer → 401; bad JSON or unknown platform/environment → 400; unknown route → 404.
- [ ] **Run** `npx vitest run` → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit `feat(relay): webhook auth and device registry`.

### Task 4: Event classification and copy

**Files:** Create `relay/src/events.ts`, `relay/src/copy.ts`; tests `relay/test/events.test.ts`, `relay/test/copy.test.ts`, fixtures in `relay/test/fixtures/`.

**Interfaces — Produces:**
- `type EventKind = "mergeReady" | "opened" | "readyForReview" | "reviewRequested" | "reviewSubmitted" | "comment" | "checksFailed" | "merged" | "closed"`
- `interface PRRef { owner: string; repo: string; number: number }`
- `interface Notice { kind: EventKind; pr: PRRef; prTitle: string; url: string; actor?: string; reviewState?: "approved" | "changes_requested" | "commented" }`
- `interface Classified { notices: Notice[]; evaluate: PRRef[]; sha?: { owner: string; repo: string; sha: string; failed: boolean } }`
- `classify(event: string, payload: unknown, selfLogin: string): Classified`
- `renderAlert(n: Notice): { title: string; subtitle: string; body: string }` — copy table in Global Constraints

Rules (logins compared case-insensitively; "self" = `sender.login` equals `selfLogin`):

| event · action | notice | evaluate |
|---|---|---|
| pull_request · opened | opened, even if self | the PR |
| pull_request · ready_for_review | readyForReview unless self | the PR |
| pull_request · synchronize, reopened | — | the PR |
| pull_request · review_requested | reviewRequested only if `requested_reviewer.login` is self | — |
| pull_request · closed | merged (if `merged`) or closed, unless self | — |
| pull_request_review · submitted | reviewSubmitted unless self | — |
| issue_comment · created, on a PR | comment unless self | — |
| check_suite · completed | checksFailed for each PR if conclusion is failure or timed_out | each PR in `check_suite.pull_requests` |
| status | — | `sha` set, `failed` = state is failure or error |
| anything else | — | — |

- [ ] **Write failing tests:** one per table row, each self case, `issue_comment` on a plain issue → nothing, `renderAlert` for every kind and all three review states.
- [ ] **Run** → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit `feat(relay): classify webhook events`.

### Task 5: Merge-ready check

**Files:** Create `relay/src/githubApp.ts`, `relay/src/mergeReady.ts`, `relay/src/dedupe.ts`; tests for each.

**Interfaces — Consumes:** `PRRef` (Task 4). **Produces:**
- `appJwt(appId: string, pkcs8Pem: string, nowSeconds: number): Promise<string>` — RS256, `iat = now - 60`, `exp = now + 540`, `iss = appId`
- `installationToken(jwt: string, installationId: number): Promise<string>` — POST `/app/installations/{id}/access_tokens`
- `interface PRStatus { state: "OPEN" | "CLOSED" | "MERGED"; isDraft: boolean; mergeable: "MERGEABLE" | "CONFLICTING" | "UNKNOWN"; rollup: "SUCCESS" | "PENDING" | "FAILURE" | "ERROR" | "EXPECTED" | null; headOid: string; title: string; url: string; author: string | null }`
- `fetchPRStatus(token: string, pr: PRRef): Promise<PRStatus>` — exactly the PR-status query in Task 8
- `prsForSha(token: string, owner: string, repo: string, sha: string): Promise<number[]>` — GET `/repos/{owner}/{repo}/commits/{sha}/pulls`, open PRs only
- `isMergeReady(s: PRStatus): boolean` — the Global Constraints definition
- `firstTime(kv: KVNamespace, key: string, ttlSeconds: number): Promise<boolean>` — key `ready:<owner>/<repo>#<number>@<headOid>`, TTL 2592000

GitHub hands out the App key as PKCS#1. Convert once with `openssl pkcs8 -topk8 -nocrypt -in notifier.pem -out notifier.pkcs8.pem` before `wrangler secret put NOTIFIER_PRIVATE_KEY`.

- [ ] **Write failing tests:** `isMergeReady` table (draft → false, closed → false, pending → false, failure → false, conflicting → false, UNKNOWN mergeable with SUCCESS → true, null rollup → true); `appJwt` verified with an RSA key generated in the test; `fetchPRStatus` maps a fixture GraphQL response; `firstTime` true then false; `prsForSha` drops closed PRs.
- [ ] **Run** → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit `feat(relay): merge-ready check`.

### Task 6: Wire up, deploy, register the GitHub Apps

**Files:** Create `relay/src/handle.ts`, `relay/test/handle.test.ts`, `docs/setup.md`; modify `relay/src/index.ts`.

**Interfaces — Consumes:** Tasks 1, 3, 4, 5. **Produces:** `handleWebhook(env: Env, event: string, payload: any): Promise<void>` — classify → if `sha`, resolve PRs (add checksFailed notices when `failed`, add PRs to evaluate) → for each evaluate PR: installation token from `payload.installation.id`, `fetchPRStatus`, and if `isMergeReady` and `firstTime` add a mergeReady notice → `renderAlert` → `sendPush` to every device with `aps.alert` = the rendered alert, `aps.sound` = `default`, `aps.thread-id` = `<owner>/<repo>#<number>`, and `mergeable: { v: 1, kind, owner, repo, number, url }`. On APNs 410, or 400 `BadDeviceToken` from the device's own environment host, call `removeDevice`.

- [ ] **Write failing tests** (stub `fetch`, fake KV): check_suite success on a ready PR → one push per device; the same delivery twice → one push; ready_for_review sent by self with green checks → mergeReady push and no readyForReview push (Review Focus 1); opened PR with no checks → opened + mergeReady (Review Focus 2); a sandbox device is pushed via the sandbox host and a production device via the production host (Review Focus 5); 410 removes the device.
- [ ] **Run** → FAIL. **Implement.** **Run** → PASS.
- [ ] **Write `docs/setup.md`, then you do it:**
  - Register **Mergeable** (owner: your account; installable only on this account; Device Flow on; expiring user tokens on; webhook off; permissions Pull requests RW, Contents RW, Checks R, Commit statuses R, Metadata R). Note its client ID for Task 12.
  - Register **Mergeable Notifier** (installable only on this account; webhook URL `https://push.pluth.org/webhook` with a generated secret; permissions Pull requests R, Issues R, Checks R, Commit statuses R, Metadata R; events Pull request, Pull request review, Issue comment, Check suite, Status). Download its private key.
  - Install both on your personal account, all repositories.
  - Create the KV namespace, put every `Env` secret, set `SELF_LOGIN` to your personal login, deploy, and route `push.pluth.org` to the Worker.
- [ ] **Verify:** `curl https://push.pluth.org/health` → `ok`; the Notifier's Recent Deliveries show 202 responses.
- [ ] Commit, open a PR, mark it ready.

---

## Part 2 — Core (`MergeableCore/`)

### Task 7: Accounts, routing, merge-readiness

**Files:** Create `MergeableCore/Package.swift` (Swift 6; library `MergeableCore`, test target `MergeableCoreTests`), `Sources/MergeableCore/Account.swift`, `Routing.swift`, `MergeReadiness.swift`; tests `RoutingTests.swift`, `MergeReadinessTests.swift`.

**Interfaces — Produces:**
- `struct AccountID: Hashable, Codable, Sendable { let rawValue: String }`
- `enum Connection: String, Codable, Sendable { case githubApp, pat }`
- `enum AccountColor: String, Codable, CaseIterable, Sendable { case blue, orange, green, purple, red, gray }`
- `struct Account: Codable, Hashable, Sendable, Identifiable { var id: AccountID; var login: String; var label: String; var color: AccountColor; var connection: Connection; var orgs: [String]; var opensInLinear: Bool }`
- `struct PRKey: Hashable, Codable, Sendable { let owner: String; let repo: String; let number: Int }` — `init` lowercases owner and repo
- `enum Route: Equatable, Sendable { case account(AccountID), ambiguous([AccountID]), unowned }`
- `struct Router: Sendable { var accounts: [Account]; var manualOwners: [String: AccountID]; var remembered: [PRKey: AccountID]; func route(_ pr: PRKey, fetchedBy: Set<AccountID>) -> Route }`
- `enum CheckRollup: String, Codable, Sendable { case success = "SUCCESS", pending = "PENDING", failure = "FAILURE", error = "ERROR", expected = "EXPECTED" }`
- `enum PRState: String, Codable, Sendable { case open = "OPEN", closed = "CLOSED", merged = "MERGED" }`
- `enum MergeableState: String, Codable, Sendable { case mergeable = "MERGEABLE", conflicting = "CONFLICTING", unknown = "UNKNOWN" }`
- `struct PRStatus: Codable, Hashable, Sendable { var state: PRState; var isDraft: Bool; var mergeable: MergeableState; var rollup: CheckRollup?; var headOid: String }`
- `func isMergeReady(_ s: PRStatus) -> Bool`

Routing, in order: `manualOwners` → owner claimed by exactly one account (its login or one of its orgs) → claimed by several = `.ambiguous` → unclaimed: one fetching account = that one, several = `remembered` or `.ambiguous`, none = `.unowned`. Every owner comparison is case-insensitive.

- [ ] **Write failing tests** (Swift Testing): `ownerMapWins`, `manualOverridesOrgClaim`, `ownerClaimedByTwoIsAmbiguous`, `unmappedUsesFetchingAccount`, `fetchedByBothUsesRememberedChoice`, `fetchedByBothWithoutChoiceIsAmbiguous`, `noOwnerIsUnowned`, `ownerIsCaseInsensitive` (`#expect(router.route(PRKey(owner: "anthonypluth", repo: "x", number: 1), fetchedBy: []) == .account(personal.id))` where the personal login is `AnthonyPluth`); merge-readiness cases identical to Task 5's table.
- [ ] **Run** `cd MergeableCore && swift test` → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit `feat(core): accounts, routing, merge-readiness`.

### Task 8: GitHub client

**Files:** Create `Sources/MergeableCore/HTTP.swift`, `Models.swift`, `Queries.swift`, `GitHubClient.swift`; tests `GitHubClientTests.swift` with JSON fixtures.

**Interfaces — Consumes:** Task 7 types. **Produces:**
- `protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }` and `struct URLSessionTransport: HTTPTransport` (imports `FoundationNetworking` on Linux)
- `protocol TokenProvider: Sendable { func token(for account: AccountID, owner: String) async throws -> String }`
- `enum GitHubError: Error, Equatable { case unauthorized(AccountID), headChanged, notFound, http(Int), graphQL(String) }`
- `enum InboxSection: String, CaseIterable, Codable, Sendable { case needsReview, yours, assignedOrMentioned }`
- `struct PullRequestSummary: Codable, Hashable, Sendable { var nodeID: String; var key: PRKey; var title: String; var url: URL; var author: String?; var baseBranch: String; var status: PRStatus; var reviewDecision: String?; var updatedAt: Date; var commentCount: Int; var lastCommentAuthor: String?; var reviewCount: Int; var lastReviewAuthor: String?; var lastReviewState: String? }`
- `struct InboxSnapshot: Codable, Sendable { var sections: [InboxSection: [PullRequestSummary]] }`
- `struct PullRequestDetail: Sendable { var summary: PullRequestSummary; var body: String; var timeline: [TimelineItem]; var checks: [CheckContext] }` with `TimelineItem` (author, date, kind comment/review, review state, body) and `CheckContext` (name, state, url)
- `struct ChangedFile: Codable, Sendable { var path: String; var status: String; var additions: Int; var deletions: Int; var patch: String? }`
- `enum ReviewEvent: String, Sendable { case approve = "APPROVE", requestChanges = "REQUEST_CHANGES", comment = "COMMENT" }`
- `enum MergeMethod: String, Codable, Sendable { case merge = "MERGE", squash = "SQUASH", rebase = "REBASE" }`
- `final class GitHubClient: Sendable` — `init(transport: HTTPTransport, tokens: TokenProvider, onUnauthorized: @escaping @Sendable (AccountID) -> Void)`; async throwing methods `inbox(for: Account) -> InboxSnapshot`, `detail(_: PRKey, as: AccountID) -> PullRequestDetail`, `files(_: PRKey, as: AccountID) -> [ChangedFile]` (REST `/pulls/{n}/files`, follows `Link` pagination), `status(_: PRKey, as: AccountID) -> PRStatus`, `comment(prNodeID: String, body: String, as: AccountID)`, `submitReview(prNodeID: String, event: ReviewEvent, body: String?, as: AccountID)`, `merge(prNodeID: String, method: MergeMethod, expectedHeadOid: String, as: AccountID)`, `markReady(prNodeID: String, as: AccountID)`, `close(prNodeID: String, as: AccountID)`, `reopen(prNodeID: String, as: AccountID)`

Inbox searches (GraphQL `search(type: ISSUE, first: 50)`), de-duplicated by `nodeID` within a section:
- needsReview: `is:pr is:open archived:false review-requested:@me`
- yours: `is:pr is:open archived:false author:@me` and `is:pr is:open archived:false user:<login>`
- assignedOrMentioned: `is:pr is:open archived:false assignee:@me` and `is:pr is:open archived:false mentions:@me`

PR-status query, shared with the relay:

```graphql
query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){title url state isDraft mergeable headRefOid author{login} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}
```

Every call uses only the `as:` account's token. HTTP 401 → `onUnauthorized(account)` and throw `.unauthorized`, with no retry on any other token. GitHub's error for a stale `expectedHeadOid` maps to `.headChanged`.

- [ ] **Write failing tests:** `inboxRunsFiveSearchesAndDedupes`, `usesOnlyTheGivenAccountsToken` (assert the `Authorization` header per call), `unauthorizedNeverFallsBack`, `mergeSendsExpectedHeadOid`, `staleHeadMapsToHeadChanged` (Review Focus 3), `filesFollowsPagination`, `fileWithoutPatchDecodes`.
- [ ] **Run** → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit `feat(core): GitHub client`.

### Task 9: Device flow

**Files:** Create `Sources/MergeableCore/DeviceFlow.swift`; tests `DeviceFlowTests.swift`.

**Interfaces — Consumes:** `HTTPTransport` (Task 8). **Produces:**
- `struct DeviceCode: Sendable { var deviceCode: String; var userCode: String; var verificationURL: URL; var interval: Int; var expiresAt: Date }`
- `struct AppTokens: Codable, Sendable { var accessToken: String; var accessExpiry: Date; var refreshToken: String; var refreshExpiry: Date }`
- `struct DeviceFlow: Sendable { let clientID: String; let transport: HTTPTransport; func start() async throws -> DeviceCode; func poll(_ code: DeviceCode, sleep: @Sendable (Int) async -> Void) async throws -> AppTokens; func refresh(_ refreshToken: String) async throws -> AppTokens }`

POST `https://github.com/login/device/code` and `https://github.com/login/oauth/access_token` with `Accept: application/json`; no `client_secret` in any request. `authorization_pending` keeps polling; `slow_down` adds 5 seconds; `expired_token` and `access_denied` throw.

- [ ] **Write failing tests:** `noClientSecretEverSent`, `pendingThenSuccess`, `slowDownAddsFiveSeconds`, `refreshReturnsNewPair`, `expiryDatesComeFromExpiresIn`.
- [ ] **Run** → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit `feat(core): device flow`.

### Task 10: Change detection and alert copy

**Files:** Create `Sources/MergeableCore/ChangeDetector.swift`, `NotificationCopy.swift`; tests `ChangeDetectorTests.swift`, `NotificationCopyTests.swift`.

**Interfaces — Consumes:** Tasks 7, 8. **Produces:**
- `enum InboxEvent: Equatable, Sendable { case mergeReady(PRKey, title: String), opened(PRKey, title: String), readyForReview(PRKey, title: String), reviewRequested(PRKey, title: String), reviewSubmitted(PRKey, title: String, by: String, state: String), comment(PRKey, title: String, by: String), checksFailed(PRKey, title: String), merged(PRKey, title: String, by: String), closed(PRKey, title: String, by: String) }`
- `struct ClosedOutcome: Sendable { var merged: Bool; var by: String? }`
- `struct ChangeDetector: Sendable { let selfLogin: String; func events(previous: InboxSnapshot?, current: InboxSnapshot, closed: [PRKey: ClosedOutcome], notifiedReady: inout Set<String>) -> [InboxEvent] }` — `notifiedReady` holds `"<owner>/<repo>#<number>@<headOid>"`
- `enum NotificationCopy { static func render(_ e: InboxEvent) -> (title: String, subtitle: String, body: String) }` — the Global Constraints table

Rules: `previous == nil` → no events, but already-ready PRs go into `notifiedReady` (Review Focus 4). New in needsReview → reviewRequested. New in yours with author ≠ self → opened. Draft → not draft with author ≠ self → readyForReview. Comment count up and last commenter ≠ self → comment. Review count up and last reviewer ≠ self → reviewSubmitted. Rollup became FAILURE or ERROR → checksFailed. Became merge-ready, key not in `notifiedReady`, and (author == self or owner == self) → mergeReady. In `previous`, gone from `current` → merged or closed from `closed`, unless `by` is self.

- [ ] **Write failing tests:** one per rule, plus `firstSnapshotIsBaseline`, `sameHeadAlertsOnce`, `newHeadAlertsAgain`, `copyMatchesRelayTable` (the exact strings from Task 4's copy test).
- [ ] **Run** → FAIL. **Implement.** **Run** → PASS.
- [ ] Commit, open a PR for Part 2, mark it ready.

---

## Part 3 — App (`App/`, needs Xcode)

### Task 11: GitHub look and mockup sign-off

**Files:** Create `tools/primer/package.json`, `tools/primer/build-assets.mjs`, `App/Shared/Theme.swift`; generated `App/Shared/Assets.xcassets/Colors/*.colorset` and `App/Shared/Assets.xcassets/Octicons/*.imageset`.

- [ ] Script reads `@primer/primitives` light and dark functional tokens (`fgColor.default`, `fgColor.muted`, `fgColor.accent`, `fgColor.open`, `fgColor.closed`, `fgColor.done`, `fgColor.success`, `fgColor.danger`, `fgColor.attention`, `bgColor.default`, `bgColor.muted`, `borderColor.default`) and writes one colorset each with light and dark appearances. It copies these 16px Octicons from `@primer/octicons`: git-pull-request, git-pull-request-draft, git-merge, git-pull-request-closed, check-circle-fill, x-circle-fill, dot-fill, comment, eye, check, file-diff, bell, person.
- [ ] `Theme.swift`: `enum PRVisualState { case open, draft, merged, closed }` with `color: Color` and `icon: Image`, using the Global Constraints mapping.
- [ ] Make mockups (Design artifacts) of the Inbox (All tab, three sections, account badges) and the PR detail (header, checks, "as @login" actions, merge sheet), iPhone and Mac sizes, using these tokens and icons.
- [ ] **Gate: you sign off on the mockups before Task 13 starts.**
- [ ] Run the script, commit the generated assets.

### Task 12: Project, Keychain, accounts

**Files:** Create `App/project.yml` (XcodeGen: one multiplatform app target `Mergeable` for iOS and macOS, bundle `com.pluth.mergeable`, local package `../MergeableCore`, capabilities Push Notifications, Background Modes fetch + remote-notification, iCloud key-value storage, Keychain Sharing), `App/Shared/KeychainStore.swift`, `App/Shared/AccountStore.swift`, `App/Shared/Settings/AddAccountView.swift`, `AccountDetailView.swift`, `OwnerMapView.swift`; test target `MergeableTests`.

**Interfaces — Consumes:** `TokenProvider`, `DeviceFlow`, `Account`, `Router`. **Produces:**
- `final class KeychainStore: TokenProvider` — items keyed `token.<accountID>.<owner or *>`; `kSecAttrSynchronizable` follows the account's sync switch; GitHub App tokens are refreshed through `DeviceFlow.refresh` when less than 5 minutes remain
- `@MainActor final class AccountStore: ObservableObject` — `accounts`, `router`, `needsAttention: Set<AccountID>`; non-secret data persisted in `NSUbiquitousKeyValueStore`

- [ ] Add account: GitHub App → show the user code, open the verification URL, poll. PAT → paste field with the permission list and the 15-minute note. On save, read `/user` and `/user/orgs` for login and orgs. A per-account "Open in Linear" switch.
- [ ] Owner map: owners per account, ambiguous owners flagged until you assign them.
- [ ] **Test** `keychainRoundTripRespectsSyncFlag`; **build** `xcodebuild -scheme Mergeable -destination 'generic/platform=iOS' build` and `xcodebuild -scheme Mergeable -destination 'platform=macOS' build` → both succeed.
- [ ] **Manual:** add both accounts on the Mac; they appear on the iPhone after iCloud syncs.
- [ ] Commit, open a PR, mark it ready.

### Task 13: Inbox, PR detail, actions

**Files:** Create `App/Shared/Inbox/InboxView.swift`, `PRRow.swift`, `App/Shared/Detail/PRDetailView.swift`, `DiffView.swift`, `ActionBar.swift`, `MergeSheet.swift`.

- [ ] Tabs: All, then one per account; each has the three sections. Rows show repo, title, author, checks icon, review state, age and the account badge (label + color).
- [ ] Detail: description, timeline, checks, and files with read-only diffs. A file with no patch shows "Too large to show here" and a link to github.com.
- [ ] Actions call `Router.route` at tap time. `.ambiguous` → ask which account and remember. `.unowned` → read-only banner with the reason. Button titles per Global Constraints. Merge sheet: account, method (remembered per repo), target branch. `.headChanged` → "This PR changed since you opened it" and reload (Review Focus 3).
- [ ] "Open in Linear" for accounts with `opensInLinear`: `https://linear.review/<owner>/<repo>/pull/<number>`.
- [ ] **Verify** against the approved mockups on both platforms, with screenshots side by side.
- [ ] Commit, open a PR, mark it ready.

### Task 14: Notifications and background work

**Files:** Create `App/Shared/Notifications/PushRegistration.swift`, `LocalAlerts.swift`, `Poller.swift`, `App/Shared/Unread.swift`, `App/iOS/BackgroundRefresh.swift`, `App/macOS/MenuBar.swift`.

- [ ] Push: register for remote notifications; POST `{token, platform, environment}` to `https://push.pluth.org/devices` with the registration secret (stored in the Keychain, synced). `environment` = `sandbox` for Debug builds, `production` for Release. Tapping opens the PR from the payload's `mergeable` object.
- [ ] Poller (PAT accounts): every 900 seconds, `inbox(for:)`, then `status` for PRs that disappeared, then `ChangeDetector.events`, then `NotificationCopy.render` into a local notification. Snapshots and `notifiedReady` persist per account.
- [ ] iOS: `BGAppRefreshTask` id `com.pluth.mergeable.refresh`, `earliestBeginDate` = now + 900 seconds, rescheduled every run. Each run's time is logged and shown in Settings → Diagnostics.
- [ ] macOS: `MenuBarExtra` with counts per account, a 900-second timer, and launch at login via `SMAppService.mainApp`.
- [ ] Unread = activity since you last opened the PR, stored in `NSUbiquitousKeyValueStore` by PR node ID.
- [ ] **Manual:** a personal PR's checks go green → alert on iPhone and Mac within about a minute; a work PR goes green → Mac alert within 15 minutes; delete and reinstall → no flood of alerts (Review Focus 4).
- [ ] Commit, open a PR, mark it ready.

### Task 15: End-to-end check

- [ ] In a personal test repo, open a PR from your account with a passing workflow → "New pull request", then "Ready to merge" once.
- [ ] Push another commit → "Ready to merge" again for the new commit.
- [ ] Merge it from the iPhone; GitHub shows your personal account as the merger.
- [ ] Comment on a work PR from the Mac; GitHub shows your work account as the author.
- [ ] Revoke the work token → the work account shows "needs attention" and no action uses the personal token.
- [ ] After 3 days, read Diagnostics for the real iPhone refresh frequency and note it in the README.
