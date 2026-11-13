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
