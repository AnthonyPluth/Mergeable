# Mergeable

An iPhone and Mac app that shows personal and work GitHub pull requests together, acts on each PR as the account that owns its repo, and alerts you when a PR is ready to merge.

- Design: [docs/superpowers/specs/2026-11-13-mergeable-design.md](docs/superpowers/specs/2026-11-13-mergeable-design.md)
- Build plan: [docs/superpowers/plans/2026-11-13-mergeable.md](docs/superpowers/plans/2026-11-13-mergeable.md)

| Folder | What |
| --- | --- |
| `relay/` | Cloudflare Worker that turns the notifier GitHub App's webhooks into Apple pushes |
| `MergeableCore/` | Swift package: routing, GitHub client, merge-readiness, polling |
| `App/` | SwiftUI app for iPhone and Mac |
| `tools/` | Scripts (token check, Primer assets) |

Repository settings are managed by Terraform in AnthonyPluth/Infrastructure.

## Status

All the code in the build plan is written and CI is green: the relay, `MergeableCore`, the app (inbox, PR detail, actions, notifications, menu bar item) and the agent setup. What is left needs the owner's accounts and devices:

| Issue | What |
| --- | --- |
| [#2](https://github.com/AnthonyPluth/Mergeable/issues/2) | Live APNs probe from a Worker (`docs/setup.md`, step 3) |
| [#3](https://github.com/AnthonyPluth/Mergeable/issues/3) | Run `tools/check-token.sh` with the work token (`docs/work-token.md`) |
| [#7](https://github.com/AnthonyPluth/Mergeable/issues/7) | Register the two GitHub Apps and deploy the relay (`docs/setup.md`) |
| [#16](https://github.com/AnthonyPluth/Mergeable/issues/16) | End-to-end check on real PRs and devices |

How the app gets its alerts, and what to set up in Settings, is in [docs/notifications.md](docs/notifications.md).

### iPhone background refresh

To fill in after about 3 days on a real iPhone (issue #16): how often iOS actually ran the 15-minute check, from the in-app refresh log. Not measured yet.

## Developing

- `relay/`: `npm ci`, `npm run typecheck`, `npm test`.
- `MergeableCore/`: `swift test` (Linux or macOS).
- `App/`: built by CI's macOS job (XcodeGen, then `xcodebuild`); screenshots from the fixture harness are uploaded as the `screenshots` artifact. Mockups are in `docs/mockups/`; regenerate the colors and icons with `node tools/primer/build-assets.mjs`.

See [AGENTS.md](AGENTS.md) for conventions.
