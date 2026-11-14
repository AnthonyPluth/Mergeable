# Work token check

Mergeable reads your work pull requests with a personal access token (PAT). Before building on it, confirm the token can do everything the app needs. Steps marked **YOU** can only be done by you, in your GitHub account.

## 1. Create the token (YOU)

Create one token per organisation. Try a fine-grained PAT first.

**Fine-grained PAT** (GitHub, Settings, Developer settings, Personal access tokens, Fine-grained tokens):

- Resource owner: the work organisation.
- Repository access: the repositories whose PRs you want in Mergeable (or all repositories).
- Permissions:
  - Pull requests: Read and write
  - Contents: Read and write
  - Metadata: Read-only
  - Commit statuses: Read-only
  - Checks: Read-only

If the organisation requires owner approval for fine-grained tokens and the approval blocks you, or the token cannot see the repositories, use a **classic PAT** instead (Settings, Developer settings, Tokens (classic)) with the `repo` scope, and authorise it for the organisation's SSO if prompted.

Never paste the token into chat, commits or issues. Keep it in your password manager.

## 2. Run the script (YOU)

Needs `curl` and `jq`. The token is read from the `GITHUB_TOKEN` environment variable only, and is never printed.

```sh
read -rs GITHUB_TOKEN && export GITHUB_TOKEN    # paste the token, press Enter
tools/check-token.sh <owner> <repo> <pr-number> --login <your-login-or-org>
```

Use one of your own open work PRs for `<owner> <repo> <pr-number>`. `--login` adds the `user:<login>` search (use the org name for an org-scoped token); leave it out to skip that search.

PASS means every line starts with `OK`, the PR-status output shows `statusCheckRollup field: true, mergeable field: true`, and the last line is `SUMMARY: PASS`. Any HTTP error or GraphQL error prints one `FAIL` line with the first error message and exits non-zero. Common causes: a missing permission from the list above, a repository not selected for a fine-grained token, or SSO not authorised.

## 3. Prove write access (YOU)

On your own open work PR, add one comment and delete it again, using the same token:

```sh
id=$(gh api repos/<owner>/<repo>/issues/<pr-number>/comments -f body='Mergeable token check' --jq .id)
gh api -X DELETE repos/<owner>/<repo>/issues/comments/$id
```

`gh` reads `GITHUB_TOKEN` from the environment. Both calls must succeed (the delete returns no output). Then report PASS or the error on issue #3.
