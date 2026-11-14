# Mergeable

An iPhone and Mac app that shows personal and work GitHub pull requests together, acts on each PR as the account that owns its repo, and alerts when a PR is merge-ready. The repository is public.

- `relay/`: Cloudflare Worker (TypeScript, Vitest). `MergeableCore/`: Swift package, Foundation only. `App/`: SwiftUI, built only by CI's macOS job. `tools/`: scripts.
- Private data would look like: a real GitHub token, a `.p8` APNs key, a `.pem` private key, `.dev.vars` contents, a device token, or a real account's login, repository name or PR title in a fixture. Likeliest places: relay and core test fixtures, `docs/mockups/`, screenshots.
- Generated or vendored: `relay/package-lock.json`; `.claude/skills/fleet-*`, `.claude/agents/fleet-*`, `.claude/hooks/fleet-*`, `tools/fleet` and the fleet blocks of `AGENTS.md` come from fleet and change only there.
- Matter most in `AGENTS.md`: "Conventions" (the plan's Global Constraints), "Review focus" and "Mistakes that keep coming back".
